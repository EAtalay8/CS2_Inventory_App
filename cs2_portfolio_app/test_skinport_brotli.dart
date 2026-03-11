import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:brotli/brotli.dart';

void main() async {
  try {
    print('Fetching from Skinport API with Brotli...');
    final response = await http.get(
      Uri.parse('https://api.skinport.com/v1/items?app_id=730&currency=USD&tradable=0'),
      headers: {
        'Accept-Encoding': 'br',
      },
    );
    print('Status Code: ' + response.statusCode.toString());
    if (response.statusCode == 200) {
      final decodedBytes = brotli.decode(response.bodyBytes);
      final jsonString = utf8.decode(decodedBytes);
      List<dynamic> items = jsonDecode(jsonString);
      print('Items loaded: ' + items.length.toString());
      if (items.isNotEmpty) {
        print('Sample item: ' + items[0]['market_hash_name'].toString());
        print('Min price: ' + items[0]['min_price'].toString());
      }
    } else {
        print('Error body: ' + response.body);
    }
  } catch (e) {
    print('Error: ' + e.toString());
  }
}
