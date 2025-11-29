import 'package:flutter/material.dart';
import 'models/inventory_item.dart';

class ItemDetailPage extends StatelessWidget {
  final InventoryItem item;

  const ItemDetailPage({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(item.name),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Image
            item.icon.isNotEmpty
              ? Hero(
                  tag: item.assetid,
                  child: Image.network(item.icon, height: 150),
              )
              : const Icon(Icons.image_not_supported, size: 80),

            const SizedBox(height: 16),

            // Name
            Text(
              item.name,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 8),

            // Type
            Text(
              item.type,
              style: const TextStyle(fontSize: 16, color: Colors.grey),
            ),

            const SizedBox(height: 24),

            // IDs
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Asset ID: ${item.assetid}",
                      style: const TextStyle(fontSize: 14)),
                  Text("Class ID: ${item.classid}",
                      style: const TextStyle(fontSize: 14)),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Price Graph Placeholder
            Container(
              height: 180,
              decoration: BoxDecoration(
                color: Colors.black38,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                child: Text(
                  "Price Chart Placeholder\n(No price API yet)",
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
