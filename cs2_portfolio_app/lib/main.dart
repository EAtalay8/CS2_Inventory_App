import 'package:flutter/material.dart';
import 'inventory_page.dart';
import 'market_page.dart';
import 'services/inventory_service.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: const HomePage(),
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

  @override
  void initState() {
    super.initState();
    loadTotalValue();
  }

  Future<void> loadTotalValue({bool forceUpdate = false}) async {
    setState(() {
      loading = true;
    });

    final service = InventoryService();
    // Steam ID şimdilik hardcoded, ileride dinamik olabilir
    final result = await service.fetchInventory("76561198253002919", forceUpdate: forceUpdate);
    
    if (mounted) {
      setState(() {
        totalValue = result.totalValue;
        totalPurchaseValue = result.totalPurchaseValue;
        totalValueForProfitCalc = result.totalValueForProfitCalc;
        loading = false;
        lastRefreshTime = DateTime.now();
        if (result.lastPriceRefresh != null) {
          lastPriceRefresh = result.lastPriceRefresh;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Profit/Loss Calculation:
    // Only compare (Current Value of Tracked Items) - (Purchase Price of Tracked Items)
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
      ),
      body: Padding(
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

            // Placeholder chart
            Container(
              height: 160,
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                child: Text("Chart Placeholder"),
              ),
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

            const Spacer(),

            // Button to go to item list
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const InventoryPage(),
                        ),
                      ).then((_) {
                        // Refresh when returning from inventory page
                        setState(() { loading = true; });
                        loadTotalValue();
                      });
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
    );
  }
}
