import 'dart:convert';
import 'package:http/http.dart' as http;

import '../models/inventory_item.dart';

class InventoryService {
  static const String baseUrl = "http://192.168.1.25:3000";

  Future<List<InventoryItem>> fetchInventory(String steamId, {int? limit = 20}) async {
    final url = Uri.parse("$baseUrl/inventory/$steamId/priced?limit=$limit");

    final res = await http.get(url);

    if (res.statusCode == 200) {
      final body = json.decode(res.body);

      if (body["success"] == true) {
        final List items = body["items"];
        return items.map((e) => InventoryItem.fromJson(e)).toList();
      }
    }

    return [];
  }
}


