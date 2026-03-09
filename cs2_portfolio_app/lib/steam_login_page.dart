import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'main.dart';

class SteamLoginPage extends StatefulWidget {
  const SteamLoginPage({super.key});

  @override
  State<SteamLoginPage> createState() => _SteamLoginPageState();
}

class _SteamLoginPageState extends State<SteamLoginPage> {
  late final WebViewController _controller;
  bool _isLoading = true;
  bool _loginDetected = false;

  // Platform channel for native cookie access (handles HttpOnly cookies)
  static const _cookieChannel = MethodChannel('com.cs2portfolio/cookies');

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  void _initWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            setState(() => _isLoading = true);
          },
          onPageFinished: (String url) {
            setState(() => _isLoading = false);
            _checkForLoginCookie();
          },
          onNavigationRequest: (NavigationRequest request) {
            return NavigationDecision.navigate;
          },
        ),
      )
      ..setUserAgent(
        'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
      )
      ..loadRequest(Uri.parse('https://steamcommunity.com/login/home/'));
  }

  Future<void> _checkForLoginCookie() async {
    if (_loginDetected) return;

    try {
      // Use native Android CookieManager via platform channel
      // This reads ALL cookies including HttpOnly ones
      final String? cookies = await _cookieChannel.invokeMethod('getCookies', {
        'url': 'https://steamcommunity.com',
      });

      if (cookies != null && cookies.contains('steamLoginSecure=')) {
        final regex = RegExp(r'steamLoginSecure=([^;]+)');
        final match = regex.firstMatch(cookies);

        if (match != null) {
          String cookieValue = match.group(1)!.trim();
          if (cookieValue.isNotEmpty) {
            _loginDetected = true;
            await _handleSuccessfulLogin(cookieValue);
          }
        }
      }
    } catch (e) {
      print('Error checking cookies via platform channel: $e');
      // Fallback: try JavaScript (won't work for HttpOnly, but worth a shot)
      _checkCookiesViaJavaScript();
    }
  }

  Future<void> _checkCookiesViaJavaScript() async {
    try {
      final String cookies = await _controller.runJavaScriptReturningResult(
        'document.cookie',
      ) as String;

      String cookieStr = cookies;
      if (cookieStr.startsWith('"') && cookieStr.endsWith('"')) {
        cookieStr = cookieStr.substring(1, cookieStr.length - 1);
      }

      if (cookieStr.contains('steamLoginSecure=')) {
        final regex = RegExp(r'steamLoginSecure=([^;]+)');
        final match = regex.firstMatch(cookieStr);

        if (match != null) {
          String cookieValue = match.group(1)!.trim();
          if (cookieValue.isNotEmpty) {
            _loginDetected = true;
            await _handleSuccessfulLogin(cookieValue);
          }
        }
      }
    } catch (e) {
      print('JS cookie fallback also failed: $e');
    }
  }

  Future<void> _handleSuccessfulLogin(String cookieValue) async {
    // Cookie format: 76561198XXXXXXXXX%7C%7CeyAidHlw...
    // The Steam ID is the number before the first %7C%7C (||)
    String steamId = '';

    try {
      String decoded = Uri.decodeComponent(cookieValue);
      List<String> parts = decoded.split('||');
      if (parts.isNotEmpty) {
        steamId = parts[0].trim();
      }
    } catch (e) {
      if (cookieValue.contains('%7C%7C')) {
        steamId = cookieValue.split('%7C%7C')[0].trim();
      } else if (cookieValue.contains('||')) {
        steamId = cookieValue.split('||')[0].trim();
      }
    }

    if (steamId.isEmpty || !steamId.startsWith('7656')) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Login detected but could not parse Steam ID. Please try manual login.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      _loginDetected = false;
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('steamId', steamId);
    await prefs.setString('steamLoginSecure', cookieValue);

    print('✅ Steam login successful! Steam ID: $steamId');
    print('🍪 Cookie captured via native CookieManager');

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Welcome! Steam ID: $steamId'),
          backgroundColor: Colors.greenAccent.shade700,
          duration: const Duration(seconds: 2),
        ),
      );

      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const HomePage()),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Steam Login'),
        centerTitle: true,
        backgroundColor: const Color(0xFF1B2838),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: const Color(0xFF2A475E),
            child: const Row(
              children: [
                Icon(Icons.info_outline, color: Colors.white70, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Log in to your Steam account. This allows the app to fetch prices without rate limits.',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: WebViewWidget(controller: _controller),
          ),
        ],
      ),
    );
  }
}
