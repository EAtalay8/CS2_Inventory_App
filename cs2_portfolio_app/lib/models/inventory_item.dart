class InventoryItem {
  final String assetid;
  final String classid;
  final String name;
  final String icon;
  final String type;
  final int marketable;
  final double? steamPrice;
  final double? steamPreviousPrice;
  final double? skinportPrice;
  final double? skinportPreviousPrice;
  final double? purchasePrice;
  final String? collection;
  final bool isWatched;
  final DateTime? lastUpdated;

  // Convenience getters for UI compatibility
  double? get price => steamPrice ?? skinportPrice;
  double? get previousPrice => steamPreviousPrice ?? skinportPreviousPrice;

  InventoryItem({
    required this.assetid,
    required this.classid,
    required this.name,
    required this.icon,
    required this.type,
    this.marketable = 1,
    this.steamPrice,
    this.steamPreviousPrice,
    this.skinportPrice,
    this.skinportPreviousPrice,
    this.purchasePrice,
    this.collection,
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
      steamPrice: (json['steam_price'] != null) 
          ? double.tryParse(json['steam_price'].toString()) 
          : null,
      steamPreviousPrice: (json['steam_previous_price'] != null)
          ? double.tryParse(json['steam_previous_price'].toString())
          : null,
      skinportPrice: (json['skinport_price'] != null) 
          ? double.tryParse(json['skinport_price'].toString()) 
          : (json['bp_price'] != null) ? double.tryParse(json['bp_price'].toString()) : null,
      skinportPreviousPrice: (json['skinport_previous_price'] != null)
          ? double.tryParse(json['skinport_previous_price'].toString())
          : (json['bp_previous_price'] != null) ? double.tryParse(json['bp_previous_price'].toString()) : null,
      purchasePrice: (json['purchase_price'] != null)
          ? double.tryParse(json['purchase_price'].toString())
          : null,
      collection: json['collection']?.toString(),
      isWatched: json['is_watched'] == true,
      lastUpdated: json['last_updated'] != null 
          ? DateTime.fromMillisecondsSinceEpoch(json['last_updated']) 
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      "assetid": assetid,
      "classid": classid,
      "name": name,
      "icon": icon,
      "type": type,
      "marketable": marketable,
      "steam_price": steamPrice,
      "steam_previous_price": steamPreviousPrice,
      "skinport_price": skinportPrice,
      "skinport_previous_price": skinportPreviousPrice,
      "purchase_price": purchasePrice,
      "collection": collection,
      "is_watched": isWatched,
      "last_updated": lastUpdated?.millisecondsSinceEpoch,
    };
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

  String get category {
    if (name.startsWith("Sticker |")) return "Stickers";
    if (name.startsWith("Sealed Graffiti |")) return "Graffitis";
    if (type.contains("Music Kit") || name.contains("Music Kit")) return "Music Kits";
    if (type.contains("Agent")) return "Agents";
    if (type.contains("Charm") || name.contains("Charm |")) return "Charms";
    if (name.contains("Case") || name.contains("Capsule") || name.contains("Package") || name.contains("Terminal")) return "Containers & Terminals";
    if (name.contains("Pin |")) return "Pins";
    if (name.contains("Patch |")) return "Patches";
    
    // Assume Weapon if it has a '|' and is not one of the above
    if (name.contains("|")) return "Weapons";
    
    return "Others";
  }

  static const List<String> _knifeNames = [
    'Karambit', 'Bayonet', 'M9 Bayonet', 'Butterfly Knife', 'Flip Knife',
    'Gut Knife', 'Huntsman Knife', 'Falchion Knife', 'Shadow Daggers',
    'Bowie Knife', 'Navaja Knife', 'Stiletto Knife', 'Talon Knife',
    'Ursus Knife', 'Classic Knife', 'Paracord Knife', 'Survival Knife',
    'Nomad Knife', 'Skeleton Knife', 'Kukri Knife',
  ];

  static const List<String> _gloveNames = [
    'Sport Gloves', 'Specialist Gloves', 'Driver Gloves', 'Hand Wraps',
    'Moto Gloves', 'Hydra Gloves', 'Broken Fang Gloves',
  ];

  String get subCategory {
    if (category == "Weapons") {
      String wpnName = name.split(" | ").first.trim();
      if (wpnName.startsWith("StatTrak™ ")) {
        wpnName = wpnName.replaceFirst("StatTrak™ ", "");
      }
      if (wpnName.startsWith("Souvenir ")) {
        wpnName = wpnName.replaceFirst("Souvenir ", "");
      }
      if (wpnName.startsWith("★ ")) {
        wpnName = wpnName.replaceFirst("★ ", "");
      }
      if (wpnName.startsWith("★ StatTrak™ ")) {
        wpnName = wpnName.replaceFirst("★ StatTrak™ ", "");
      }

      // Check if it's a knife
      for (var knife in _knifeNames) {
        if (wpnName == knife) return "Knives";
      }
      // Check if it's gloves
      for (var glove in _gloveNames) {
        if (wpnName == glove) return "Gloves";
      }

      return wpnName;
    }
    if (category == "Containers & Terminals") {
      if (name.contains("Terminal")) return "Terminals";
      return "Containers";
    }
    return category;
  }
}
