import 'package:http/http.dart' as http;
import 'dart:io';

class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (X509Certificate cert, String host, int port) => true;
  }
}

void main() async {
  HttpOverrides.global = MyHttpOverrides();
  try {
    print('Fetching from allorigins...');
    final response = await http.get(
      Uri.parse('https://api.allorigins.win/raw?url=https%3A%2F%2Fcsgobackpack.net%2Fapi%2FGetItemsList%2Fv2%2F%3Fno_details%3Dtrue'),
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'
      }
    );
    print('Status Code: ${response.statusCode}');
    print('Content Length: ${response.body.length}');
  } catch (e) {
    print('Error: $e');
  }
}
