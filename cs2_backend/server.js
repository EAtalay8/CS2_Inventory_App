const express = require("express");
const axios = require("axios");
const cors = require("cors");

const app = express();
app.use(cors());


function fixIcon(icon) {
    if (!icon) return null;

    // Tam URL ise dokunma
    if (icon.startsWith("https://") || icon.startsWith("http://"))
        return icon;
    // Değilse prefix ekle

    return "https://steamcommunity-a.akamaihd.net/economy/image/" + icon;
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


app.listen(3000, '0.0.0.0', () => console.log("Backend running on port 3000"));
