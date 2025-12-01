import 'dart:convert';
import 'package:http/http.dart' as http;

import '../models/inventory_item.dart';

class InventoryResult {
  final List<InventoryItem> items;
  final double totalValue;
  final double totalPurchaseValue;
  final double totalValueForProfitCalc;
  final DateTime? lastPriceRefresh;
  final String? error; // 🔥 Added error field

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
  static const String baseUrl = "http://192.168.1.25:3000";

  Future<InventoryResult> fetchInventory(String steamId, {bool forceUpdate = false}) async {
    final url = Uri.parse("$baseUrl/inventory/$steamId/priced${forceUpdate ? '?update_prices=true' : ''}");

    try {
      final res = await http.get(url);

      if (res.statusCode == 200) {
        final body = json.decode(res.body);

        if (body["success"] == true) {
          final List itemsJson = body["items"];
          final items = itemsJson.map((e) => InventoryItem.fromJson(e)).toList();
          
          final double totalValue = (body["total_value"] ?? 0).toDouble();
          final double totalPurchaseValue = (body["total_purchase_value"] ?? 0).toDouble();
          final double totalValueForProfitCalc = (body["total_value_for_profit_calc"] ?? 0).toDouble();
          
          DateTime? lastPriceRefresh;
          if (body["last_price_refresh"] != null && body["last_price_refresh"] > 0) {
            lastPriceRefresh = DateTime.fromMillisecondsSinceEpoch(body["last_price_refresh"]);
          }

          return InventoryResult(
            items: items,
            totalValue: totalValue,
            totalPurchaseValue: totalPurchaseValue,
            totalValueForProfitCalc: totalValueForProfitCalc,
            lastPriceRefresh: lastPriceRefresh,
          );
        } else {
             return InventoryResult(
                items: [], 
                totalValue: 0, 
                totalPurchaseValue: 0, 
                totalValueForProfitCalc: 0,
                error: body["error"] ?? "Unknown backend error"
            );
        }
      } else {
          return InventoryResult(
            items: [], 
            totalValue: 0, 
            totalPurchaseValue: 0, 
            totalValueForProfitCalc: 0,
            error: "Server error: ${res.statusCode}"
        );
      }
    } catch (e) {
      print("Error fetching inventory: $e");
      return InventoryResult(
        items: [], 
        totalValue: 0.0, 
        totalPurchaseValue: 0.0, 
        totalValueForProfitCalc: 0.0,
        error: "Connection failed: $e"
      );
    }
  }

  Future<bool> savePurchasePrice(String assetId, double? price) async {
    final url = Uri.parse("$baseUrl/portfolio/set-price");
    try {
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "assetId": assetId,
          "price": price,
        }),
      );
      return response.statusCode == 200;
    } catch (e) {
      print("Error setting price: $e");
      return false;
    }
  }

  Future<bool> toggleWatch(String assetId, bool isWatched) async {
    final url = Uri.parse("$baseUrl/portfolio/toggle-watch");
    try {
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "assetId": assetId,
          "isWatched": isWatched,
        }),
      );
      return response.statusCode == 200;
    } catch (e) {
      print("Error toggling watch: $e");
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> fetchTotalHistory() async {
    final url = Uri.parse("$baseUrl/history/total");
    try {
      final res = await http.get(url);
      if (res.statusCode == 200) {
        return List<Map<String, dynamic>>.from(json.decode(res.body));
      }
    } catch (e) {
      print("Error fetching total history: $e");
    }
    return [];
  }

  Future<List<Map<String, dynamic>>> fetchItemHistory(String marketName) async {
    final url = Uri.parse("$baseUrl/history/item/${Uri.encodeComponent(marketName)}");
    try {
      final res = await http.get(url);
      if (res.statusCode == 200) {
        return List<Map<String, dynamic>>.from(json.decode(res.body));
      }
    } catch (e) {
      print("Error fetching item history: $e");
    }
    return [];
  }
}
