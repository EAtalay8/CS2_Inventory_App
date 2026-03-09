import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'main.dart';
import 'steam_login_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _steamIdController = TextEditingController();
  bool _isLoading = false;
  bool _showManualInput = false;

  Future<void> _login() async {
    final steamId = _steamIdController.text.trim();
    if (steamId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter a Steam ID")),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    // Save to SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('steamId', steamId);

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
      // Navigate to Home
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const HomePage()),
      );
    }
  }

  void _loginWithSteam() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SteamLoginPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E1E), // Dark background
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo placeholder (or icon)
              const Icon(Icons.inventory_2_outlined, size: 80, color: Colors.blueAccent),
              const SizedBox(height: 24),
              
              const Text(
                "CS2 Portfolio",
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 48),

              // 🔥 Primary: Login with Steam button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: _loginWithSteam,
                  icon: const Icon(Icons.login, color: Colors.white),
                  label: const Text(
                    "Login with Steam",
                    style: TextStyle(fontSize: 18, color: Colors.white),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1B2838), // Steam dark blue
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Info text about Steam login benefits
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.greenAccent.withAlpha(26),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.greenAccent.withAlpha(77)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.verified, color: Colors.greenAccent, size: 20),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        "Recommended: Steam login enables faster price updates with less rate limiting.",
                        style: TextStyle(color: Colors.greenAccent, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Toggle for manual input
              GestureDetector(
                onTap: () {
                  setState(() {
                    _showManualInput = !_showManualInput;
                  });
                },
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      "Or enter Steam ID manually",
                      style: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      _showManualInput ? Icons.expand_less : Icons.expand_more,
                      color: Colors.grey.shade400,
                      size: 20,
                    ),
                  ],
                ),
              ),

              // Manual Steam ID input (collapsible)
              if (_showManualInput) ...[
                const SizedBox(height: 16),
                TextField(
                  controller: _steamIdController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: "e.g. 76561198xxxxxxxxx",
                    hintStyle: TextStyle(color: Colors.grey.withAlpha(128)),
                    filled: true,
                    fillColor: Colors.black26,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    prefixIcon: const Icon(Icons.person, color: Colors.grey),
                  ),
                ),
                const SizedBox(height: 12),

                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _login,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text(
                            "Login with Steam ID",
                            style: TextStyle(fontSize: 18, color: Colors.white),
                          ),
                  ),
                ),
              ],

              const SizedBox(height: 32),
              
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orangeAccent.withAlpha(26),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orangeAccent.withAlpha(77)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        "Your Steam Profile and Inventory must be set to PUBLIC for this app to work.",
                        style: TextStyle(color: Colors.orangeAccent, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
