import 'package:http/http.dart' as http;
import 'dart:convert';

void main() async {
  try {
    print('Fetching from Skinport API (Auto Encoding)...');
    final response = await http.get(
      Uri.parse('https://api.skinport.com/v1/items?app_id=730&currency=USD&tradable=0'),
    );
    print('Status Code: ' + response.statusCode.toString());
    if (response.statusCode == 200) {
      List<dynamic> items = jsonDecode(response.body);
      print('Items loaded: ' + items.length.toString());
      if (items.isNotEmpty) {
        print('Sample item: ' + items[0]['market_hash_name'].toString());
        print('Min price: ' + items[0]['min_price'].toString());
        print('Suggested price: ' + items[0]['suggested_price'].toString());
      }
    } else {
        print('Error body: ' + response.body);
    }
  } catch (e) {
    print('Error: ' + e.toString());
  }
}
