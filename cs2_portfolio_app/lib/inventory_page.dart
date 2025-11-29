import 'package:flutter/material.dart';
import '../services/inventory_service.dart';
import '../models/inventory_item.dart';
import 'item_detail_page.dart';
import 'package:cs2_portfolio_app/services/rarity_color_service.dart';

Widget buildItemCard(BuildContext context, InventoryItem item, {bool isGrid = false}) {
  return Container(
    decoration: BoxDecoration(
      border: Border.all(
        color: getRarityColor(item.rarity), // 🔥 Rarity rengi
        width: 2,
      ),
      borderRadius: BorderRadius.circular(8),
    ),
    child: GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ItemDetailPage(item: item),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.all(6.0),
        child: isGrid
            ? Column(
                children: [
                  item.icon.isNotEmpty
                    ? Hero(
                      tag: item.assetid,
                      child: Image.network(item.icon, height: 60),
                    )
                    : const Icon(Icons.image_not_supported),
                  const SizedBox(height: 4),
                  Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              )
            : ListTile(
                leading: item.icon.isNotEmpty
                    ? Hero(
                      tag: item.assetid,
                      child: Image.network(item.icon, width: 40),
                    )
                    : const Icon(Icons.image_not_supported),
                title: Text(item.name),
                subtitle: Text("${item.type}\nAssetID: ${item.assetid}"),
              ),
      ),
    ),
  );
}



class InventoryPage extends StatefulWidget {
  const InventoryPage({super.key});

  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> {
  List<InventoryItem> items = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    loadInventory();
  }

  Future<void> loadInventory() async {
    final service = InventoryService();
    final data = await service.fetchInventory("76561198253002919");

    setState(() {
      items = data;
      loading = false;
    });
  }

  bool isGrid = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Inventory"),
        actions: [
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
              crossAxisCount: 3,   // 3 sütun
              childAspectRatio: 0.75,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: items.length,
            itemBuilder: (context, i) {
              final item = items[i];

              return buildItemCard(context, item, isGrid: true);
            },
          )
        : ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, i) {
              final item = items[i];

              return buildItemCard(context, item, isGrid: false);
            },
          ),
    );
  }
}
