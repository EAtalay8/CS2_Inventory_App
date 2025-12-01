import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'inventory_page.dart';
import 'market_page.dart';
import 'services/inventory_service.dart';
import 'widgets/portfolio_chart.dart';
import 'login_page.dart';
import 'models/inventory_item.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final String? steamId = prefs.getString('steamId');

  runApp(MyApp(initialRoute: steamId != null ? '/' : '/login'));
}

class MyApp extends StatelessWidget {
  final String initialRoute;
  const MyApp({super.key, required this.initialRoute});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      initialRoute: initialRoute,
      routes: {
        '/': (context) => const HomePage(),
        '/login': (context) => const LoginPage(),
      },
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  double totalValue = 0.0;
  double totalPurchaseValue = 0.0;
  double totalValueForProfitCalc = 0.0;
  bool loading = true;
  DateTime? lastRefreshTime;
  DateTime? lastPriceRefresh;
  List<InventoryItem> items = []; // Store items for Top Movers
  List<Map<String, dynamic>> history = [];
  String? steamId;
  double minPriceFilter = 0.50; // Default, will be updated from prefs

  @override
  void initState() {
    super.initState();
    _loadSteamId();
  }

  Future<void> _loadSteamId() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      steamId = prefs.getString('steamId');
      minPriceFilter = prefs.getDouble('minPriceFilter') ?? 0.50;
    });
    if (steamId != null) {
      loadTotalValue();
    }
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('steamId');
    if (mounted) {
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  Future<void> loadTotalValue({bool forceUpdate = false}) async {
    if (steamId == null) return;

    setState(() {
      loading = true;
    });

    final service = InventoryService();
    final result = await service.fetchInventory(steamId!, forceUpdate: forceUpdate);
    final historyData = await service.fetchTotalHistory();

    if (mounted) {
      setState(() {
        items = result.items; // 🔥 Save items
        totalValue = result.totalValue;
        totalPurchaseValue = result.totalPurchaseValue;
        totalValueForProfitCalc = result.totalValueForProfitCalc;
        lastRefreshTime = DateTime.now();
        if (result.lastPriceRefresh != null) {
          lastPriceRefresh = result.lastPriceRefresh;
        }
        history = historyData;
        loading = false;
      });

      if (result.error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.error!), 
            backgroundColor: Colors.redAccent,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  Widget _buildTopMovers() {
    // Filter items with price and previousPrice (Market Logic)
    // AND apply minPriceFilter
    final marketItems = items.where((i) => 
      i.price != null && 
      i.previousPrice != null && 
      i.previousPrice! > 0 &&
      i.price! >= minPriceFilter // 🔥 Apply filter
    ).toList();

    if (marketItems.isEmpty) return const SizedBox.shrink();

    marketItems.sort((a, b) {
      final changeA = (a.price! - a.previousPrice!) / a.previousPrice!;
      final changeB = (b.price! - b.previousPrice!) / b.previousPrice!;
      return changeB.compareTo(changeA); // Descending (Highest gain first)
    });

    final top3 = marketItems.take(3).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Daily Top Movers (24h)",
          style: TextStyle(fontSize: 16, color: Colors.grey),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 110,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: top3.length,
            itemBuilder: (context, index) {
              final item = top3[index];
              final change = item.price! - item.previousPrice!;
              final percent = (change / item.previousPrice!) * 100;
              final isPositive = change >= 0;

              return Container(
                width: 100,
                margin: const EdgeInsets.only(right: 12),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isPositive ? Colors.greenAccent.withOpacity(0.3) : Colors.redAccent.withOpacity(0.3)
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    item.icon.isNotEmpty
                        ? Image.network(item.icon, height: 40)
                        : const Icon(Icons.image, size: 40),
                    const SizedBox(height: 8),
                    Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "${isPositive ? '+' : ''}${percent.toStringAsFixed(2)}%",
                      style: TextStyle(
                        color: isPositive ? Colors.greenAccent : Colors.redAccent,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Profit/Loss Calculation:
    double profitLoss = totalValueForProfitCalc - totalPurchaseValue;
    
    // Calculate percentage relative to the TOTAL inventory value (Portfolio Growth)
    double totalCostBasis = totalValue - profitLoss;
    double profitPercent = totalCostBasis > 0 
        ? (profitLoss / totalCostBasis) * 100 
        : 0.0;
    
    Color profitColor = profitLoss >= 0 ? Colors.greenAccent : Colors.redAccent;

    // Cooldown check (4 hours)
    bool canUpdatePrices = true;
    Duration? timeUntilNextUpdate;
    if (lastPriceRefresh != null) {
      final diff = DateTime.now().difference(lastPriceRefresh!);
      if (diff.inHours < 4) {
        canUpdatePrices = false;
        timeUntilNextUpdate = const Duration(hours: 4) - diff;
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("CS2 Portfolio"),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _logout,
            tooltip: "Logout",
          ),
        ],
      ),
      body: SingleChildScrollView( // 🔥 Added ScrollView to prevent overflow
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Total portfolio value
              const Text(
                "Total Value",
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 8),
              loading
                  ? const CircularProgressIndicator()
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              "\$${totalValue.toStringAsFixed(2)}",
                              style: const TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 10),
                            IconButton(
                              icon: const Icon(Icons.refresh, color: Colors.white70),
                              onPressed: () {
                                setState(() {
                                  loading = true;
                                });
                                loadTotalValue();
                              },
                            ),
                          ],
                        ),
                        if (lastRefreshTime != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4.0),
                            child: Text(
                              "Last Refreshed: ${lastRefreshTime!.toLocal().toString().split('.')[0]}",
                              style: const TextStyle(color: Colors.grey, fontSize: 12),
                            ),
                          ),
                      ],
                    ),

              const SizedBox(height: 12),

              // Daily change % box (Actually Total Profit/Loss now)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: profitColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      "${profitLoss >= 0 ? '+' : ''}\$${profitLoss.toStringAsFixed(2)}",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: profitColor,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      "(${profitPercent >= 0 ? '+' : ''}${profitPercent.toStringAsFixed(1)}%)",
                      style: TextStyle(
                        fontSize: 16,
                        color: profitColor,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // 🔥 CHART
              Container(
                height: 200, // Increased height slightly
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: loading 
                    ? const Center(child: CircularProgressIndicator())
                    : PortfolioChart(history: history),
              ),

              const SizedBox(height: 24),

              // Update Prices Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.cloud_sync),
                  label: Text(canUpdatePrices 
                    ? "Update Prices from Steam" 
                    : "Update Available in ${timeUntilNextUpdate?.inHours}:${(timeUntilNextUpdate?.inMinutes ?? 0) % 60}m"
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: canUpdatePrices ? Colors.blueAccent : Colors.grey,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: canUpdatePrices 
                    ? () => loadTotalValue(forceUpdate: true) 
                    : null,
              ),
            ),
              if (lastPriceRefresh != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Center(
                    child: Text(
                      "Prices Last Updated: ${lastPriceRefresh!.toLocal().toString().split('.')[0]}",
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ),
                ),

              const SizedBox(height: 24),

              // 🔥 TOP MOVERS SECTION
              if (!loading) _buildTopMovers(),

              const SizedBox(height: 24),

              // Button to go to item list
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        if (steamId != null) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => InventoryPage(steamId: steamId!),
                            ),
                          ).then((_) {
                            // Refresh when returning from inventory page
                            setState(() { loading = true; });
                            loadTotalValue();
                          });
                        }
                      },
                      child: const Text("Inventory"),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.purpleAccent.withOpacity(0.2),
                        foregroundColor: Colors.purpleAccent,
                      ),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const MarketPage(),
                          ),
                        );
                      },
                      child: const Text("Market"),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
