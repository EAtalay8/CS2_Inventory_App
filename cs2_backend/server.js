const express = require("express");
const axios = require("axios");
const cors = require("cors");
const cheerio = require("cheerio");


const app = express();
app.use(cors());


function parsePriceText(text) {
    if (!text) return null;

    // Örnek: "₺ 123,45", "$13.40", "1.234,56 TL"
    const m = text.match(/[\d.,]+/);
    if (!m) return null;

    let numStr = m[0];

    // Türk formatı: 1.234,56  ->  1234.56
    if (numStr.includes(",") && numStr.includes(".")) {
        numStr = numStr.replace(/\./g, "").replace(",", ".");
    }
    // Sadece virgül varsa: 123,45 -> 123.45
    else if (numStr.includes(",") && !numStr.includes(".")) {
        numStr = numStr.replace(",", ".");
    }
    // Sadece nokta varsa: olduğu gibi bırak

    const val = parseFloat(numStr);
    return isNaN(val) ? null : val;
}

async function scrapeSteamMarketPrice(marketName) {
    const encoded = encodeURIComponent(marketName);
    const url = `https://steamcommunity.com/market/listings/730/${encoded}`;

    console.log("Scraping:", url);

    try {
        const response = await axios.get(url, {
            timeout: 10000,
            headers: {
                // Normal browser gibi görünelim
                "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"
            }
        });

        const html = response.data;

        // 1) Önce sayfada gömülü JSON içindeki "lowest_price" alanını dene
        const jsonMatch = html.match(/"lowest_price":"([^"]+)"/);
        let priceText = null;

        if (jsonMatch && jsonMatch[1]) {
            priceText = jsonMatch[1];
        } else {
            // 2) Bulamazsak, HTML'deki fiyat label'ını dene
            const $ = cheerio.load(html);
            // market_listing_price_with_fee class'lı ilk elementi al
            priceText = $(".market_listing_price_with_fee").first().text().trim();
        }

        const price = parsePriceText(priceText);
        return { price, raw: priceText };

    } catch (err) {
        console.log("Scrape error:", err.message);
        return { price: null, raw: null };
    }
}


app.get("/inventory/:steamid", async (req, res) => {
    const steamId = req.params.steamid;
    const appId = 730;
    const contextId = 2;

    let startAssetId = "";
    let assets = [];
    let descriptions = {};
    let visitedPages = new Set();

    try {
        while (true) {
            console.log("Fetching page:", startAssetId || "first");

            const url =
                `https://steamcommunity.com/inventory/${steamId}/${appId}/${contextId}` +
                `?l=english&count=200${startAssetId ? "&start_assetid=" + startAssetId : ""}`;

            const response = await axios.get(url);
            const data = response.data;

            if (!data || !data.assets) {
                return res.json({ success: false, error: "Inventory not found" });
            }

            assets.push(...data.assets);

            if (data.descriptions) {
                for (let d of data.descriptions) {
                    descriptions[d.classid] = d;
                }
            }

            if (!data.more_items) break;

            if (visitedPages.has(data.last_assetid)) break;

            visitedPages.add(data.last_assetid);
            startAssetId = data.last_assetid;
        }

        const merged = [];

        for (let asset of assets) {
            const meta = descriptions[asset.classid] || {};
            const name = meta.market_name || meta.name || "Unknown";

            merged.push({
                assetid: asset.assetid,
                classid: asset.classid,
                name,
                icon: meta.icon_url
                    ? `https://steamcommunity-a.akamaihd.net/economy/image/${meta.icon_url}`
                    : null,
                type: meta.type || "",
            });
        }

        return res.json({
            success: true,
            total: merged.length,
            items: merged
        });

    } catch (err) {
        console.log("ERROR:", err.message);
        return res.json({ success: false, error: err.message });
    }
});


// ---------------------------------------
//  AŞAMA 1: FİYAT HELPER + CACHE
// ---------------------------------------

// Basit RAM cache: { "AK-47 | Redline (Field-Tested)": { price, time } }
const priceCache = {};
const PRICE_TTL = 1000 * 60 * 10; // 10 dakika

// "$13.40" gibi string'den sayıyı çıkar
function parseSteamPrice(str) {
    if (!str) return null;
    const match = str.match(/[\d.,]+/);
    if (!match) return null;
    const normalized = match[0].replace(/,/g, "");
    const val = parseFloat(normalized);
    return isNaN(val) ? null : val;
}

