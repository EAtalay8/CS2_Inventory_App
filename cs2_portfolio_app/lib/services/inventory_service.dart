import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:flutter_background_service/flutter_background_service.dart';
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
  static const Map<String, String> _steamHeaders = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
    "Accept": "application/json, text/plain, */*",
    "Accept-Language": "en-US,en;q=0.9",
    "Connection": "keep-alive",
  };
  
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
          res = await http.get(
            Uri.parse(urlString),
            headers: {
              ..._steamHeaders,
              "Referer": "https://steamcommunity.com/profiles/$steamId/inventory",
            },
          );
          
          print("Status Code: ${res.statusCode}");
          print("Response Body (Start): ${res.body.substring(0, res.body.length > 200 ? 200 : res.body.length)}");

          if (res.statusCode == 200) {
            success = true;
            break;
          } else if (res.statusCode == 429) {
             throw Exception("Rate Limit (429)");
          } else {
             throw Exception("Status ${res.statusCode}");
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

    // Filter items that need update (marketable)
    final uniqueNames = items.where((i) => i.marketable == 1).map((i) => i.name).toSet();
    int total = uniqueNames.length;
    int current = 0;
    
    // Update Meta Timestamp
    if (_portfolio["_meta"] == null) _portfolio["_meta"] = {};
    _portfolio["_meta"]["last_price_refresh"] = DateTime.now().millisecondsSinceEpoch;
    await _storage.saveData('portfolio.json', _portfolio);

    int consecutiveErrors = 0;
    int delayMs = 3500; // Base delay between requests

    for (var name in uniqueNames) {
      current++;
      String progressMsg = "$current/$total";
      
      // Update UI Stream
      _progressController.add(progressMsg);
      
      // Update Notification
      service.invoke("updateNotification", {"content": "Updating prices: $progressMsg"});

      bool success = await _fetchAndSavePrice(name);
      
      // Adaptive delay: slow down on errors, speed up on success
      if (success) {
        consecutiveErrors = 0;
        delayMs = 3500; // Reset to base delay
      } else {
        consecutiveErrors++;
        if (consecutiveErrors >= 3) {
          // 3+ consecutive errors = likely rate limited, pause longer
          delayMs = 15000; // 15 seconds
          print("⚠️ Rate limit detected, slowing down to ${delayMs}ms");
          _progressController.add("$progressMsg (rate limited, slowing down...)");
          service.invoke("updateNotification", {"content": "Rate limited, waiting... $progressMsg"});
        } else {
          delayMs = 5000; // Slightly slower on single errors
        }
      }

      await Future.delayed(Duration(milliseconds: delayMs));
    }
    
    // After all updates, save total value history
    await _recordTotalValueHistory(items);
    
    // Stop Service (or keep it running if you want)
    // service.invoke("stopService"); 
    // Better to keep the notification saying "Done" for a moment then stop
    service.invoke("updateNotification", {"content": "Update Complete!"});
    await Future.delayed(const Duration(seconds: 5));
    service.invoke("stopService");
    _progressController.add(""); // Clear UI
  }

  /// Fetches and saves price for a single item. Returns true on success.
  Future<bool> _fetchAndSavePrice(String marketHashName) async {
    final url = Uri.parse("https://steamcommunity.com/market/priceoverview/?currency=1&appid=730&market_hash_name=${Uri.encodeComponent(marketHashName)}");
    
    // Retry with exponential backoff (up to 3 attempts)
    int retryAttempt = 0;
    const maxRetries = 3;

    while (retryAttempt < maxRetries) {
      try {
        final res = await http.get(url, headers: {
          ..._steamHeaders,
          "Referer": "https://steamcommunity.com/market/",
        });

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
              await _storage.saveData('prices.json', _prices);

              // Update Item History
              if (_history["items"][marketHashName] == null) {
                _history["items"][marketHashName] = [];
              }
              (_history["items"][marketHashName] as List).add({
                "time": DateTime.now().millisecondsSinceEpoch,
                "price": price
              });
              await _storage.saveData('history.json', _history);
              
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
}
