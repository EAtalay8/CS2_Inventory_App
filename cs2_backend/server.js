// server.js

const express = require("express");
const axios = require("axios");
const cors = require("cors");
const fs = require("fs");

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

const inventoryCache = {};
const INVENTORY_TTL = 1000 * 60 * 5; // 5 dakika cache

async function fetchInventory(steamId) {
    // Cache kontrolü
    const cached = inventoryCache[steamId];
    if (cached && (Date.now() - cached.time < INVENTORY_TTL)) {
        console.log("Serving inventory from cache:", steamId);
        return cached.items;
    }

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

        let response;
        let attempts = 0;
        while (attempts < 3) {
            try {
                response = await axios.get(url);
                break;
            } catch (err) {
                attempts++;
                console.log(`Fetch attempt ${attempts} failed: ${err.message}`);
                if (attempts >= 3) throw err;
                await delay(2000);
            }
        }
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
            marketable: meta.marketable // 1 or 0
        };
    });

    // Cache'e kaydet
    inventoryCache[steamId] = { items, time: Date.now() };

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

// -------------------- PRICE QUEUE SYSTEM --------------------

const DB_FILE = "prices.json";

let priceDatabase = {};
const priceQueue = new Set();
let isProcessing = false;

// Load DB on start
if (fs.existsSync(DB_FILE)) {
    try {
        priceDatabase = JSON.parse(fs.readFileSync(DB_FILE, "utf8"));
        console.log("Loaded price database. Items:", Object.keys(priceDatabase).length);
    } catch (e) {
        console.error("Failed to load prices.json", e);
    }
}

function savePriceDatabase() {
    try {
        fs.writeFileSync(DB_FILE, JSON.stringify(priceDatabase, null, 2));
    } catch (e) {
        console.error("Failed to save prices.json", e);
    }
}

// Tekli fiyat çekme (Steam PriceOverview)
async function fetchPriceForMarketName(marketName) {
    const encoded = encodeURIComponent(marketName);
    const url = `https://steamcommunity.com/market/priceoverview/?currency=1&appid=730&market_hash_name=${encoded}`;

    try {
        const response = await axios.get(url, {
            timeout: 10000,
            headers: {
                "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
            }
        });
        const data = response.data;

        if (data && data.success) {
            const priceStr = data.lowest_price || data.median_price;
            return parseNumeric(priceStr);
        }
    } catch (err) {
        console.log("Steam Price Error:", marketName, err.message);
    }
    return null;
}

async function processQueue() {
    if (isProcessing) return;
    isProcessing = true;

    console.log("Starting queue processing...");

    while (priceQueue.size > 0) {
        const marketName = priceQueue.values().next().value;
        priceQueue.delete(marketName);

        // Cache check removed: If it's in the queue, we fetch it.
        // The decision to queue is made upstream (in the endpoint).

        console.log("Queue fetching:", marketName);
        const price = await fetchPriceForMarketName(marketName);

        if (price !== null) {
            // Save previous price if it exists
            const oldEntry = priceDatabase[marketName];
            const previousPrice = oldEntry ? oldEntry.price : null;

            priceDatabase[marketName] = {
                price,
                time: Date.now(),
                previous_price: previousPrice
            };
            savePriceDatabase(); // Her başarılı işlemde kaydet
            addItemHistory(marketName, price); // 🔥 Record history
        } else {
            console.log("Failed to fetch:", marketName);
        }

        // Rate limit yememek için bekle
        await delay(3500);
    }

    isProcessing = false;
    console.log("Queue processing finished.");

    // 🔥 Update History for all cached users
    console.log("Updating total value history for cached users...");
    for (const steamId of Object.keys(inventoryCache)) {
        try {
            const items = await fetchInventory(steamId);
            let totalValue = 0;
            for (const item of items) {
                const priceEntry = priceDatabase[item.name];
                if (priceEntry) {
                    totalValue += priceEntry.price;
                }
            }
            if (totalValue > 0) {
                console.log(`Recording history for ${steamId}: $${totalValue}`);
                addTotalValueHistory(totalValue, true); // Force update
            }
        } catch (e) {
            console.error(`Failed to update history for ${steamId}`, e);
        }
    }
}

// -------------------- PORTFOLIO SYSTEM --------------------

const PORTFOLIO_FILE = "portfolio.json";
let portfolioDatabase = {};

// Load Portfolio
if (fs.existsSync(PORTFOLIO_FILE)) {
    try {
        portfolioDatabase = JSON.parse(fs.readFileSync(PORTFOLIO_FILE, "utf8"));
        console.log("Loaded portfolio database. Items:", Object.keys(portfolioDatabase).length);
    } catch (e) {
        console.error("Failed to load portfolio.json", e);
    }
}

function savePortfolioDatabase() {
    try {
        fs.writeFileSync(PORTFOLIO_FILE, JSON.stringify(portfolioDatabase, null, 2));
    } catch (e) {
        console.error("Failed to save portfolio.json", e);
    }
}

app.post("/portfolio/set-price", express.json(), (req, res) => {
    const { assetId, price } = req.body;
    if (!assetId) {
        return res.status(400).json({ success: false, error: "Missing assetId" });
    }

    if (price === null) {
        delete portfolioDatabase[assetId];
        console.log(`Removed purchase price for ${assetId}`);
    } else {
        portfolioDatabase[assetId] = { purchase_price: parseFloat(price), time: Date.now() };
        console.log(`Set purchase price for ${assetId}: ${price}`);
    }

    savePortfolioDatabase();
    res.json({ success: true });
});

