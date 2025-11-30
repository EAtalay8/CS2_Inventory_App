import 'package:flutter/material.dart';
import 'models/inventory_item.dart';
import 'services/inventory_service.dart';

class MarketPage extends StatefulWidget {
  const MarketPage({super.key});

  @override
  State<MarketPage> createState() => _MarketPageState();
}

class _MarketPageState extends State<MarketPage> {
  List<InventoryItem> items = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    loadData();
  }

  Future<void> loadData() async {
    final service = InventoryService();
    final result = await service.fetchInventory("76561198253002919");
    
    if (mounted) {
      setState(() {
        // Filter items that have both current and previous price
        items = result.items.where((i) => i.price != null && i.previousPrice != null).toList();
        
        // Sort by % change descending (Top Gainers first)
        items.sort((a, b) {
          double changeA = (a.price! - a.previousPrice!) / a.previousPrice!;
          double changeB = (b.price! - b.previousPrice!) / b.previousPrice!;
          return changeB.compareTo(changeA);
        });
        
        loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Market Movers"),
        centerTitle: true,
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : items.isEmpty
              ? const Center(
                  child: Text(
                    "No price change data available yet.\nUpdate prices to see changes.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              : ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final double change = item.price! - item.previousPrice!;
                    final double percent = (change / item.previousPrice!) * 100;
                    final Color color = change >= 0 ? Colors.greenAccent : Colors.redAccent;

                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      color: Colors.grey[900],
                      child: ListTile(
                        leading: item.icon != null
                            ? Image.network(item.icon!, width: 50, height: 50)
                            : const Icon(Icons.image_not_supported),
                        title: Text(
                          item.name,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          "Prev: \$${item.previousPrice!.toStringAsFixed(2)} -> Now: \$${item.price!.toStringAsFixed(2)}",
                          style: const TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              "${change >= 0 ? '+' : ''}\$${change.toStringAsFixed(2)}",
                              style: TextStyle(
                                color: color,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            Text(
                              "${percent >= 0 ? '+' : ''}${percent.toStringAsFixed(2)}%",
                              style: TextStyle(
                                color: color,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
