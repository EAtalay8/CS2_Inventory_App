import 'package:flutter/material.dart';
import 'models/inventory_item.dart';
import 'services/inventory_service.dart';
import 'widgets/portfolio_chart.dart';

class ItemDetailPage extends StatefulWidget {
  final InventoryItem item;

  const ItemDetailPage({super.key, required this.item});

  @override
  State<ItemDetailPage> createState() => _ItemDetailPageState();
}

class _ItemDetailPageState extends State<ItemDetailPage> {
  final TextEditingController _priceController = TextEditingController();
  double? purchasePrice;
  bool isSaving = false;
  bool isWatched = false;
  List<Map<String, dynamic>> history = []; // 🔥 History data
  bool loadingHistory = true;

  @override
  void initState() {
    super.initState();
    purchasePrice = widget.item.purchasePrice;
    isWatched = widget.item.isWatched; 
    if (purchasePrice != null) {
      _priceController.text = purchasePrice.toString();
    }
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final service = InventoryService();
    // Use market name for history lookup
    final data = await service.fetchItemHistory(widget.item.name);
    if (mounted) {
      setState(() {
        history = data;
        loadingHistory = false;
      });
    }
  }

  Future<void> _toggleWatch() async {
    setState(() {
      isWatched = !isWatched;
    });

    final service = InventoryService();
    final success = await service.toggleWatch(widget.item.assetid, isWatched);

    if (!success) {
      // Revert if failed
      setState(() {
        isWatched = !isWatched;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Failed to update watch status")),
        );
      }
    }
  }

  Future<void> _savePrice({bool reset = false}) async {
    double? price;
    if (!reset) {
      price = double.tryParse(_priceController.text);
      if (price == null) return;
    }

    setState(() {
      isSaving = true;
    });

    final service = InventoryService();
    final success = await service.savePurchasePrice(widget.item.assetid, price);

    if (mounted) {
      setState(() {
        isSaving = false;
        if (success) {
          purchasePrice = price;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(reset ? "Price reset!" : "Purchase price saved!")),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Failed to save price")),
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentPrice = widget.item.price;
    double? profitLoss;
    double? profitLossPercent;
    Color profitColor = Colors.grey;

    if (currentPrice != null && purchasePrice != null && purchasePrice! > 0) {
      profitLoss = currentPrice - purchasePrice!;
      profitLossPercent = (profitLoss / purchasePrice!) * 100;
      profitColor = profitLoss >= 0 ? Colors.green : Colors.red;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.item.name),
        actions: [
          IconButton(
            icon: Icon(
              isWatched ? Icons.star : Icons.star_border,
              color: isWatched ? Colors.yellowAccent : null,
            ),
            onPressed: _toggleWatch,
            tooltip: isWatched ? "Remove from Watchlist" : "Add to Watchlist",
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Image
            widget.item.icon.isNotEmpty
              ? Hero(
                  tag: widget.item.assetid,
                  child: Image.network(widget.item.icon, height: 150),
              )
              : const Icon(Icons.image_not_supported, size: 80),

            const SizedBox(height: 16),

            // Name
            Text(
              widget.item.name,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 8),

            // Type
            Text(
              widget.item.type,
              style: const TextStyle(fontSize: 16, color: Colors.grey),
            ),

            const SizedBox(height: 24),

            // 🔥 PRICE HISTORY CHART
            const Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: EdgeInsets.only(bottom: 8.0),
                child: Text("Price History", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
            ),
            Container(
              height: 200,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(12),
              ),
              child: loadingHistory
                  ? const Center(child: CircularProgressIndicator())
                  : PortfolioChart(
                      history: history,
                      isItemHistory: true, // Use item styling
                    ),
            ),

            const SizedBox(height: 24),

            // --- PRICE SECTION ---
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  // Current Price
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Current Price:", style: TextStyle(fontSize: 16)),
                      Text(
                        currentPrice != null ? "\$${currentPrice.toStringAsFixed(2)}" : "Loading...",
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  
                  // Purchase Price Input
                  Row(
                    children: [
                      const Text("Bought At: \$", style: TextStyle(fontSize: 16)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _priceController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            hintText: "0.00",
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (isSaving)
                        const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      else ...[
                        IconButton(
                          icon: const Icon(Icons.save, color: Colors.blueAccent),
                          onPressed: _savePrice,
                          tooltip: "Save Price",
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                          onPressed: () async {
                             _priceController.clear();
                             await _savePrice(reset: true);
                          },
                          tooltip: "Reset Price",
                        ),
                      ]
                    ],
                  ),

                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),

                  // Profit / Loss Display
                  if (profitLoss != null) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Profit / Loss:", style: TextStyle(fontSize: 16)),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              "${profitLoss >= 0 ? '+' : ''}\$${profitLoss.toStringAsFixed(2)}",
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: profitColor,
                              ),
                            ),
                            Text(
                              "${profitLossPercent! >= 0 ? '+' : ''}${profitLossPercent.toStringAsFixed(1)}%",
                              style: TextStyle(
                                fontSize: 14,
                                color: profitColor.withOpacity(0.8),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ] else
                    const Text(
                      "Enter purchase price to see Profit/Loss",
                      style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
                    ),

                  // Last Updated Display
                  if (widget.item.lastUpdated != null) ...[
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 8),
                    Text(
                      "Price Updated: ${widget.item.lastUpdated!.toLocal().toString().split('.')[0]}",
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ],
              ),
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
                  Text("Asset ID: ${widget.item.assetid}",
                      style: const TextStyle(fontSize: 14)),
                  Text("Class ID: ${widget.item.classid}",
                      style: const TextStyle(fontSize: 14)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