app.post("/portfolio/toggle-watch", express.json(), (req, res) => {
    const { assetId, isWatched } = req.body;
    if (!assetId) {
        return res.status(400).json({ success: false, error: "Missing assetId" });
    }

    if (!portfolioDatabase[assetId]) {
        portfolioDatabase[assetId] = { time: Date.now() };
    }

    portfolioDatabase[assetId].watch = isWatched;
    console.log(`Set watch status for ${assetId}: ${isWatched}`);

    savePortfolioDatabase();
    res.json({ success: true });
});

// -------------------- HISTORY SYSTEM --------------------

const HISTORY_FILE = "history.json";
let historyDatabase = { total_value: [], items: {} };

// Load History
if (fs.existsSync(HISTORY_FILE)) {
    try {
        historyDatabase = JSON.parse(fs.readFileSync(HISTORY_FILE, "utf8"));
        if (!historyDatabase.total_value) historyDatabase.total_value = [];
        if (!historyDatabase.items) historyDatabase.items = {};
        console.log("Loaded history database.");
    } catch (e) {
        console.error("Failed to load history.json", e);
    }
}

function saveHistoryDatabase() {
    try {
        fs.writeFileSync(HISTORY_FILE, JSON.stringify(historyDatabase, null, 2));
    } catch (e) {
        console.error("Failed to save history.json", e);
    }
}

// Helper to add item history
function addItemHistory(marketName, price) {
    if (!historyDatabase.items[marketName]) {
        historyDatabase.items[marketName] = [];
    }
    historyDatabase.items[marketName].push({ time: Date.now(), price: price });
    saveHistoryDatabase();
}

// Helper to add total value history
function addTotalValueHistory(value, force = false) {
    // Limit to 1 entry per hour to avoid spam, unless forced
    const lastEntry = historyDatabase.total_value[historyDatabase.total_value.length - 1];
    const now = Date.now();
    if (!force && lastEntry && (now - lastEntry.time < 1000 * 60 * 5)) {
        return; // Skip if less than 5 mins passed and not forced
    }
    historyDatabase.total_value.push({ time: now, value: value });
    saveHistoryDatabase();
}

app.get("/history/total", (req, res) => {
    res.json(historyDatabase.total_value);
});

app.get("/history/item/:name", (req, res) => {
    const name = req.params.name;
    const history = historyDatabase.items[name] || [];
    res.json(history);
});

app.get("/inventory/:steamid/priced", async (req, res) => {
    const steamId = req.params.steamid;

    // Check for manual update flag
    const forceUpdate = req.query.update_prices === 'true';

    // Get last refresh time from portfolio DB
    let lastPriceRefresh = portfolioDatabase['_meta']?.last_price_refresh || 0;
    const now = Date.now();
    const COOLDOWN = 1000 * 60 * 60 * 4; // 4 hours

    let canUpdate = false;
    if (forceUpdate) {
        if (now - lastPriceRefresh > COOLDOWN) {
            canUpdate = true;
            // Update timestamp
            if (!portfolioDatabase['_meta']) portfolioDatabase['_meta'] = {};
            portfolioDatabase['_meta'].last_price_refresh = now;
            lastPriceRefresh = now;
            savePortfolioDatabase(); // Save meta to file
            console.log("Manual price update triggered.");
        } else {
            console.log("Manual update ignored: Cooldown active.");
        }
    }

    try {
        // 1. Get Inventory (Cached)
        const items = await fetchInventory(steamId);

        let totalValue = 0;
        let totalPurchaseValue = 0;
        let totalValueForProfitCalc = 0;
        let queuedCount = 0;
        // 2. Match with Prices
        const pricedItems = items.map(i => {
            const dbEntry = priceDatabase[i.name];
            let price = null;
            let previousPrice = null;
            let lastUpdated = null;

            if (dbEntry) {
                price = dbEntry.price;
                previousPrice = dbEntry.previous_price || null;
                lastUpdated = dbEntry.time; // Timestamp
                totalValue += price;
            }

            // Queue logic: Only queue if canUpdate is true AND item is marketable AND not already in queue
            if (canUpdate && i.marketable === 1 && !priceQueue.has(i.name)) {
                priceQueue.add(i.name);
                queuedCount++;
            }

            // Portfolio verisini ekle
            const portfolioData = portfolioDatabase[i.assetid];
            const purchasePrice = portfolioData ? portfolioData.purchase_price : null;
            const isWatched = portfolioData ? (portfolioData.watch === true) : false;

            if (purchasePrice) {
                totalPurchaseValue += purchasePrice;
                if (price) {
                    totalValueForProfitCalc += price;
                }
            }

            return {
                ...i,
                price: price,
                previous_price: previousPrice,
                purchase_price: purchasePrice,
                is_watched: isWatched,
                last_updated: lastUpdated
            };
        });

        if (queuedCount > 0) {
            console.log(`Added ${queuedCount} items to price queue.`);
            processQueue();
        }

        // 🔥 Record Total Value History (if not 0)
        // REMOVED: Only record when prices are updated via queue
        // if (totalValue > 0) {
        //     addTotalValueHistory(totalValue);
        // }

        res.json({
            success: true,
            items: pricedItems,
            total_value: totalValue,
            total_purchase_value: totalPurchaseValue,
            total_value_for_profit_calc: totalValueForProfitCalc,
            queued_count: queuedCount,
            last_price_refresh: lastPriceRefresh
        });

    } catch (error) {
        console.error(error);
        res.status(500).json({ error: "Failed to fetch inventory" });
    }
});

// -------------------- SERVER --------------------

app.listen(3000, "0.0.0.0", () => console.log("Backend running on port 3000"));
