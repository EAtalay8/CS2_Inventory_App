class InventoryItem {
  final String assetid;
  final String classid;
  final String name;
  final String icon;
  final String type;
  final int marketable;
  final double? price;
  final double? previousPrice;
  final double? purchasePrice;
  final bool isWatched;
  final DateTime? lastUpdated;

  InventoryItem({
    required this.assetid,
    required this.classid,
    required this.name,
    required this.icon,
    required this.type,
    this.marketable = 1,
    this.price,
    this.previousPrice,
    this.purchasePrice,
    this.isWatched = false,
    this.lastUpdated,
  });

  factory InventoryItem.fromJson(Map<String, dynamic> json) {
    return InventoryItem(
      assetid: json["assetid"]?.toString() ?? "",
      classid: json["classid"]?.toString() ?? "",
      name: json["name"] ?? "Unknown",
      icon: json["icon"] ?? "",
      type: json["type"] ?? "",
      marketable: (json['marketable'] != null) 
          ? int.tryParse(json['marketable'].toString()) ?? 1 
          : 1,
      price: (json['price'] != null) 
          ? double.tryParse(json['price'].toString()) 
          : null,
      previousPrice: (json['previous_price'] != null)
          ? double.tryParse(json['previous_price'].toString())
          : null,
      purchasePrice: (json['purchase_price'] != null)
          ? double.tryParse(json['purchase_price'].toString())
          : null,
      isWatched: json['is_watched'] == true,
      lastUpdated: json['last_updated'] != null 
          ? DateTime.fromMillisecondsSinceEpoch(json['last_updated']) 
          : null,
    );
  }

  String get rarity {
    if (type.isEmpty) return "";

    // Example: "Mil-Spec Grade Sniper Rifle"
    final parts = type.split(" ");

    if (parts.length >= 2) {
      return "${parts[0]} ${parts[1]}";  // "Mil-Spec Grade"
    }

    return type;
  }
}
