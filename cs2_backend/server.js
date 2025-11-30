// server.js

const express = require("express");
const axios = require("axios");     
const cors = require("cors");
const cheerio = require("cheerio");

const app = express();
app.use(cors());

// -------------------- Genel helperlar --------------------

function delay(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
}

// "₺ 123,45", "$13.40", "1.234,56 TL" -> 123.45
function parseNumeric(text) {
    if (!text) return null;
    const m = text.match(/[\d.,]+/);
    if (!m) return null;

    let numStr = m[0];

    if (numStr.includes(",") && numStr.includes(".")) {
        // 1.234,56 -> 1234.56
        numStr = numStr.replace(/\./g, "").replace(",", ".");
    } else if (numStr.includes(",") && !numStr.includes(".")) {
        // 123,45 -> 123.45
        numStr = numStr.replace(",", ".");
    }
    const val = parseFloat(numStr);
    return isNaN(val) ? null : val;
}

// -------------------- INVENTORY FETCH --------------------

async function fetchInventory(steamId) {
    const appId = 730;
    const contextId = 2;

    let startAssetId = "";
    let assets = [];
    let descriptions = {};
    let visitedPages = new Set();

    while (true) {
        console.log("Fetching inventory page:", startAssetId || "first");

        const url =
            `https://steamcommunity.com/inventory/${steamId}/${appId}/${contextId}` +
            `?l=english&count=200${startAssetId ? "&start_assetid=" + startAssetId : ""}`;

        const response = await axios.get(url);
        const data = response.data;

        if (!data || !data.assets) {
            throw new Error("Inventory not found");
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

    const items = assets.map(asset => {
        const meta = descriptions[asset.classid] || {};
        return {
            assetid: asset.assetid,
            classid: asset.classid,
            name: meta.market_name || meta.name || "Unknown",
            icon: meta.icon_url
                ? `https://steamcommunity-a.akamaihd.net/economy/image/${meta.icon_url}`
                : null,
            type: meta.type || "",
        };
    });

    return items;
}

// sade inventory endpoint (fiyatsız)
app.get("/inventory/:steamid", async (req, res) => {
    try {
        const items = await fetchInventory(req.params.steamid);
        res.json({ success: true, total: items.length, items });
    } catch (err) {
        console.log("ERROR inventory:", err.message);
        res.json({ success: false, error: err.message });
    }
});

// -------------------- PRICEOVERVIEW (hızlı API) --------------------

const priceCache = {};
const PRICE_TTL = 1000 * 60 * 10; // 10 dk

async function fetchPriceForMarketName(marketName) {
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
            console.log("priceoverview success=false:", marketName);
            return null;
        }

        const priceStr = data.median_price || data.lowest_price;
        const price = parseNumeric(priceStr);

        priceCache[marketName] = { price, time: Date.now() };
        return price;
    } catch (err) {
        if (err.response && err.response.status === 429) {
            console.log("Steam 429 priceoverview:", marketName);
            if (priceCache[marketName]) {
                return priceCache[marketName].price;
            }
        }
        console.log("Priceoverview error:", marketName, "->", err.message);
        return null;
    }
}

// -------------------- SCRAPER (fallback) --------------------

const scraperCache = {};
const SCRAPER_TTL = 1000 * 60 * 60; // 1 saat

async function scrapeSteamMarketPrice(marketName) {
    const cached = scraperCache[marketName];
    if (cached && (Date.now() - cached.time < SCRAPER_TTL)) {
        return { price: cached.price, raw: cached.raw };
    }

    const encoded = encodeURIComponent(marketName);
    const url = `https://steamcommunity.com/market/listings/730/${encoded}`;

    console.log("Scraping:", marketName);

    let attempts = 0;
    while (attempts < 3) {
        try {
            const response = await axios.get(url, {
                timeout: 10000,
                headers: {
                    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"
                }
            });

            const html = response.data;

            let priceText = null;
            const jsonMatch = html.match(/"lowest_price":"([^"]+)"/);
            if (jsonMatch && jsonMatch[1]) {
                priceText = jsonMatch[1];
            } else {
                const $ = cheerio.load(html);
                priceText = $(".market_listing_price_with_fee").first().text().trim();
            }

            const price = parseNumeric(priceText);

            scraperCache[marketName] = {
                price,
                raw: priceText,
                time: Date.now()
            };

            return { price, raw: priceText };
        } catch (err) {
            if (err.response && err.response.status === 429) {
                console.log("429! Scraper backoff →", marketName);
                await delay(5000);
                attempts++;
                continue;
            }
            console.log("Scraper error:", marketName, "->", err.message);
            return { price: null, raw: null };
        }
    }

    return { price: null, raw: null };
}

// -------------------- Küçük yardımcı endpointler --------------------

app.get("/price/:marketName", async (req, res) => {
    const name = req.params.marketName;
    const price = await fetchPriceForMarketName(name);
    res.json({ marketName: name, price });
});

app.get("/scrape-price/:marketName", async (req, res) => {
    const name = req.params.marketName;
    const result = await scrapeSteamMarketPrice(name);
    res.json(result);
});

// -------------------- INVENTORY + PRICED --------------------

const PARALLEL_LIMIT = 3; // priceoverview için max paralel istek

async function runLimitedParallel(items, workerFn) {
    const result = [];
    let index = 0;

    async function worker() {
        while (index < items.length) {
            const i = index++;
            const r = await workerFn(items[i]);
            result[i] = r;
        }
    }

    const workers = [];
    for (let i = 0; i < PARALLEL_LIMIT; i++) {
        workers.push(worker());
    }

    await Promise.all(workers);
    return result;
}

app.get("/inventory/:steamid/priced", async (req, res) => {
    const steamId = req.params.steamid;
    const limit = parseInt(req.query.limit) || 20; // kaç tane fiyatlı item istiyoruz
    console.log("Price limit:", limit);

    try {
        // 1) Envanteri çek
        const items = await fetchInventory(steamId);

        // 2) İlk 'limit' itemi al (fiyatı olsun olmasın)
        const priceMap = {};

        const limitedItems = items.slice(0, limit);
        const limitedNames = limitedItems.map(i => i.name);

        console.log("Limited names:", limitedNames.length);

        for (const name of limitedNames) {
            await delay(350);

            let price = await fetchPriceForMarketName(name);

            // eğer overview fiyat vermediyse scraper dene
            if (price == null) {
                const scraped = await scrapeSteamMarketPrice(name);
                price = scraped.price;
            }

            // hala null ise kullanıcıya "fiyat yok" göster
            if (price == null) {
                price = "fiyat yok";
            }

            priceMap[name] = price;
        }

        // 3) itemlara price ekle
        const pricedItems = items.map(i => ({
            ...i,
            price: priceMap[i.name] ?? null
        }));

        return res.json({
            success: true,
            total: pricedItems.length,
            items: pricedItems
        });

    } catch (err) {
        console.log("ERROR priced:", err.message);
        return res.json({ success: false, error: err.message });
    }
});

// -------------------- SERVER --------------------

app.listen(3000, "0.0.0.0", () => console.log("Backend running on port 3000"));
