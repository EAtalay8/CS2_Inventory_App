const fetch = require("node-fetch");

async function fetchInventoryPage(steamId, startAssetId = null) {
  const baseUrl = `https://steamcommunity.com/inventory/${steamId}/730/2?l=english&count=200`;

  const url = startAssetId
    ? `${baseUrl}&start_assetid=${startAssetId}`
    : baseUrl;

  const res = await fetch(url, {
    headers: {
      "User-Agent":
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120 Safari/537.36",
    },
  });

  return res.json();
}

async function fetchFullInventory(steamId) {
  let allAssets = [];
  let lastAssetId = null;
  let page = 1;

  while (true) {
    console.log(`Fetching page ${page}...`);

    const data = await fetchInventoryPage(steamId, lastAssetId);

    if (!data || data.success !== 1) {
      throw new Error("Failed to fetch inventory page.");
    }

    // asset yoksa direk kır
    if (!data.assets || data.assets.length === 0) {
      break;
    }

    allAssets = allAssets.concat(data.assets);

    // Eğer devam yoksa kır
    if (data.more_items !== 1 || !data.last_assetid) {
      break;
    }

    // Sonsuz döngüyü engellemek için güvenlik
    if (lastAssetId === data.last_assetid) {
      console.log("Stopping: Steam returned same last_assetid twice.");
      break;
    }

    lastAssetId = data.last_assetid;
    page++;

    // Güvenlik: En fazla 10 sayfa
    if (page > 10) {
      console.log("Stopped: page limit exceeded.");
      break;
    }
  }

  return allAssets;
}

module.exports = { fetchFullInventory };
