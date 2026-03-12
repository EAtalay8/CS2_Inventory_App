import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:brotli/brotli.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/inventory_item.dart';
import 'local_storage_service.dart';
import 'background_service.dart';

class InventoryResult {
  final List<InventoryItem> items;
  final double totalValue;
  final double totalPurchaseValue;
  final double totalValueForProfitCalc;
  final DateTime? lastPriceRefresh;
  final String? error;

  InventoryResult({
    required this.items,
    required this.totalValue,
    required this.totalPurchaseValue,
    required this.totalValueForProfitCalc,
    this.lastPriceRefresh,
    this.error,
  });
}

class InventoryService {
  final LocalStorageService _storage = LocalStorageService();

  // Shared browser-like headers for all Steam requests
  static const Map<String, String> _baseHeaders = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
    "Accept": "application/json, text/plain, */*",
    "Accept-Language": "en-US,en;q=0.9",
    "Connection": "keep-alive",
  };

  /// Returns headers with steamLoginSecure cookie if available.
  /// Authenticated requests have much higher rate limits on Steam.
  static Future<Map<String, String>> _getSteamHeaders() async {
    final headers = Map<String, String>.from(_baseHeaders);
    try {
      final prefs = await SharedPreferences.getInstance();
      final cookie = prefs.getString('steamLoginSecure');
      if (cookie != null && cookie.isNotEmpty) {
        headers['Cookie'] = 'steamLoginSecure=$cookie';
      }
    } catch (e) {
      print('Warning: Could not load Steam cookie: $e');
    }
    return headers;
  }
  
  // Progress Stream for UI (e.g. "5/285")
  static final StreamController<String> _progressController = StreamController<String>.broadcast();
  Stream<String> get progressStream => _progressController.stream;

  static bool _isUpdating = false;

  // Cache for loaded data (Static to persist across instances)
  static Map<String, dynamic> _prices = {};
  static Map<String, dynamic> _portfolio = {};
  static Map<String, dynamic> _history = {};
  
  static final bool _dataLoaded = false;

  Future<void> _loadLocalData() async {
    _prices = await _storage.loadData('prices.json');
    _portfolio = await _storage.loadData('portfolio.json');
    _history = await _storage.loadData('history.json');
    
    // Initialize history structure if empty
    if (!_history.containsKey('total_value')) _history['total_value'] = [];
    if (!_history.containsKey('items')) _history['items'] = {};
  }

  // Cache for raw inventory items (mimicking server.js inventoryCache)
  static final Map<String, dynamic> _inventoryCache = {};
  static const int _inventoryCacheTTL = 1000 * 60 * 30; // 30 minutes

  Future<InventoryResult> fetchInventory(String steamId, {bool forceUpdate = false}) async {
    await _loadLocalData();

    try {
      // 1. Fetch Raw Inventory (Cached & Retried like backend)
      List<InventoryItem> rawItems = await _fetchRawInventoryFromSteam(steamId, forceUpdate: forceUpdate);

      // 2. Merge with Prices & Portfolio (Mimicking /inventory/:steamid/priced)
      List<InventoryItem> pricedItems = [];
      double totalValue = 0;
      double totalPurchaseValue = 0;
      double totalValueForProfitCalc = 0;

      for (var item in rawItems) {
         // Merge with Local Data
         final priceEntry = _prices[item.name];
         double? steamPrice;
         double? bpPrice;
         double? steamPreviousPrice;
         double? bpPreviousPrice;
         DateTime? lastUpdated;

         if (priceEntry != null) {
           steamPrice = (priceEntry["steam_price"] as num?)?.toDouble();
           bpPrice = (priceEntry["bp_price"] as num?)?.toDouble();
           steamPreviousPrice = (priceEntry["steam_previous_price"] as num?)?.toDouble();
           bpPreviousPrice = (priceEntry["bp_previous_price"] as num?)?.toDouble();

           // Legacy fallback for old cache formats
           if (steamPrice == null && priceEntry["price"] != null) {
             steamPrice = (priceEntry["price"] as num?)?.toDouble();
             steamPreviousPrice = (priceEntry["previous_price"] as num?)?.toDouble();
           }

           if (priceEntry["time"] != null) {
             lastUpdated = DateTime.fromMillisecondsSinceEpoch(priceEntry["time"]);
           }
         }

         final portfolioEntry = _portfolio[item.assetid];
         double? purchasePrice;
         bool isWatched = false;

         if (portfolioEntry != null) {
           purchasePrice = (portfolioEntry["purchase_price"] as num?)?.toDouble();
           isWatched = portfolioEntry["watch"] == true;
         }
         
         // Create new item with merged data
         final newItem = InventoryItem(
           assetid: item.assetid,
           classid: item.classid,
           name: item.name,
           icon: item.icon,
           type: item.type,
           marketable: item.marketable,
           steamPrice: steamPrice,
           steamPreviousPrice: steamPreviousPrice,
           bpPrice: bpPrice,
           bpPreviousPrice: bpPreviousPrice,
           purchasePrice: purchasePrice,
           isWatched: isWatched,
           lastUpdated: lastUpdated,
         );

         pricedItems.add(newItem);

         // Calculate Totals
         if (newItem.price != null) {
           totalValue += newItem.price!;
         }
         if (newItem.purchasePrice != null) {
           totalPurchaseValue += newItem.purchasePrice!;
           if (newItem.price != null) {
             totalValueForProfitCalc += newItem.price!;
           }
         }
      }

      // Get Last Refresh Time from Meta
      DateTime? lastPriceRefresh;
      if (_portfolio["_meta"] != null && _portfolio["_meta"]["last_price_refresh"] != null) {
        lastPriceRefresh = DateTime.fromMillisecondsSinceEpoch(_portfolio["_meta"]["last_price_refresh"]);
      }

      // Handle Price Updates (Force Update)
      if (forceUpdate) {
        final service = FlutterBackgroundService();
        if (!await service.isRunning()) {
          await service.startService();
          await Future.delayed(const Duration(milliseconds: 500));
        }
        service.invoke("startSteamUpdate");
      }

      return InventoryResult(
        items: pricedItems,
        totalValue: totalValue,
        totalPurchaseValue: totalPurchaseValue,
        totalValueForProfitCalc: totalValueForProfitCalc,
        lastPriceRefresh: lastPriceRefresh,
      );

    } catch (e) {
      // On error, return items with CACHED prices instead of empty list
      // This prevents the inventory from showing $0 when Steam is down or rate-limited
      List<InventoryItem> cachedItems = [];
      double cachedTotalValue = 0;
      double cachedTotalPurchaseValue = 0;
      double cachedTotalValueForProfitCalc = 0;

      // First check memory cache
      var cached = _inventoryCache[steamId];
      List<InventoryItem>? rawItems;

      if (cached != null) {
        rawItems = cached['items'] as List<InventoryItem>;
      } else {
        // Fallback to disk cache if memory is empty (e.g. on app restart)
        final diskCache = await _storage.loadData('inventory.json');
        if (diskCache != null && diskCache['items'] != null) {
          rawItems = (diskCache['items'] as List).map((e) => InventoryItem.fromJson(e)).toList();
        }
      }

      if (rawItems != null) {
        for (var item in rawItems) {
          final priceEntry = _prices[item.name];
          double? steamPrice = (priceEntry?["steam_price"] as num?)?.toDouble();
          double? steamPrevPrice = (priceEntry?["steam_previous_price"] as num?)?.toDouble();
          double? bpPrice = (priceEntry?["bp_price"] as num?)?.toDouble();
          double? bpPrevPrice = (priceEntry?["bp_previous_price"] as num?)?.toDouble();

          // Legacy support
          if (steamPrice == null && priceEntry?["price"] != null) {
            steamPrice = (priceEntry?["price"] as num?)?.toDouble();
            steamPrevPrice = (priceEntry?["previous_price"] as num?)?.toDouble();
          }

          double? price = steamPrice ?? bpPrice;
          // previousPrice is not directly used in the constructor, but the getter will derive it.

          final portfolioEntry = _portfolio[item.assetid];
          double? purchasePrice = portfolioEntry != null ? (portfolioEntry["purchase_price"] as num?)?.toDouble() : null;

          final newItem = InventoryItem(
            assetid: item.assetid,
            classid: item.classid,
            name: item.name,
            icon: item.icon, type: item.type, marketable: item.marketable,
            steamPrice: steamPrice, steamPreviousPrice: steamPrevPrice,
            bpPrice: bpPrice, bpPreviousPrice: bpPrevPrice,
            purchasePrice: purchasePrice,
            isWatched: portfolioEntry?["watch"] == true,
          );
          cachedItems.add(newItem);
          if (price != null) cachedTotalValue += price;
          if (purchasePrice != null) {
            cachedTotalPurchaseValue += purchasePrice;
            if (price != null) cachedTotalValueForProfitCalc += price;
          }
        }
      }

      if (cachedItems.isNotEmpty) {
        return InventoryResult(
          items: cachedItems,
          totalValue: cachedTotalValue,
          totalPurchaseValue: cachedTotalPurchaseValue,
          totalValueForProfitCalc: cachedTotalValueForProfitCalc,
          error: "Warning: Using cached data. $e",
        );
      }

      return InventoryResult(
          items: [], totalValue: 0, totalPurchaseValue: 0, totalValueForProfitCalc: 0,
          error: "Error: $e"
      );
    }
  }

  // Mimics fetchInventory from server.js
  Future<List<InventoryItem>> _fetchRawInventoryFromSteam(String steamId, {bool forceUpdate = false}) async {
    // 1. Memory Cache Check
    final cached = _inventoryCache[steamId];
    if (!forceUpdate && cached != null) {
      final int time = cached['time'];
      if (DateTime.now().millisecondsSinceEpoch - time < _inventoryCacheTTL) {
        print("Serving inventory from memory cache: $steamId");
        return cached['items'] as List<InventoryItem>;
      }
    }

    // 2. Disk Cache Check (New: Prevents network hit on startup if cache exists)
    if (!forceUpdate) {
      final diskCache = await _storage.loadData('inventory.json');
      if (diskCache != null && diskCache['items'] != null && diskCache['time'] != null) {
        final int time = diskCache['time'];
        if (DateTime.now().millisecondsSinceEpoch - time < _inventoryCacheTTL) {
           print("Serving inventory from disk cache: $steamId");
           final items = (diskCache['items'] as List).map((e) => InventoryItem.fromJson(e)).toList();
           
           // Refill memory cache for next call
           _inventoryCache[steamId] = {
             'items': items,
             'time': time
           };
           return items;
        }
      }
    }

    List<dynamic> assets = [];
    Map<String, dynamic> descriptions = {};
    Set<String> visitedPages = {};
    String? startAssetId;
    
    // Pagination Loop
    while (true) {
      print("Fetching inventory page: ${startAssetId ?? 'first'}");
      
      // Retry Loop (3 attempts)
      http.Response? res;
      int attempts = 0;
      bool success = false;
      
      while (attempts < 3) {
        try {
          String urlString = "https://steamcommunity.com/inventory/$steamId/730/2?l=english&count=500";
          if (startAssetId != null) {
            urlString += "&start_assetid=$startAssetId";
          }
          
          print("Requesting: $urlString");
          final headers = await _getSteamHeaders();
          headers["Referer"] = "https://steamcommunity.com/profiles/$steamId/inventory";
          res = await http.get(
            Uri.parse(urlString),
            headers: headers,
          );
          
          print("Status Code: ${res.statusCode}");
          print("Response Body (Start): ${res.body.substring(0, res.body.length > 200 ? 200 : res.body.length)}");

          if (res.statusCode == 200) {
            success = true;
            break;
          } else if (res.statusCode == 429) {
             throw Exception("Steam is temporarily blocking requests (Rate Limit). Please wait ~15 minutes and try again.");
          } else if (res.statusCode == 403) {
             throw Exception("Access Denied (403). Is your Steam inventory private?");
          } else if (res.statusCode >= 500) {
             throw Exception("Steam servers are having issues (${res.statusCode}). Try again later.");
          } else {
             throw Exception("Unexpected Steam error (${res.statusCode}).");
          }
        } catch (e) {
          attempts++;
          print("Fetch attempt $attempts failed: $e");
          if (attempts >= 3) rethrow;
          await Future.delayed(const Duration(seconds: 2));
        }
      }

      if (!success || res == null) throw Exception("Failed to fetch inventory after 3 attempts");

      final body = json.decode(res.body);
      
      if (body == null || (body['assets'] == null && body['success'] != true)) {
         // If it's a private inventory or error
         if (body != null && body['success'] == false) throw Exception("Steam API Success: False");
         throw Exception("Inventory not found or empty");
      }

      if (body['assets'] != null) {
        assets.addAll(body['assets']);
      }
      
      if (body['descriptions'] != null) {
        for (var d in body['descriptions']) {
          descriptions[d['classid']] = d;
        }
      }

      if (body['more_items'] != 1) break;
      if (body['last_assetid'] == null) break;
      if (visitedPages.contains(body['last_assetid'])) break;

      visitedPages.add(body['last_assetid']);
      startAssetId = body['last_assetid'];
      
      await Future.delayed(const Duration(milliseconds: 1000)); // Rate limit safety
    }

    // Map to InventoryItems
    List<InventoryItem> items = [];
    for (var asset in assets) {
       final desc = descriptions[asset["classid"]] ?? {};
       final name = desc["market_hash_name"] ?? desc["market_name"] ?? "Unknown";
       final icon = desc["icon_url"] != null 
           ? "https://steamcommunity-a.akamaihd.net/economy/image/${desc["icon_url"]}" 
           : "";
       final type = desc["type"] ?? "";
       final marketable = desc["marketable"] ?? 0;

       items.add(InventoryItem(
         assetid: asset["assetid"],
         classid: asset["classid"],
         name: name,
         icon: icon,
         type: type,
         marketable: marketable,
         steamPrice: null,
         steamPreviousPrice: null,
         bpPrice: null,
         bpPreviousPrice: null,
         purchasePrice: null,
         isWatched: false,
       ));
    }

    // Update Cache
    _inventoryCache[steamId] = {
      'items': items,
      'time': DateTime.now().millisecondsSinceEpoch
    };

    // Save to Disk for Background Services
    await _storage.saveData('inventory.json', {
      'items': items.map((e) => e.toJson()).toList(),
      'time': DateTime.now().millisecondsSinceEpoch
    });

    return items;
  }

  /// Update trigger from UI (Steam)
  Future<void> updateAllPrices() async {
    if (_isUpdating) {
      print("⚠️ Update already in progress.");
      return; 
    }

    final service = FlutterBackgroundService();
    final cached = await _storage.loadData('inventory.json');
    if (cached['items'] == null) {
      print("❌ Cannot update: Inventory cache empty.");
      return;
    }
    
    _isUpdating = true;
    try {
      if (!await service.isRunning()) {
        await service.startService();
      }
      final rawItems = cached['items'] as List<dynamic>;
      final List<InventoryItem> items = rawItems.map((e) => InventoryItem.fromJson(e)).toList();
      await _updatePricesInBackground(items, service);
    } finally {
      _isUpdating = false;
    }
  }

  /// Update trigger from UI (CSGO Backpack)
  Future<void> updateAllPricesFromBP() async {
    if (_isUpdating) {
      print("⚠️ Update already in progress.");
      return; 
    }

    final service = FlutterBackgroundService();
    _isUpdating = true;
    try {
      if (!await service.isRunning()) {
        await service.startService();
      }
      await _updatePricesFromBPInBackground(service);
    } finally {
      _isUpdating = false;
    }
  }

  // 🔥 Background Price Update Logic (Steam)
  Future<void> _updatePricesInBackground(List<InventoryItem> items, FlutterBackgroundService service) async {
    // Normalize names and filter marketable items
    // We store the ORIGINAL name for storage keys, but use NORMALIZED for matching
    final Map<String, String> normalizedToOriginal = {};
    for (var item in items.where((i) => i.marketable == 1)) {
       normalizedToOriginal[item.name.trim().toLowerCase()] = item.name;
    }
    
    final uniqueNormalizedNames = normalizedToOriginal.keys.toSet();
    int total = uniqueNormalizedNames.length;

    print("🔍 Diagnostic: Total unique items to update: $total");
    if (normalizedToOriginal.isNotEmpty) {
      print("🔍 Diagnostic: Sample items from inventory (normalized): ${uniqueNormalizedNames.take(5).toList()}");
    }

    // Update Meta Timestamp (Restore)
    if (_portfolio["_meta"] == null) _portfolio["_meta"] = {};
    _portfolio["_meta"]["last_price_refresh"] = DateTime.now().millisecondsSinceEpoch;
    await _storage.saveData('portfolio.json', _portfolio);

    service.invoke("updateNotification", {"content": "Starting price update..."});
    
    // --- 📦 PHASE 1: SMART BATCH UPDATE (Search/Render) ---
    Set<String> allBatchUpdated = {};
    
    // Extract unique subcategories (keywords) from user's inventory
    Set<String> searchKeywords = {};
    for (var item in items.where((i) => i.marketable == 1)) {
       // "AK-47", "M4A4", "Stickers", "Containers" etc.
       // But wait: searching "Containers" literally might not match Case names since the word might be missing.
       // Let's refine the keyword: if category is not Weapons, just search the exact base name (with a limit) or a generic term.
       // Actually, searching "Case", "Sticker", "Graffiti" works wonderfully with Steam's search engine.
       String keyword = item.subCategory;
       if (keyword == "Containers") keyword = "Case";
       if (keyword == "Stickers") keyword = "Sticker";
       if (keyword == "Graffitis") keyword = "Graffiti";
       if (keyword == "Music Kits") keyword = "Music Kit";
       if (keyword == "Agents") keyword = "Agent";
       if (keyword == "Pins") keyword = "Pin";
       if (keyword == "Patches") keyword = "Patch";
       searchKeywords.add(keyword);
    }
    
    // If we have "Others", remove it to avoid junk searches
    searchKeywords.remove("Others");
    
    print("🚀 Starting Smart Batch Update Phase for ${searchKeywords.length} categories: $searchKeywords");
    
    int batchIndex = 0;
    for (var keyword in searchKeywords) {
      batchIndex++;
      _progressController.add("Batching $keyword... ($batchIndex/${searchKeywords.length})");
      
      // Fetch top 100 for this specific subcategory
      final batch = await _fetchPricesInBatch(keyword, 0, 100);
      allBatchUpdated.addAll(batch);
      
      // Small cooling-off between batch requests
      if (batchIndex < searchKeywords.length) {
        await Future.delayed(const Duration(seconds: 4));
      }
    }

    // Phase transition cool-off (Let Steam breathe)
    if (allBatchUpdated.isNotEmpty) {
      _progressController.add("Found ${allBatchUpdated.length} items. Syncing remaining...");
      await Future.delayed(const Duration(seconds: 8));
    } else {
      _progressController.add("No items found in batch. Syncing all one-by-one...");
      await Future.delayed(const Duration(seconds: 5));
    }

    // --- 🔍 PHASE 2: INDIVIDUAL UPDATE (Fallback) ---
    final remainingNormalized = uniqueNormalizedNames.where((norm) => !allBatchUpdated.contains(norm)).toList();
    int remainingTotal = remainingNormalized.length;
    int current = 0;
    
    print("🔍 Batch Phase Result: Found ${uniqueNormalizedNames.length - remainingTotal} items. $remainingTotal remaining.");

    if (remainingTotal > 0) {
      int consecutiveErrors = 0;
      int delayMs = 4000; 

      for (var normName in remainingNormalized) {
        final originalName = normalizedToOriginal[normName] ?? normName;
        current++;
        String progressMsg = "$current/$remainingTotal";
        
        _progressController.add("Syncing rare skins: $progressMsg");
        service.invoke("updateNotification", {"content": "Updating rare skins: $progressMsg"});

        bool success = await _fetchAndSavePrice(originalName, saveToDisk: false);
        
        // Save to disk every 10 items to reduce massive I/O
        if (success && (current % 10 == 0 || current == remainingTotal)) {
          await _storage.saveData('prices.json', _prices);
          await _storage.saveData('history.json', _history);
        }
        
        if (success) {
          consecutiveErrors = 0;
          delayMs = 4000; 
        } else {
          consecutiveErrors++;
          if (consecutiveErrors >= 2) { 
            delayMs = 25000; // 25s
            print("⚠️ Frequent errors, slowing down to ${delayMs}ms");
            _progressController.add("Steam is busy. Cooling down for 25s... ($current/$remainingTotal)");
            service.invoke("updateNotification", {"content": "Rate limited, waiting... $progressMsg"});
          } else {
            delayMs = 8000; 
          }
        }

        await Future.delayed(Duration(milliseconds: delayMs));
      }
    }
    
    // After all updates, save total value history
    await _recordTotalValueHistory(items);
    
    service.invoke("updateNotification", {"content": "Update Complete!"});
    await Future.delayed(const Duration(seconds: 5));
    service.invoke("stopService");
    _progressController.add(""); // Clear UI
  }

  /// Fetches 100 items from Steam Search and updates prices in batch.
  /// Returns a set of names that were successfully updated.
  Future<Set<String>> _fetchPricesInBatch(String query, int start, int count) async {
    final url = Uri.parse("https://steamcommunity.com/market/search/render/?query=${Uri.encodeComponent(query)}&start=$start&count=$count&search_descriptions=0&sort_column=popular&sort_dir=desc&appid=730&norender=1&currency=1");
    final Set<String> updatedNames = {};

    int retryAttempt = 0;
    while (retryAttempt < 2) {
      try {
        final batchHeaders = await _getSteamHeaders();
        batchHeaders["Referer"] = "https://steamcommunity.com/market/search?appid=730";
        final res = await http.get(url, headers: batchHeaders);

        if (res.statusCode == 200) {
          // FORCE UTF-8 Decoding for special characters (™, ★, etc.)
          final bodyString = utf8.decode(res.bodyBytes);
          final body = json.decode(bodyString);
          
          if (body["success"] == true && body["results"] != null) {
            final List results = body["results"] as List;
            final Map<String, dynamic> historyItems = (_history["items"] as Map<String, dynamic>?) ?? {};

            for (var result in results) {
              if (result is! Map) continue;
              
              // Steam names can be in 'hash_name' or 'name'
              String rawHashName = (result["hash_name"] ?? result["name"])?.toString() ?? "";
              String normName = rawHashName.trim().toLowerCase();
              String? priceStr = result["sell_price_text"];
              
              if (retryAttempt == 0 && updatedNames.isEmpty && rawHashName.isNotEmpty) {
                 print("🔍 Diagnostic: First item in Batch (normalized): '$normName' Price: '$priceStr'");
              }

              if (rawHashName.isNotEmpty && priceStr != null) {
                double? price = _parsePrice(priceStr);
                if (price != null) {
                  // We update the original raw name in our storage to match fallback keys
                  final oldEntry = _prices[rawHashName] ?? {};
                  double? previousSteamPrice = oldEntry["steam_price"] != null 
                      ? (oldEntry["steam_price"] as num?)?.toDouble() 
                      : (oldEntry["price"] as num?)?.toDouble(); // legacy fallback
                  
                  _prices[rawHashName] = {
                    ...oldEntry, // Preserve BP and other keys
                    "steam_price": price,
                    "steam_previous_price": previousSteamPrice,
                    "time": DateTime.now().millisecondsSinceEpoch
                  };
                  
                  if (historyItems[rawHashName] == null) historyItems[rawHashName] = [];
                  (historyItems[rawHashName] as List).add({
                    "time": DateTime.now().millisecondsSinceEpoch,
                    "steam_price": price
                  });
                  
                  // Mark as updated using BOTH original and normalized for safety
                  updatedNames.add(normName); 
                  updatedNames.add(rawHashName); 
                }
              }
            }
            _history["items"] = historyItems;
            if (updatedNames.isNotEmpty) {
              await _storage.saveData('prices.json', _prices);
              await _storage.saveData('history.json', _history);
              print("📦 Batch update: Updated ${updatedNames.length} items (start=$start).");
            }
            return updatedNames;
          }
        } else if (res.statusCode == 429) {
          retryAttempt++;
          print("🚫 Batch Rate Limit (429) at start=$start. Waiting 30s...");
          _progressController.add("Steam limit reached. Cooling down (30s)...");
          await Future.delayed(const Duration(seconds: 30));
          if (retryAttempt >= 2) break;
        } else if (res.statusCode == 503 || res.statusCode == 500) {
          print("❌ Steam Server Error (${res.statusCode}) at start=$start");
          _progressController.add("Steam Market is down (${res.statusCode})");
          break;
        } else {
          print("❌ Batch update failed (HTTP ${res.statusCode})");
          break;
        }
      } catch (e) {
        print("❌ Error in batch update: $e");
        break;
      }
    }

    return updatedNames;
  }

  /// Fetches and saves price for a single item. Returns true on success.
  Future<bool> _fetchAndSavePrice(String marketHashName, {bool saveToDisk = true}) async {
    final url = Uri.parse("https://steamcommunity.com/market/priceoverview/?currency=1&appid=730&market_hash_name=${Uri.encodeComponent(marketHashName)}");
    
    // Retry with exponential backoff (up to 3 attempts)
    int retryAttempt = 0;
    const maxRetries = 3;

    while (retryAttempt < maxRetries) {
      try {
        final singleHeaders = await _getSteamHeaders();
        singleHeaders["Referer"] = "https://steamcommunity.com/market/";
        final res = await http.get(url, headers: singleHeaders);

        if (res.statusCode == 200) {
          final body = json.decode(res.body);
          if (body["success"] == true) {
            String? priceStr = body["lowest_price"] ?? body["median_price"];
            double? price = _parsePrice(priceStr);

            if (price != null) {
              // Update Prices
              final oldPriceEntry = _prices[marketHashName] ?? {};
              double? previousSteamPrice = oldPriceEntry["steam_price"] != null
                  ? (oldPriceEntry["steam_price"] as num?)?.toDouble()
                  : (oldPriceEntry["price"] as num?)?.toDouble(); // legacy fallback

              _prices[marketHashName] = {
                ...oldPriceEntry, // Preserve BP and other keys
                "steam_price": price,
                "steam_previous_price": previousSteamPrice,
                "time": DateTime.now().millisecondsSinceEpoch
              };
              
              if (saveToDisk) await _storage.saveData('prices.json', _prices);

              // Update Item History
              final Map<String, dynamic> historyItems = (_history["items"] as Map<String, dynamic>?) ?? {};
              if (historyItems[marketHashName] == null) {
                historyItems[marketHashName] = [];
              }
              (historyItems[marketHashName] as List).add({
                "time": DateTime.now().millisecondsSinceEpoch,
                "steam_price": price
              });
              _history["items"] = historyItems; // Ensure _history["items"] is updated
              
              if (saveToDisk) await _storage.saveData('history.json', _history);
              
              print("✅ Updated price for $marketHashName: \$$price");
              return true;
            }
          }
          // success == false or price == null
          print("⚠️ No valid price for $marketHashName");
          return false;

        } else if (res.statusCode == 429) {
          // Rate limited — retry with exponential backoff
          retryAttempt++;
          int waitSeconds = retryAttempt * 10; // 10s, 20s, 30s
          print("🚫 Rate limit (429) for $marketHashName. Retry $retryAttempt/$maxRetries in ${waitSeconds}s");
          if (retryAttempt < maxRetries) {
            await Future.delayed(Duration(seconds: waitSeconds));
          }
        } else {
          // Other HTTP errors (404, 500, etc.)
          print("❌ HTTP ${res.statusCode} for $marketHashName");
          return false;
        }
      } catch (e) {
        retryAttempt++;
        print("❌ Error fetching price for $marketHashName (attempt $retryAttempt): $e");
        if (retryAttempt < maxRetries) {
          await Future.delayed(Duration(seconds: retryAttempt * 5));
        }
      }
    }

    print("❌ Failed completely to fetch price for $marketHashName after $maxRetries attempts");
    return false;
  }

  // ===========================================================================
  // 🎒 PHASE 2.5: CSGO BACKPACK INTEGRATION (INSTANT)
  // ===========================================================================

  Future<void> _updatePricesFromBPInBackground(FlutterBackgroundService service) async {
    try {
      print("🎒 Initializing CSGO Backpack Price Update...");
      
      // 1. Fetch Inventory & Prepare
      final cached = await _storage.loadData('inventory.json');
      if (cached['items'] == null) {
        print("❌ Inventory cache not found.");
        service.invoke("updateNotification", {"content": "Inventory not loaded"});
        service.invoke("stopService");
        return;
      }

      final rawItems = cached['items'] as List<dynamic>;
      final List<InventoryItem> items = rawItems.map((e) => InventoryItem.fromJson(e)).toList();
      
      // Get unique normalized names
      Map<String, String> normalizedToOriginal = {};
      for (var item in items) {
        if (item.marketable == 1) {
          normalizedToOriginal[item.name.trim().toLowerCase()] = item.name;
        }
      }
      
      int totalItems = normalizedToOriginal.length;
      print("🔍 Total unique active items to update: $totalItems");

      // 2. Fetch Bulk API (Skinport)
      print("🌍 Fetching 20,000+ items from Skinport...");
      service.invoke("updateNotification", {"content": "Fetching Backpack API..."});

      final res = await http.get(
        Uri.parse('https://api.skinport.com/v1/items?app_id=730&currency=USD&tradable=0'),
        headers: {
          'Accept-Encoding': 'br', // Force Brotli compression
        },
      );

      if (res.statusCode != 200) {
        print("❌ HTTP Error ${res.statusCode} from Skinport API");
        service.invoke("updateNotification", {"content": "API Error: ${res.statusCode}"});
        service.invoke("stopService");
        return;
      }

      print("✅ Skinport API response received. Decoding Brotli and Parsing JSON...");
      
      final decodedBytes = brotli.decode(res.bodyBytes);
      final jsonString = utf8.decode(decodedBytes);
      final List<dynamic> itemsList = json.decode(jsonString);

      if (itemsList.isEmpty) {
        print("❌ Skinport API returned empty list.");
        service.invoke("stopService");
        return;
      }

      print("📦 Successfully parsed ${itemsList.length} global items.");

      // 3. Match & Update Prices
      int matches = 0;
      final Map<String, dynamic> historyItems = (_history["items"] as Map<String, dynamic>?) ?? {};

      for (var bpData in itemsList) {
        String bpName = bpData["market_hash_name"] as String;
        String normBpName = bpName.trim().toLowerCase();
        
        if (normalizedToOriginal.containsKey(normBpName)) {
           final originalName = normalizedToOriginal[normBpName]!;
           
           // Skinport structure: min_price and suggested_price
           double? newBpPrice;
           try {
             if (bpData["min_price"] != null) {
               newBpPrice = (bpData["min_price"] as num).toDouble();
             } else if (bpData["suggested_price"] != null) {
               newBpPrice = (bpData["suggested_price"] as num).toDouble();
             }
           } catch (e) {
             print("⚠️ Error parsing price for $bpName: $e");
           }

           if (newBpPrice != null && newBpPrice > 0) {
              matches++;
              
              final oldPriceEntry = _prices[originalName] ?? {};
              double? previousBpPrice = oldPriceEntry["bp_price"] != null
                  ? (oldPriceEntry["bp_price"] as num?)?.toDouble()
                  : null;

              _prices[originalName] = {
                ...oldPriceEntry, // Preserve steam_price
                "bp_price": newBpPrice,
                "bp_previous_price": previousBpPrice,
                "time": DateTime.now().millisecondsSinceEpoch
              };
              
              if (historyItems[originalName] == null) {
                historyItems[originalName] = [];
              }
              (historyItems[originalName] as List).add({
                "time": DateTime.now().millisecondsSinceEpoch,
                "bp_price": newBpPrice
              });
           }
        }
      }

      _history["items"] = historyItems;
      
      print("💾 Saving matching Backpack prices to disk ($matches/$totalItems matched)...");
      await _storage.saveData('prices.json', _prices);
      await _storage.saveData('history.json', _history);

      // Update Portfolio Meta
      if (_portfolio["_meta"] == null) _portfolio["_meta"] = {};
      _portfolio["_meta"]["last_bp_price_refresh"] = DateTime.now().millisecondsSinceEpoch;
      await _storage.saveData('portfolio.json', _portfolio);

      // Record total history
      await _recordTotalValueHistory(items);

      print("🎉 Backpack Update Complete in 1 API request!");
      service.invoke("updateNotification", {"content": "Backpack Update Complete!"});

    } catch (e) {
      print("❌ Fatal error in Backpack Update: $e");
      service.invoke("updateNotification", {"content": "Error: $e"});
    } finally {
      await Future.delayed(const Duration(seconds: 4));
      service.invoke("stopService");
    }
  }

  // ===========================================================================
  // MISCELLANEOUS / HELPERS
  // ===========================================================================

  Future<void> _recordTotalValueHistory(List<InventoryItem> items) async {
    // Re-calculate total value with new prices
    double totalSteam = 0;
    double totalBp = 0;
    
    for (var item in items) {
      final priceEntry = _prices[item.name];
      if (priceEntry != null) {
        double? steam = (priceEntry["steam_price"] as num?)?.toDouble();
        double? bp = (priceEntry["bp_price"] as num?)?.toDouble();
        if (steam != null) totalSteam += steam;
        if (bp != null) totalBp += bp;
      }
    }

    if (totalSteam > 0 || totalBp > 0) {
      if (_history["total_value"] == null) _history["total_value"] = [];
      (_history["total_value"] as List).add({
        "time": DateTime.now().millisecondsSinceEpoch,
        "steam_value": totalSteam,
        "bp_value": totalBp
      });
      await _storage.saveData('history.json', _history);
    }
  }

  double? _parsePrice(String? text) {
    if (text == null) return null;
    // Remove currency symbols and parse
    // Example: "$12.50", "12,50 TL"
    String clean = text.replaceAll(RegExp(r'[^\d.,]'), '');
    // Handle comma vs dot
    if (clean.contains(',') && clean.contains('.')) {
       clean = clean.replaceAll('.', '').replaceAll(',', '.');
    } else if (clean.contains(',')) {
       clean = clean.replaceAll(',', '.');
    }
    return double.tryParse(clean);
  }

  Future<bool> savePurchasePrice(String assetId, double? price) async {
    await _loadLocalData();
    if (price == null) {
      if (_portfolio[assetId] != null) {
         _portfolio[assetId]["purchase_price"] = null;
         _portfolio[assetId]["time"] = DateTime.now().millisecondsSinceEpoch;
      }
    } else {
      _portfolio[assetId] = _portfolio[assetId] ?? {};
      _portfolio[assetId]["purchase_price"] = price;
      _portfolio[assetId]["time"] = DateTime.now().millisecondsSinceEpoch;
    }
    await _storage.saveData('portfolio.json', _portfolio);
    return true;
  }

  Future<bool> toggleWatch(String assetId, bool isWatched) async {
    await _loadLocalData();
    _portfolio[assetId] = _portfolio[assetId] ?? {};
    _portfolio[assetId]["watch"] = isWatched;
    _portfolio[assetId]["time"] = DateTime.now().millisecondsSinceEpoch;
    await _storage.saveData('portfolio.json', _portfolio);
    return true;
  }

  Future<List<Map<String, dynamic>>> fetchTotalHistory() async {
    await _loadLocalData();
    return List<Map<String, dynamic>>.from(_history["total_value"] ?? []);
  }

  Future<List<Map<String, dynamic>>> fetchItemHistory(String marketName) async {
    await _loadLocalData();
    return List<Map<String, dynamic>>.from(_history["items"]?[marketName] ?? []);
  }

  /// Returns a map of {itemName: price} for the price closest to [targetTime] for all items.
  /// Used by the market page time range filter (1 day, 1 week, 1 month).
  Future<Map<String, double?>> getPricesAtTimeForAll(DateTime targetTime) async {
    await _loadLocalData();
    final Map<String, double?> result = {};
    final int targetMs = targetTime.millisecondsSinceEpoch;

    final items = _history["items"] as Map<String, dynamic>? ?? {};
    for (var entry in items.entries) {
      final String itemName = entry.key;
      final List<dynamic> historyList = entry.value as List<dynamic>? ?? [];

      if (historyList.isEmpty) {
        result[itemName] = null;
        continue;
      }

      // Find the entry closest to targetTime (but not after it)
      Map<String, dynamic>? best;
      int bestDiff = 999999999999;

      for (var h in historyList) {
        final int t = h["time"] as int;
        if (t <= targetMs) {
          final diff = targetMs - t;
          if (diff < bestDiff) {
            bestDiff = diff;
            best = h as Map<String, dynamic>;
          }
        }
      }

      // If no entry before target, take the earliest available
      if (best == null && historyList.isNotEmpty) {
        best = historyList.first as Map<String, dynamic>;
      }

      result[itemName] = best != null ? (best["price"] as num?)?.toDouble() : null;
    }

    return result;
  }
}
