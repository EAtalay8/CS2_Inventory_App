import 'package:flutter/material.dart';
import '../services/inventory_service.dart';
import '../models/inventory_item.dart';
import 'item_detail_page.dart';
import 'package:cs2_portfolio_app/services/rarity_color_service.dart';

// calculateDynamicLimit removed

Widget buildItemCard(BuildContext context, InventoryItem item, {
  bool isGrid = false, 
  int count = 1, 
  VoidCallback? onTap,
  bool isGroup = true,
  double? customProfit,
  double? customProfitPercent,
  int? trackedCount, // 🔥 New parameter
}) {
  double? profitLoss;
  double? profitPercent;
  Color profitColor = Colors.grey;

  if (customProfit != null && customProfitPercent != null) {
    profitLoss = customProfit;
    profitPercent = customProfitPercent;
    profitColor = profitLoss >= 0 ? Colors.green : Colors.red;
  } else if (item.price != null && item.purchasePrice != null && item.purchasePrice! > 0) {
    profitLoss = item.price! - item.purchasePrice!;
    profitPercent = (profitLoss / item.purchasePrice!) * 100;
    profitColor = profitLoss >= 0 ? Colors.green : Colors.red;
  }

  // Helper to format profit text
  String getProfitText() {
    if (profitLoss == null || profitPercent == null) return "";
    String text = "${profitLoss >= 0 ? '+' : ''}\$${profitLoss.toStringAsFixed(2)} (${profitPercent.toStringAsFixed(0)}%)";
    
    // If this is a group and we have partial tracking info
    if (isGroup && count > 1 && trackedCount != null && trackedCount < count) {
      text += " [$trackedCount/$count]";
    }
    return text;
  }

  return Container(
    decoration: BoxDecoration(
      border: Border.all(
        color: getRarityColor(item.rarity), // 🔥 Rarity rengi
        width: 2,
      ),
      borderRadius: BorderRadius.circular(8),
    ),
    child: GestureDetector(
      onTap: onTap ?? () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ItemDetailPage(item: item),
          ),
        ).then((_) {
          // Detay sayfasından dönünce listeyi yenilemek gerekebilir
          // Şimdilik basitçe bırakıyoruz, state yönetimi daha karmaşık olabilir
        });
      },
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(6.0),
            child: isGrid
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      item.icon.isNotEmpty
                        ? Hero(
                          tag: isGroup ? "${item.assetid}_group" : item.assetid,
                          child: Image.network(item.icon, height: 60, fit: BoxFit.contain),
                        )
                        : const Icon(Icons.image_not_supported),
                      const SizedBox(height: 8),
                      Text(
                        item.name,
                        maxLines: 2,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                      const SizedBox(height: 4),

                      // 🔥 PRICE & PROFIT
                      if (item.price != null) ...[
                        Text(
                          "\$${item.price!.toStringAsFixed(2)}",
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (profitLoss != null)
                          Text(
                            getProfitText(),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: profitColor,
                              fontSize: 10,
                            ),
                          ),
                      ] else
                        const Text("-", style: TextStyle(color: Colors.grey)),
                    ],
                  )
                : ListTile(
                    leading: item.icon.isNotEmpty
                        ? Hero(
                            tag: isGroup ? "${item.assetid}_group" : item.assetid,
                            child: Image.network(item.icon, width: 40),
                          )
                        : const Icon(Icons.image_not_supported),
                    title: Text(item.name),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.type),
                        
                        // 🔥 PRICE & PROFIT
                        Row(
                          children: [
                            Text(
                              item.price != null
                                ? "\$${item.price!.toStringAsFixed(2)}"
                                : "-",
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (profitLoss != null) ...[
                              const SizedBox(width: 8),
                              Text(
                                getProfitText(),
                                style: TextStyle(
                                  color: profitColor,
                                  fontSize: 12,
                                ),
                              ),
                            ]
                          ],
                        ),
                      ],
                    ),
                  ),
          ),
          
          // 🔥 COUNT BADGE
          if (count > 1)
            Positioned(
              right: 4,
              bottom: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.orangeAccent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  "x$count",
                  style: const TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}



