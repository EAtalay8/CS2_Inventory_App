import 'dart:convert';
import 'package:http/http.dart' as http;

import '../models/inventory_item.dart';

class InventoryResult {
  final List<InventoryItem> items;
  final double totalValue;
  final double totalPurchaseValue;
  final double totalValueForProfitCalc;
  final DateTime? lastPriceRefresh;

  InventoryResult({
    required this.items,
    required this.totalValue,
    required this.totalPurchaseValue,
    required this.totalValueForProfitCalc,
    this.lastPriceRefresh,
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
        }
      }
    } catch (e) {
      print("Error fetching inventory: $e");
    }

    return InventoryResult(items: [], totalValue: 0.0, totalPurchaseValue: 0.0, totalValueForProfitCalc: 0.0);
  }

  Future<bool> savePurchasePrice(String assetId, double? price) async {
    final url = Uri.parse("$baseUrl/portfolio/set-price");
    try {
      final res = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: json.encode({
          "assetId": assetId,
          "price": price,
        }),
      );

      if (res.statusCode == 200) {
        return true;
      }
    } catch (e) {
      print("Error saving price: $e");
    }
    return false;
  }
}


