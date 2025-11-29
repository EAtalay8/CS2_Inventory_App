class InventoryItem {
  final String assetid;
  final String classid;
  final String name;
  final String icon;
  final String type;

  InventoryItem({
    required this.assetid,
    required this.classid,
    required this.name,
    required this.icon,
    required this.type,
  });

  factory InventoryItem.fromJson(Map<String, dynamic> json) {
    return InventoryItem(
      assetid: json["assetid"] ?? "",
      classid: json["classid"] ?? "",
      name: json["name"] ?? "Unknown",
      icon: json["icon"] ?? "",
      type: json["type"] ?? "",
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