enum SortOption {
  valueHighToLow,
  priceHighToLow,
  countHighToLow,
  nameAZ,
}

class InventoryPage extends StatefulWidget {
  final String steamId;
  const InventoryPage({super.key, required this.steamId});

  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> {
  List<InventoryItem> items = [];
  Map<String, List<InventoryItem>> groupedItems = {};
  bool loading = true;
  bool isGrid = false;
  SortOption currentSort = SortOption.valueHighToLow; // Default sort

  @override
  void initState() {
    super.initState();
    loadInventory();
  }

  Future<void> loadInventory() async {
    final service = InventoryService();
    final result = await service.fetchInventory(widget.steamId);

    // Group items by name
    final Map<String, List<InventoryItem>> groups = {};
    for (var item in result.items) {
      if (!groups.containsKey(item.name)) {
        groups[item.name] = [];
      }
      groups[item.name]!.add(item);
    }

    if (mounted) {
      setState(() {
        items = result.items;
        groupedItems = groups;
        loading = false;
      });
    }
  }

  List<String> getSortedKeys() {
    final keys = groupedItems.keys.toList();

    keys.sort((a, b) {
      final groupA = groupedItems[a]!;
      final groupB = groupedItems[b]!;
      
      final itemA = groupA.first;
      final itemB = groupB.first;

      final priceA = itemA.price ?? 0;
      final priceB = itemB.price ?? 0;
      
      final countA = groupA.length;
      final countB = groupB.length;

      final valueA = priceA * countA;
      final valueB = priceB * countB;

      switch (currentSort) {
        case SortOption.valueHighToLow:
          return valueB.compareTo(valueA);
        case SortOption.priceHighToLow:
          return priceB.compareTo(priceA);
        case SortOption.countHighToLow:
          return countB.compareTo(countA);
        case SortOption.nameAZ:
          return a.compareTo(b);
      }
    });

    return keys;
  }

  void _showGroupDetails(BuildContext context, String name, List<InventoryItem> groupItems) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) {
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    "$name (${groupItems.length})",
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    itemCount: groupItems.length,
                    itemBuilder: (context, index) {
                      return buildItemCard(context, groupItems[index], isGrid: false, isGroup: false);
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    ).then((_) => loadInventory()); // Refresh when closing sheet
  }



