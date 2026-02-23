import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models/inventory_item.dart';
import 'services/inventory_service.dart';
import 'item_detail_page.dart';

class MarketPage extends StatefulWidget {
  const MarketPage({super.key});

  @override
  State<MarketPage> createState() => _MarketPageState();
}

enum MarketRange { day, week, month, threeMonths }

class _MarketPageState extends State<MarketPage> {
  List<InventoryItem> allItems = []; 
  List<List<InventoryItem>> filteredGroups = []; // 🔥 Store groups of items
  double minPriceFilter = 0.50; 
  bool loading = true; 
  
  MarketRange selectedRange = MarketRange.day;
  Map<String, double?> historicPrices = {}; // Price at the start of the selected range
  @override
  void initState() {
    super.initState();
    _loadFilterPreference();
    loadData();
  }

  Future<void> _loadFilterPreference() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      minPriceFilter = prefs.getDouble('minPriceFilter') ?? 0.50;
    });
  }

  Future<void> loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final String? steamId = prefs.getString('steamId');
    
    if (steamId == null) return;

    final service = InventoryService();
    final result = await service.fetchInventory(steamId);
    
    // Load historical prices if needed
    if (selectedRange != MarketRange.day) {
      DateTime target;
      if (selectedRange == MarketRange.week) {
        target = DateTime.now().subtract(const Duration(days: 7));
      } else if (selectedRange == MarketRange.month) {
        target = DateTime.now().subtract(const Duration(days: 30));
      } else {
        target = DateTime.now().subtract(const Duration(days: 90));
      }
      historicPrices = await service.getPricesAtTimeForAll(target);
    } else {
      historicPrices = {};
    }

    if (mounted) {
      allItems = result.items.where((i) => i.price != null).toList();
      _applyFilter(); 
      setState(() {
        loading = false;
      });
    }
  }

  void _applyFilter() {
    setState(() {
      // 1. Group items by classid
      Map<String, List<InventoryItem>> groups = {};
      for (var item in allItems) {
        if (!groups.containsKey(item.classid)) {
          groups[item.classid] = [];
        }
        groups[item.classid]!.add(item);
      }

      // 2. Filter groups
      filteredGroups = groups.values.where((group) {
        if (group.isEmpty) return false;
        
        // Show group if ANY item is watched OR if price > min
        // Since they are identical, price is same for all.
        // But watch status might differ (though ideally should be same for classid, but currently per assetid)
        
        bool priceCondition = group.first.price! >= minPriceFilter;
        bool watchCondition = group.any((i) => i.isWatched);
        
        return priceCondition || watchCondition;
      }).toList();

      // 3. Sort groups by % change of the first item
      filteredGroups.sort((a, b) {
        final itemA = a.first;
        final itemB = b.first;

        double basePriceA = selectedRange == MarketRange.day 
            ? (itemA.previousPrice ?? itemA.price!) 
            : (historicPrices[itemA.name] ?? itemA.price!);
        double basePriceB = selectedRange == MarketRange.day 
            ? (itemB.previousPrice ?? itemB.price!) 
            : (historicPrices[itemB.name] ?? itemB.price!);

        double changeA = (itemA.price! - basePriceA) / (basePriceA > 0 ? basePriceA : 1);
        double changeB = (itemB.price! - basePriceB) / (basePriceB > 0 ? basePriceB : 1);
        
        return changeB.compareTo(changeA);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Market Movers"),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // 🔥 RANGE & FILTER SECTION
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.black12,
            child: Column(
              children: [
                SegmentedButton<MarketRange>(
                  segments: const [
                    ButtonSegment(value: MarketRange.day, label: Text("1D"), tooltip: "24-hour Change"),
                    ButtonSegment(value: MarketRange.week, label: Text("1W"), tooltip: "7-day Change"),
                    ButtonSegment(value: MarketRange.month, label: Text("1M"), tooltip: "30-day Change"),
                    ButtonSegment(value: MarketRange.threeMonths, label: Text("3M"), tooltip: "90-day Change"),
                  ],
                  selected: {selectedRange},
                  onSelectionChanged: (Set<MarketRange> newSelection) {
                    setState(() {
                      selectedRange = newSelection.first;
                      loading = true;
                    });
                    loadData();
                  },
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("Min Price Filter:", style: TextStyle(fontWeight: FontWeight.bold)),
                    Text("\$${minPriceFilter.toStringAsFixed(2)}"),
                  ],
                ),
                Slider(
                  value: minPriceFilter,
                  min: 0.0,
                  max: 10.0,
                  divisions: 20,
                  label: "\$${minPriceFilter.toStringAsFixed(2)}",
                  onChanged: (val) async {
                    setState(() {
                      minPriceFilter = val;
                    });
                    _applyFilter();
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setDouble('minPriceFilter', val);
                  },
                ),
                const Text(
                  "Items below this price are hidden, unless they are in your Watchlist (⭐).",
                  style: TextStyle(fontSize: 10, color: Colors.grey),
                ),
              ],
            ),
          ),

          // 🔥 LIST
          Expanded(
            child: loading
              ? const Center(child: CircularProgressIndicator())
              : filteredGroups.isEmpty
                  ? const Center(
                      child: Text(
                        "No items match your filter.\nTry lowering the minimum price.",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.builder(
                      itemCount: filteredGroups.length,
                      itemBuilder: (context, index) {
                        final group = filteredGroups[index];
                        final item = group.first;
                        final int count = group.length;

                        // Calculate totals for the group
                        double basePrice = selectedRange == MarketRange.day 
                            ? (item.previousPrice ?? item.price!) 
                            : (historicPrices[item.name] ?? item.price!);

                        final double singleChange = item.price! - basePrice;
                        final double totalChange = singleChange * count;
                        final double percent = basePrice > 0 ? (singleChange / basePrice) * 100 : 0;
                        final Color color = singleChange >= 0 ? Colors.greenAccent : Colors.redAccent;
                        
                        final bool isAnyWatched = group.any((i) => i.isWatched);

                        return Card(
                          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          color: Colors.grey[900],
                          shape: isAnyWatched 
                            ? RoundedRectangleBorder(
                                side: const BorderSide(color: Colors.yellowAccent, width: 1),
                                borderRadius: BorderRadius.circular(12)
                              ) 
                            : null,
                          child: ListTile(
                            leading: Stack(
                              children: [
                                item.icon.isNotEmpty
                                    ? Image.network(item.icon, width: 50, height: 50)
                                    : const Icon(Icons.image_not_supported),
                                if (isAnyWatched)
                                  const Positioned(
                                    top: 0,
                                    right: 0,
                                    child: Icon(Icons.star, size: 12, color: Colors.yellowAccent),
                                  ),
                              ],
                            ),
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    item.name,
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (count > 1)
                                  Container(
                                    margin: const EdgeInsets.only(left: 8),
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.white24,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      "x$count",
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                              ],
                            ),
                            subtitle: Text(
                              selectedRange == MarketRange.day
                                ? "Prev: \$${(item.previousPrice ?? item.price!).toStringAsFixed(2)} -> Now: \$${item.price!.toStringAsFixed(2)}"
                                : "Start: \$${(historicPrices[item.name] ?? item.price!).toStringAsFixed(2)} -> Now: \$${item.price!.toStringAsFixed(2)}",
                              style: const TextStyle(color: Colors.grey, fontSize: 12),
                            ),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  "${totalChange >= 0 ? '+' : ''}\$${totalChange.toStringAsFixed(2)}", // Total change for stack
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
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ItemDetailPage(item: item),
                                ),
                              );
                            },
                          ),
                        );
                      },
                    ),
          ),
        ],
      ),
    );
  }
}
