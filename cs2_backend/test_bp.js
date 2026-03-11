const axios = require("axios");

async function testBP() {
    try {
        console.log("Fetching from csgobackpack.net via axios...");
        const response = await axios.get("https://csgobackpack.net/api/GetItemsList/v2/?no_details=true", {
            headers: {
                "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
                "Accept": "application/json"
            }
        });
        console.log("Success! Status:", response.status);
        console.log("Data keys:", Object.keys(response.data).length);
        console.log("Items count in items_list:", Object.keys(response.data.items_list || {}).length);
    } catch (err) {
        console.error("Error:", err.message);
    }
}

testBP();