// Tek bir market_name için fiyat çeken helper
async function fetchPriceForMarketName(marketName) {
    // 1) Cache kontrolü
    const cached = priceCache[marketName];
    if (cached && (Date.now() - cached.time < PRICE_TTL)) {
        return cached.price;
    }

    const encoded = encodeURIComponent(marketName);
    const url = `https://steamcommunity.com/market/priceoverview/?currency=1&appid=730&market_hash_name=${encoded}`;

    try {
        const response = await axios.get(url, { timeout: 7000 });
        const data = response.data;

        if (!data || !data.success) {
            console.log("Steam priceoverview success=false:", marketName);
            return null;
        }

        const priceStr = data.median_price || data.lowest_price;
        const price = parseSteamPrice(priceStr);

        // Cache'e yaz
        priceCache[marketName] = {
            price,
            time: Date.now()
        };

        return price;
    } catch (err) {
        if (err.response && err.response.status === 429) {
            console.log("Steam 429 rate limit:", marketName);
            // Rate limitte, varsa eski cache değerini dönebiliriz
            if (priceCache[marketName]) {
                return priceCache[marketName].price;
            }
        }

        console.log("Price fetch error:", marketName, "->", err.message);
        return null;
    }
}

// -------------------------------
// SCRAPER PRICE ENDPOINT
// -------------------------------
app.get("/scrape-price/:marketName", async (req, res) => {
    const marketName = req.params.marketName;
    const result = await scrapeSteamMarketPrice(marketName);
    return res.json(result);
});



// Debug / tek item fiyat görmek için:
// GET /price/AK-47%20%7C%20Redline%20%28Field-Tested%29
app.get("/price/:marketName", async (req, res) => {
    const marketName = req.params.marketName;
    const price = await fetchPriceForMarketName(marketName);
    return res.json({ marketName, price});
});

// ---------------------------------------
//  ENVANTER + FİYATLI ENDPOINT
//  GET /inventory/:steamid/priced
// ---------------------------------------

app.get("/inventory/:steamid/priced", async (req, res) => {
    const steamId = req.params.steamid;

    // Önce normal envanteri alalım (yukarıdaki kodu tekrar yazmamak için)
    const appId = 730;
    const contextId = 2;

    let startAssetId = "";
    let assets = [];
    let descriptions = {};
    let visitedPages = new Set();

    try {
        while (true) {
            console.log("Fetching page (priced):", startAssetId || "first");

            const url =
                `https://steamcommunity.com/inventory/${steamId}/${appId}/${contextId}` +
                `?l=english&count=200${startAssetId ? "&start_assetid=" + startAssetId : ""}`;

            const response = await axios.get(url);
            const data = response.data;

            if (!data || !data.assets) {
                return res.json({ success: false, error: "Inventory not found" });
            }

            assets.push(...data.assets);

            if (data.descriptions) {
                for (let d of data.descriptions) {
                    descriptions[d.classid] = d;
                }
            }

            if (!data.more_items) break;

            if (visitedPages.has(data.last_assetid)) break;

            visitedPages.add(data.last_assetid);
            startAssetId = data.last_assetid;
        }

        // 1) Tüm itemleri oluştur
        const items = [];
        for (let asset of assets) {
            const meta = descriptions[asset.classid] || {};
            const name = meta.market_name || meta.name || "Unknown";

            items.push({
                assetid: asset.assetid,
                classid: asset.classid,
                name,
                icon: meta.icon_url
                    ? `https://steamcommunity-a.akamaihd.net/economy/image/${meta.icon_url}`
                    : null,
                type: meta.type || "",
            });
        }

        // 2) Unique market isimlerini çıkar
        const uniqueNames = Array.from(new Set(items.map(i => i.name)));

        console.log("Unique item count:", uniqueNames.length);

        // 3) Her unique isim için fiyat çek
        const priceMap = {};
        for (let name of uniqueNames) {
            const price = await fetchPriceForMarketName(name);
            priceMap[name] = price; // price null da olabilir, sorun değil
        }

        // 4) Itemlere price alanını ekle
        const pricedItems = items.map(item => ({
            ...item,
            price: priceMap[item.name] ?? null
        }));

        return res.json({
            success: true,
            total: pricedItems.length,
            items: pricedItems
        });

    } catch (err) {
        console.log("ERROR (priced):", err.message);
        return res.json({ success: false, error: err.message });
    }
});


app.listen(3000, '0.0.0.0', () => console.log("Backend running on port 3000"));
