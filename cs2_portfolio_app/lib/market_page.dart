import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models/inventory_item.dart';
import 'services/inventory_service.dart';
import 'item_detail_page.dart';
import 'services/rarity_color_service.dart';

class MarketPage extends StatefulWidget {
  const MarketPage({super.key});

  @override
  State<MarketPage> createState() => _MarketPageState();
}

enum MarketRange { day, week, month, threeMonths }

class _MarketPageState extends State<MarketPage> {
  List<InventoryItem> allItems = []; 
  List<List<InventoryItem>> filteredGroups = []; // ğŸ”¥ Store groups of items
  double minPriceFilter = 0.50; 
  bool loading = true; 
  
  MarketRange selectedRange = MarketRange.day;
  Map<String, Map<String, double?>> historicPrices = {}; // Price at the start of the selected range
  String marketPriceSource = 'steam'; // 'steam' or 'skinport'
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
        
        double currentPrice = marketPriceSource == 'steam' ? (group.first.steamPrice ?? 0.0) : (group.first.skinportPrice ?? 0.0);
        if (currentPrice <= 0.0) return false;

        bool priceCondition = currentPrice >= minPriceFilter;
        bool watchCondition = group.any((i) => i.isWatched);
        
        return priceCondition || watchCondition;
      }).toList();

      // 3. Sort groups by % change of the first item
      filteredGroups.sort((a, b) {
        final itemA = a.first;
        final itemB = b.first;

        double currentPriceA = marketPriceSource == 'steam' ? (itemA.steamPrice ?? 0) : (itemA.skinportPrice ?? 0);
        double currentPriceB = marketPriceSource == 'steam' ? (itemB.steamPrice ?? 0) : (itemB.skinportPrice ?? 0);
        
        double basePriceA;
        if (selectedRange == MarketRange.day) {
          basePriceA = marketPriceSource == 'steam' ? (itemA.steamPreviousPrice ?? currentPriceA) : (itemA.skinportPreviousPrice ?? currentPriceA);
        } else {
          basePriceA = historicPrices[itemA.name]?[marketPriceSource] ?? currentPriceA;
        }

        double basePriceB;
        if (selectedRange == MarketRange.day) {
          basePriceB = marketPriceSource == 'steam' ? (itemB.steamPreviousPrice ?? currentPriceB) : (itemB.skinportPreviousPrice ?? currentPriceB);
        } else {
          basePriceB = historicPrices[itemB.name]?[marketPriceSource] ?? currentPriceB;
        }

        double changeA = (currentPriceA - basePriceA) / (basePriceA > 0 ? basePriceA : 1);
        double changeB = (currentPriceB - basePriceB) / (basePriceB > 0 ? basePriceB : 1);
        
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
          // ğŸ”¥ RANGE & FILTER SECTION
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
                    const Text("Source:", style: TextStyle(fontWeight: FontWeight.bold)),
                    SegmentedButton<String>(
                      showSelectedIcon: false,
                      style: SegmentedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                      segments: const [
                        ButtonSegment(value: 'steam', label: Text('Steam')),
                        ButtonSegment(value: 'skinport', label: Text('Skinport')),
                      ],
                      selected: {marketPriceSource},
                      onSelectionChanged: (Set<String> newSelection) {
                        setState(() {
                          marketPriceSource = newSelection.first;
                        });
                        _applyFilter();
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
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
                  "Items below this price are hidden, unless they are in your Watchlist (â­).",
                  style: TextStyle(fontSize: 10, color: Colors.grey),
                ),
              ],
            ),
          ),

          // ğŸ”¥ LIST
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
                        double currentPrice = marketPriceSource == 'steam' ? (item.steamPrice ?? 0) : (item.skinportPrice ?? 0);
                        double basePrice = selectedRange == MarketRange.day 
                            ? (marketPriceSource == 'steam' ? (item.steamPreviousPrice ?? currentPrice) : (item.skinportPreviousPrice ?? currentPrice)) 
                            : (historicPrices[item.name]?[marketPriceSource] ?? currentPrice);

                        final double singleChange = currentPrice - basePrice;
                        final double totalChange = singleChange * count;
                        final double percent = basePrice > 0 ? (singleChange / basePrice) * 100 : 0;
                        final Color color = singleChange >= 0 ? Colors.greenAccent : Colors.redAccent;
                        
                        final bool isAnyWatched = group.any((i) => i.isWatched);

                        final Color rarityColor = getRarityColor(item.rarity);

                        return Container(
                          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF232323),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isAnyWatched ? Colors.yellowAccent : rarityColor.withOpacity(0.5),
                              width: isAnyWatched ? 2.0 : 1.5,
                            ),
                          ),
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
                                ? "Prev: \$${(marketPriceSource == 'steam' ? (item.steamPreviousPrice ?? currentPrice) : (item.skinportPreviousPrice ?? currentPrice)).toStringAsFixed(2)} -> Now: \$${currentPrice.toStringAsFixed(2)}"
                                : "Start: \$${(historicPrices[item.name]?[marketPriceSource] ?? currentPrice).toStringAsFixed(2)} -> Now: \$${currentPrice.toStringAsFixed(2)}",
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


