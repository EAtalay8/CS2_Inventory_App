const express = require("express");
const axios = require("axios");
const cors = require("cors");

const app = express();
app.use(cors());

app.get("/inventory/:steamId", async (req, res) => {
  const steamId = req.params.steamId;

  try {
    const url = `https://steamcommunity.com/inventory/${steamId}/730/2?l=english&count=5000`;

    const response = await axios.get(url);

    res.json({
      success: true,
      descriptions: response.data.descriptions || [],
      assets: response.data.assets || []
    });

  } catch (err) {
    console.log(err);
    res.json({ success: false, error: "Failed to fetch inventory" });
  }
});

app.listen(3000, () => {
  console.log("Backend running on http://localhost:3000");
});
