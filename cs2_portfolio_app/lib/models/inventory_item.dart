class InventoryItem {
  final String assetid;
  final String classid;
  final String name;
  final String icon;
  final String type;
  final double? price;

  InventoryItem({
    required this.assetid,
    required this.classid,
    required this.name,
    required this.icon,
    required this.type,
    this.price,
  });

  factory InventoryItem.fromJson(Map<String, dynamic> json) {
    return InventoryItem(
      assetid: json["assetid"] ?? "",
      classid: json["classid"] ?? "",
      name: json["name"] ?? "Unknown",
      icon: json["icon"] ?? "",
      type: json["type"] ?? "",
      price: (json['price'] != null)
          ? double.tryParse(json['price'].toString())
          : null,
    );
  }

    String get rarity {
    if (type.isEmpty) return "";

    // Örnek: "Mil-Spec Grade Sniper Rifle"
    final parts = type.split(" ");

    if (parts.length >= 2) {
      return "${parts[0]} ${parts[1]}";  // "Mil-Spec Grade"
    }

    return type;
  }

}
