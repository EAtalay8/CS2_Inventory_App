import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
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

  // Cache for loaded data (Static to persist across instances)
  static Map<String, dynamic> _prices = {};
  static Map<String, dynamic> _portfolio = {};
  static Map<String, dynamic> _history = {};

  Future<void> _loadLocalData() async {
    _prices = await _storage.loadData('prices.json');
    _portfolio = await _storage.loadData('portfolio.json');
    _history = await _storage.loadData('history.json');
    
    // Initialize history structure if empty
    if (!_history.containsKey('total_value')) _history['total_value'] = [];
    if (!_history.containsKey('items')) _history['items'] = {};
  }

  // Cache for raw inventory items (mimicking server.js inventoryCache)
  static Map<String, dynamic> _inventoryCache = {};
  static const int _inventoryCacheTTL = 1000 * 60 * 5; // 5 minutes

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
         double? price;
         double? previousPrice;
         DateTime? lastUpdated;

         if (priceEntry != null) {
           price = (priceEntry["price"] as num?)?.toDouble();
           previousPrice = (priceEntry["previous_price"] as num?)?.toDouble();
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
           price: price,
           previousPrice: previousPrice,
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
        _updatePricesInBackground(pricedItems);
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
      // This prevents the inventory from showing $0 when Steam is down
      List<InventoryItem> cachedItems = [];
      double cachedTotalValue = 0;
      double cachedTotalPurchaseValue = 0;
      double cachedTotalValueForProfitCalc = 0;

      final cached = _inventoryCache[steamId];
      if (cached != null) {
        final rawItems = cached['items'] as List<InventoryItem>;
        for (var item in rawItems) {
          final priceEntry = _prices[item.name];
          double? price = priceEntry != null ? (priceEntry["price"] as num?)?.toDouble() : null;
          double? previousPrice = priceEntry != null ? (priceEntry["previous_price"] as num?)?.toDouble() : null;
          final portfolioEntry = _portfolio[item.assetid];
          double? purchasePrice = portfolioEntry != null ? (portfolioEntry["purchase_price"] as num?)?.toDouble() : null;

          final newItem = InventoryItem(
            assetid: item.assetid, classid: item.classid, name: item.name,
            icon: item.icon, type: item.type, marketable: item.marketable,
            price: price, previousPrice: previousPrice, purchasePrice: purchasePrice,
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
    // Cache Check
    final cached = _inventoryCache[steamId];
    if (!forceUpdate && cached != null) {
      final int time = cached['time'];
      if (DateTime.now().millisecondsSinceEpoch - time < _inventoryCacheTTL) {
        print("Serving inventory from cache: $steamId");
        return cached['items'] as List<InventoryItem>;
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
          String urlString = "https://steamcommunity.com/inventory/$steamId/730/2?l=english&count=75";
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
         price: null, // Set later
         previousPrice: null,
         purchasePrice: null,
         isWatched: false,
       ));
    }

    // Update Cache
    _inventoryCache[steamId] = {
      'items': items,
      'time': DateTime.now().millisecondsSinceEpoch
    };

    return items;
  }


  // 🔥 Background Price Update Logic
  Future<void> _updatePricesInBackground(List<InventoryItem> items) async {
    // Start Background Service
    final service = FlutterBackgroundService();
    if (!await service.isRunning()) {
      service.startService();
    }

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
    
    // --- 📦 PHASE 1: BATCH UPDATE (Search/Render) ---
    Set<String> allBatchUpdated = {};
    
    print("🚀 Starting Deep Batch Update Phase (1000 items)...");
    _progressController.add("Deep batching top 1000 skins...");
    
    // Scan 5 pages (500 items total)
    for (int i = 0; i < 10; i++) {
      int start = i * 100;
      final batch = await _fetchPricesInBatch(start, 100);
      allBatchUpdated.addAll(batch);
      
      // Small cooling-off between batches
      if (i < 9) {
        await Future.delayed(const Duration(seconds: 4));
      }
    }

    // Phase transition cool-off (Let Steam breathe)
    if (allBatchUpdated.isNotEmpty) {
      _progressController.add("Found ${allBatchUpdated.length} items. Syncing remaining...");
      await Future.delayed(const Duration(seconds: 10));
    } else {
      _progressController.add("No items found in batch. Syncing all one-by-one...");
      await Future.delayed(const Duration(seconds: 5));
    }

    // --- 🔍 PHASE 2: INDIVIDUAL UPDATE (Fallback) ---
    final remainingNormalized = uniqueNormalizedNames.where((norm) => !allBatchUpdated.contains(norm)).toList();
    int remainingTotal = remainingNormalized.length;
    int current = 0;
    
    print("🔍 Batch Phase Result: Found ${uniqueNormalizedNames.length - remainingTotal} items. ${remainingTotal} remaining.");

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
  Future<Set<String>> _fetchPricesInBatch(int start, int count) async {
    final url = Uri.parse("https://steamcommunity.com/market/search/render/?query=&start=$start&count=$count&search_descriptions=0&sort_column=popular&sort_dir=desc&appid=730&norender=1&currency=1");
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
                  final oldEntry = _prices[rawHashName];
                  double? previousPrice = oldEntry != null ? (oldEntry["price"] as num?)?.toDouble() : null;
                  
                  _prices[rawHashName] = {
                    "price": price,
                    "previous_price": previousPrice,
                    "time": DateTime.now().millisecondsSinceEpoch
                  };
                  
                  if (historyItems[rawHashName] == null) historyItems[rawHashName] = [];
                  (historyItems[rawHashName] as List).add({
                    "time": DateTime.now().millisecondsSinceEpoch,
                    "price": price
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
              final oldEntry = _prices[marketHashName];
              double? previousPrice = oldEntry != null ? (oldEntry["price"] as num?)?.toDouble() : null;

              _prices[marketHashName] = {
                "price": price,
                "previous_price": previousPrice,
                "time": DateTime.now().millisecondsSinceEpoch
              };
              
              if (saveToDisk) await _storage.saveData('prices.json', _prices);

              // Update Item History
              if (_history["items"][marketHashName] == null) {
                _history["items"][marketHashName] = [];
              }
              (_history["items"][marketHashName] as List).add({
                "time": DateTime.now().millisecondsSinceEpoch,
                "price": price
              });
              
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

    print("❌ Failed to fetch price for $marketHashName after $maxRetries attempts");
    return false;
  }

  Future<void> _recordTotalValueHistory(List<InventoryItem> items) async {
    // Re-calculate total value with new prices
    double total = 0;
    for (var item in items) {
      final priceEntry = _prices[item.name];
      if (priceEntry != null) {
        total += (priceEntry["price"] as num).toDouble();
      }
    }

    if (total > 0) {
      (_history["total_value"] as List).add({
        "time": DateTime.now().millisecondsSinceEpoch,
        "value": total
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
      _portfolio.remove(assetId);
    } else {
      _portfolio[assetId] = {
        "purchase_price": price,
        "time": DateTime.now().millisecondsSinceEpoch,
        "watch": _portfolio[assetId]?["watch"] ?? false
      };
    }
    await _storage.saveData('portfolio.json', _portfolio);
    return true;
  }

  Future<bool> toggleWatch(String assetId, bool isWatched) async {
    await _loadLocalData();
    if (_portfolio[assetId] == null) {
      _portfolio[assetId] = {"time": DateTime.now().millisecondsSinceEpoch};
    }
    _portfolio[assetId]["watch"] = isWatched;
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
