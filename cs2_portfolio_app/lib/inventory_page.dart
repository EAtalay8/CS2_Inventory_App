import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  bool showBothPrices = false,
  String activePriceSource = 'steam',
}) {
  double? profitLoss;
  double? profitPercent;
  Color profitColor = Colors.grey;

  double? activePrice = activePriceSource == 'steam' ? item.steamPrice : item.bpPrice;
  double? fallbackPrice = item.steamPrice ?? item.bpPrice;
  double? displayPrice = activePrice ?? fallbackPrice;

  if (customProfit != null && customProfitPercent != null) {
    profitLoss = customProfit;
    profitPercent = customProfitPercent;
    profitColor = profitLoss >= 0 ? Colors.green : Colors.red;
  } else if (displayPrice != null && item.purchasePrice != null && item.purchasePrice! > 0) {
    profitLoss = displayPrice - item.purchasePrice!;
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

  return Hero(
    tag: isGroup ? "${item.assetid}_group" : item.assetid,
    child: Container(
      decoration: BoxDecoration(
        color: const Color(0xFF232323),
        border: Border.all(
          color: getRarityColor(item.rarity).withOpacity(0.5),
          width: 1.5,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: getRarityColor(item.rarity).withOpacity(0.1),
            blurRadius: 10,
            spreadRadius: 1,
          )
        ],
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF2D2D2D),
            const Color(0xFF1E1E1E),
          ],
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap ?? () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => ItemDetailPage(item: item)),
            );
          },
          child: Stack(
            children: [
              // Rarity Glow Effect (Subtle)
              Positioned(
                bottom: -20, right: -20,
                child: Container(
                  width: 100, height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: getRarityColor(item.rarity).withOpacity(0.15),
                        blurRadius: 40,
                        spreadRadius: 10,
                      )
                    ],
                  ),
                ),
              ),
              
              Padding(
                padding: const EdgeInsets.all(10.0),
                child: isGrid
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Center(
                              child: item.icon.isNotEmpty
                                ? Image.network(item.icon, fit: BoxFit.contain)
                                : const Icon(Icons.image_not_supported, color: Colors.white24),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            item.name,
                            maxLines: 1,
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: Colors.white),
                          ),
                          const SizedBox(height: 4),

                          // PRICE
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                displayPrice != null ? "\$${displayPrice.toStringAsFixed(2)}" : "-",
                                style: TextStyle(
                                  color: activePriceSource == 'steam' ? Colors.lightBlue[200] : Colors.amber[300],
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          if (showBothPrices) ...[                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (item.steamPrice != null && activePriceSource != 'steam')
                                  Text(
                                    "\$${item.steamPrice!.toStringAsFixed(2)}",
                                    style: TextStyle(color: Colors.lightBlue[200], fontSize: 12, fontWeight: FontWeight.bold),
                                  ),
                                if (item.bpPrice != null && activePriceSource != 'bp')
                                  Text(
                                    "\$${item.bpPrice!.toStringAsFixed(2)}",
                                    style: TextStyle(color: Colors.amber[300], fontSize: 12, fontWeight: FontWeight.bold),
                                  ),
                              ],
                            ),
                          ],

                          if (profitLoss != null)
                            Text(
                              getProfitText(),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: profitColor.withOpacity(0.9),
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                        ],
                      )
                    : Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: item.icon.isNotEmpty
                                ? Image.network(item.icon, width: 50, height: 50)
                                : const Icon(Icons.image_not_supported, color: Colors.white24, size: 40),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  item.name, 
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(item.type, style: const TextStyle(color: Colors.white38, fontSize: 11)),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Text(
                                      displayPrice != null ? "\$${displayPrice.toStringAsFixed(2)}" : "-",
                                      style: TextStyle(
                                        color: activePriceSource == 'steam' ? Colors.lightBlue[200] : Colors.amber[300],
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                    if (showBothPrices) ...[
                                      const SizedBox(width: 8),
                                      if (item.steamPrice != null && activePriceSource != 'steam')
                                        Text(
                                          "\$${item.steamPrice!.toStringAsFixed(2)}",
                                          style: TextStyle(color: Colors.lightBlue[200], fontWeight: FontWeight.bold, fontSize: 14),
                                        ),
                                      if (item.bpPrice != null && activePriceSource != 'bp')
                                        Text(
                                          "\$${item.bpPrice!.toStringAsFixed(2)}",
                                          style: TextStyle(color: Colors.amber[300], fontWeight: FontWeight.bold, fontSize: 14),
                                        ),
                                    ],
                                    if (profitLoss != null) ...[
                                      const SizedBox(width: 12),
                                      Text(
                                        getProfitText(),
                                        style: TextStyle(color: profitColor, fontSize: 12, fontWeight: FontWeight.w600),
                                      ),
                                    ]
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right, color: Colors.white24),
                        ],
                      ),
              ),
              
              // COUNT BADGE
              if (count > 1)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.orangeAccent,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 4, offset: const Offset(0, 2)),
                      ],
                    ),
                    child: Text(
                      "x$count",
                      style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 11),
                    ),
                  ),
                ),
            ],
          ),
        ),
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
  
  bool showBothPrices = false;
  String activePriceSource = 'steam';

  // --- Filter State ---
  Map<String, Set<String>> selectedFilters = {}; // Category -> Set of Subcategories
  // If a category is in the map but the set is empty, it means "All" for that category.
  // If the map is completely empty, it means no filtering.

  @override
  void initState() {
    super.initState();
    _loadSettingsAndInventory();
  }

  Future<void> _loadSettingsAndInventory() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
         showBothPrices = prefs.getBool('showBothPrices') ?? false;
         activePriceSource = prefs.getString('activePriceSource') ?? 'steam';
         isGrid = prefs.getBool('isGrid') ?? false;
      });
    }
    await loadInventory();
  }

  Future<void> loadInventory() async {
    final service = InventoryService();
    try {
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
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error: $e"), 
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          loading = false;
        });
      }
    }
  }

  double _getItemPrice(InventoryItem item) {
    if (showBothPrices) {
      return (item.steamPrice ?? item.bpPrice ?? 0);
    }
    return (activePriceSource == 'steam' ? item.steamPrice : item.bpPrice) ?? (item.steamPrice ?? item.bpPrice ?? 0);
  }

  List<InventoryItem> getFilteredItems() {
    if (selectedFilters.isEmpty) return items;

    return items.where((item) {
      final cat = item.category;
      final subCat = item.subCategory;

      if (!selectedFilters.containsKey(cat)) return false;
      
      final allowedSubs = selectedFilters[cat]!;
      if (allowedSubs.isEmpty) return true; // All subcategories in this category allowed
      
      return allowedSubs.contains(subCat);
    }).toList();
  }

  List<String> getSortedKeys(Map<String, List<InventoryItem>> currentGroups) {
    final keys = currentGroups.keys.toList();

    keys.sort((a, b) {
      final groupA = currentGroups[a]!;
      final groupB = currentGroups[b]!;
      
      final itemA = groupA.first;
      final itemB = groupB.first;

      final priceA = _getItemPrice(itemA);
      final priceB = _getItemPrice(itemB);
      
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

  void _showFilterSheet() {
    final Map<String, Set<String>> allCategories = {};
    for (var item in items) {
      final cat = item.category;
      final subCat = item.subCategory;
      if (!allCategories.containsKey(cat)) allCategories[cat] = {};
      if (cat != subCat) allCategories[cat]!.add(subCat);
    }

    final sortedCats = allCategories.keys.toList()
      ..sort((a, b) {
        if (a == "Weapons") return -1;
        if (b == "Weapons") return 1;
        return a.compareTo(b);
      });

    showDialog(
      context: context,
      barrierColor: Colors.black38,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.only(top: 80, right: 8),
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    width: 280,
                    constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1E1E),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white10),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 20, spreadRadius: 2)],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text("Filters", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                              if (selectedFilters.isNotEmpty)
                                GestureDetector(
                                  onTap: () { setDialogState(() => selectedFilters.clear()); setState(() {}); },
                                  child: const Padding(padding: EdgeInsets.all(8.0), child: Text("Clear", style: TextStyle(color: Colors.orangeAccent, fontSize: 13))),
                                ),
                            ],
                          ),
                        ),
                        const Divider(color: Colors.white10, height: 1),
                        Flexible(
                          child: ListView(
                            shrinkWrap: true,
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            children: sortedCats.map((cat) {
                              final subs = allCategories[cat]!;
                              final isCatSelected = selectedFilters.containsKey(cat);
                              final selectedSubs = selectedFilters[cat] ?? {};

                              if (subs.isEmpty) {
                                return _filterRow(cat, isCatSelected, false, () {
                                  setDialogState(() { if (isCatSelected) { selectedFilters.remove(cat); } else { selectedFilters[cat] = {}; } });
                                  setState(() {});
                                });
                              }

                              return Theme(
                                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                                child: ExpansionTile(
                                  tilePadding: const EdgeInsets.symmetric(horizontal: 12),
                                  dense: true,
                                  leading: SizedBox(width: 24, height: 24, child: Checkbox(
                                    value: isCatSelected, activeColor: Colors.orangeAccent, checkColor: Colors.black,
                                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    onChanged: (val) { setDialogState(() { if (val == true) { selectedFilters[cat] = {}; } else { selectedFilters.remove(cat); } }); setState(() {}); },
                                  )),
                                  title: Text(cat, style: const TextStyle(color: Colors.white, fontSize: 14)),
                                  children: subs.map((sub) {
                                    final isSubSelected = selectedSubs.contains(sub);
                                    return _filterRow(sub, isSubSelected, true, () {
                                      setDialogState(() {
                                        if (isSubSelected) { selectedFilters[cat]?.remove(sub); }
                                        else { if (!selectedFilters.containsKey(cat)) selectedFilters[cat] = {}; selectedFilters[cat]!.add(sub); }
                                      });
                                      setState(() {});
                                    });
                                  }).toList(),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _filterRow(String label, bool isSelected, bool indent, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: indent ? 24 : 12, vertical: 8),
        child: Row(children: [
          SizedBox(width: 24, height: 24, child: Checkbox(
            value: isSelected, activeColor: Colors.orangeAccent, checkColor: Colors.black,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap, onChanged: (_) => onTap(),
          )),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: TextStyle(color: indent ? Colors.white60 : Colors.white, fontSize: indent ? 13 : 14))),
        ]),
      ),
    );
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
                      return buildItemCard(context, groupItems[index], isGrid: false, isGroup: false, showBothPrices: showBothPrices, activePriceSource: activePriceSource);
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
    // 1. Filter
    final filtered = getFilteredItems();
    
    // 2. Group
    final Map<String, List<InventoryItem>> groups = {};
    for (var item in filtered) {
      if (!groups.containsKey(item.name)) groups[item.name] = [];
      groups[item.name]!.add(item);
    }

    // 3. Sort
    final groupKeys = getSortedKeys(groups);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Inventory", style: TextStyle(fontWeight: FontWeight.bold)),
        elevation: 0,
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            icon: Stack(
              children: [
                const Icon(Icons.filter_list),
                if (selectedFilters.isNotEmpty)
                  Positioned(
                    right: 0, top: 0,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(color: Colors.orangeAccent, shape: BoxShape.circle),
                      constraints: const BoxConstraints(minWidth: 8, minHeight: 8),
                    ),
                  )
              ],
            ),
            onPressed: _showFilterSheet,
            tooltip: "Filter Library",
          ),
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
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              setState(() {
                isGrid = !isGrid;
              });
              prefs.setBool('isGrid', isGrid);
            }
          )
        ],
      ),
      extendBodyBehindAppBar: false,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.grey[900]!, Colors.black],
          ),
        ),
        child: loading 
          ? const Center(child: CircularProgressIndicator(color: Colors.orangeAccent))
          : groupKeys.isEmpty 
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.search_off, size: 64, color: Colors.white24),
                    const SizedBox(height: 16),
                    Text(
                      items.isEmpty ? "Inventory Empty" : "No items match filters",
                      style: const TextStyle(color: Colors.white54, fontSize: 18),
                    ),
                    if (selectedFilters.isNotEmpty)
                      TextButton(
                        onPressed: () => setState(() => selectedFilters.clear()),
                        child: const Text("Clear Filters", style: TextStyle(color: Colors.orangeAccent)),
                      )
                  ],
                ),
              )
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
              final group = groups[key]!;
              
              double totalSteamPrice = 0;
              double totalBpPrice = 0;
              double totalTrackedProfit = 0;
              double sumActiveCurrentPrice = 0;
              int trackedCount = 0;

              for (var item in group) {
                  if (item.steamPrice != null) totalSteamPrice += item.steamPrice!;
                  if (item.bpPrice != null) totalBpPrice += item.bpPrice!;
                  
                  double? activePrice = (activePriceSource == 'steam' ? item.steamPrice : item.bpPrice) ?? (item.steamPrice ?? item.bpPrice);
                  
                  if (activePrice != null) {
                    sumActiveCurrentPrice += activePrice;
                  }
                  
                  if (activePrice != null && item.purchasePrice != null) {
                      totalTrackedProfit += (activePrice - item.purchasePrice!);
                      trackedCount++;
                  }
              }
              
              double? calculatedProfit;
              double? calculatedPercent;
              if (sumActiveCurrentPrice > 0 && trackedCount > 0) {
                  calculatedProfit = totalTrackedProfit;
                  double impliedCost = sumActiveCurrentPrice - totalTrackedProfit;
                  if (impliedCost > 0) calculatedPercent = (totalTrackedProfit / impliedCost) * 100;
              }
              
              final summaryItem = InventoryItem(
                  assetid: group.first.assetid,
                  classid: group.first.classid,
                  name: group.first.name,
                  icon: group.first.icon,
                  type: group.first.type,
                  marketable: group.first.marketable,
                  steamPrice: totalSteamPrice > 0 ? totalSteamPrice : null,
                  bpPrice: totalBpPrice > 0 ? totalBpPrice : null,
              );

              return buildItemCard(
                context, 
                summaryItem, 
                isGrid: true, 
                count: group.length, 
                customProfit: calculatedProfit,
                customProfitPercent: calculatedPercent,
                trackedCount: trackedCount,
                showBothPrices: showBothPrices,
                activePriceSource: activePriceSource,
                onTap: () {
                  if (group.length > 1) {
                    _showGroupDetails(context, key, group);
                  } else {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => ItemDetailPage(item: group.first)),
                    ).then((_) => loadInventory());
                  }
                },
              );
            },
          )
        : ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: groupKeys.length,
            itemBuilder: (context, i) {
              final key = groupKeys[i];
              final group = groups[key]!;
              
              double totalSteamPrice = 0;
              double totalBpPrice = 0;
              double totalTrackedProfit = 0;
              double sumActiveCurrentPrice = 0;
              int trackedCount = 0;

              for (var item in group) {
                  if (item.steamPrice != null) totalSteamPrice += item.steamPrice!;
                  if (item.bpPrice != null) totalBpPrice += item.bpPrice!;
                  double? activePrice = (activePriceSource == 'steam' ? item.steamPrice : item.bpPrice) ?? (item.steamPrice ?? item.bpPrice);
                  if (activePrice != null) sumActiveCurrentPrice += activePrice;
                  if (activePrice != null && item.purchasePrice != null) {
                      totalTrackedProfit += (activePrice - item.purchasePrice!);
                      trackedCount++;
                  }
              }
              
              double? calculatedProfit;
              double? calculatedPercent;
              if (sumActiveCurrentPrice > 0 && trackedCount > 0) {
                  calculatedProfit = totalTrackedProfit;
                  double impliedCost = sumActiveCurrentPrice - totalTrackedProfit;
                  if (impliedCost > 0) calculatedPercent = (totalTrackedProfit / impliedCost) * 100;
              }
              
              final summaryItem = InventoryItem(
                  assetid: group.first.assetid,
                  classid: group.first.classid,
                  name: group.first.name,
                  icon: group.first.icon,
                  type: group.first.type,
                  marketable: group.first.marketable,
                  steamPrice: totalSteamPrice > 0 ? totalSteamPrice : null,
                  bpPrice: totalBpPrice > 0 ? totalBpPrice : null,
              );

              return buildItemCard(
                context, 
                summaryItem, 
                isGrid: false, 
                count: group.length, 
                customProfit: calculatedProfit,
                customProfitPercent: calculatedPercent,
                trackedCount: trackedCount,
                showBothPrices: showBothPrices,
                activePriceSource: activePriceSource,
                onTap: () {
                  if (group.length > 1) {
                    _showGroupDetails(context, key, group);
                  } else {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => ItemDetailPage(item: group.first)),
                    ).then((_) => loadInventory());
                  }
                },
              );
            },
          ),
      ),
    );
  }
}