  @override
  Widget build(BuildContext context) {
    final groupKeys = getSortedKeys(); // 🔥 Use sorted keys

    return Scaffold(
      appBar: AppBar(
        title: const Text("Inventory"),
        actions: [
          // Sort Button
          PopupMenuButton<SortOption>(
            icon: const Icon(Icons.sort),
            tooltip: "Sort Items",
            onSelected: (SortOption result) {
              setState(() {
                currentSort = result;
              });
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<SortOption>>[
              const PopupMenuItem<SortOption>(
                value: SortOption.valueHighToLow,
                child: Text('Total Value (High -> Low)'),
              ),
              const PopupMenuItem<SortOption>(
                value: SortOption.priceHighToLow,
                child: Text('Unit Price (High -> Low)'),
              ),
              const PopupMenuItem<SortOption>(
                value: SortOption.countHighToLow,
                child: Text('Count (High -> Low)'),
              ),
              const PopupMenuItem<SortOption>(
                value: SortOption.nameAZ,
                child: Text('Name (A -> Z)'),
              ),
            ],
          ),
          IconButton(
            icon: Icon(isGrid ? Icons.view_list : Icons.grid_view),
            onPressed: () {
              setState(() {
                isGrid = !isGrid;
              });
            }
          )
        ],
      ),
      body: loading 
        ? const Center(child: CircularProgressIndicator())
        : isGrid
        ? GridView.builder(
            padding: const EdgeInsets.all(8),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 0.75,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: groupKeys.length,
            itemBuilder: (context, i) {
              final key = groupKeys[i];
              final group = groupedItems[key]!;
              
              // Calculate summary stats
              double totalCurrentPrice = 0;
              double totalTrackedProfit = 0;
              int trackedCount = 0;

              for (var item in group) {
                  if (item.price != null) {
                    totalCurrentPrice += item.price!;
                  }
                  if (item.price != null && item.purchasePrice != null) {
                      totalTrackedProfit += (item.price! - item.purchasePrice!);
                      trackedCount++;
                  }
              }
              
              // Logic: Diluted ROI
              // Assume untracked items are break-even (Cost = Price)
              // Implied Cost = Total Value - Tracked Profit
              double? calculatedProfit;
              double? calculatedPercent;

              if (totalCurrentPrice > 0 && trackedCount > 0) {
                  calculatedProfit = totalTrackedProfit;
                  
                  double impliedCost = totalCurrentPrice - totalTrackedProfit;
                  if (impliedCost > 0) {
                    calculatedPercent = (totalTrackedProfit / impliedCost) * 100;
                  }
              }
              
              final summaryItem = InventoryItem(
                  assetid: group.first.assetid,
                  classid: group.first.classid,
                  name: group.first.name,
                  icon: group.first.icon,
                  type: group.first.type,
                  marketable: group.first.marketable,
                  price: totalCurrentPrice > 0 ? totalCurrentPrice : null,
                  purchasePrice: null, 
              );

              return buildItemCard(
                context, 
                summaryItem, 
                isGrid: true, 
                count: group.length, 
                customProfit: calculatedProfit,
                customProfitPercent: calculatedPercent,
                trackedCount: trackedCount, // 🔥 Pass tracked count
                onTap: () {
                  if (group.length > 1) {
                    _showGroupDetails(context, key, group);
                  } else {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => ItemDetailPage(item: group.first)),
                    ).then((_) => loadInventory());
                  }
                }
              );
            },
          )
        : ListView.builder(
            itemCount: groupKeys.length,
            itemBuilder: (context, i) {
              final key = groupKeys[i];
              final group = groupedItems[key]!;
              
              // Calculate summary stats
              double totalCurrentPrice = 0;
              double totalTrackedProfit = 0;
              int trackedCount = 0;

              for (var item in group) {
                  if (item.price != null) {
                    totalCurrentPrice += item.price!;
                  }
                  if (item.price != null && item.purchasePrice != null) {
                      totalTrackedProfit += (item.price! - item.purchasePrice!);
                      trackedCount++;
                  }
              }
              
              // Logic: Diluted ROI
              // Assume untracked items are break-even (Cost = Price)
              // Implied Cost = Total Value - Tracked Profit
              double? calculatedProfit;
              double? calculatedPercent;

              if (totalCurrentPrice > 0 && trackedCount > 0) {
                  calculatedProfit = totalTrackedProfit;
                  
                  double impliedCost = totalCurrentPrice - totalTrackedProfit;
                  if (impliedCost > 0) {
                    calculatedPercent = (totalTrackedProfit / impliedCost) * 100;
                  }
              }
              
              final summaryItem = InventoryItem(
                  assetid: group.first.assetid,
                  classid: group.first.classid,
                  name: group.first.name,
                  icon: group.first.icon,
                  type: group.first.type,
                  marketable: group.first.marketable,
                  price: totalCurrentPrice > 0 ? totalCurrentPrice : null,
                  purchasePrice: null, 
              );

              return buildItemCard(
                context, 
                summaryItem, 
                isGrid: false, 
                count: group.length, 
                customProfit: calculatedProfit,
                customProfitPercent: calculatedPercent,
                trackedCount: trackedCount, // 🔥 Pass tracked count
                onTap: () {
                  if (group.length > 1) {
                    _showGroupDetails(context, key, group);
                  } else {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => ItemDetailPage(item: group.first)),
                    ).then((_) => loadInventory());
                  }
                }
              );
            },
          ),
    );
  }
}
