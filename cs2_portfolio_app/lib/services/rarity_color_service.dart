import 'package:flutter/material.dart';

Color getRarityColor(String rarity) {
  rarity = rarity.toLowerCase();

  if (rarity.contains("consumer")) {
    return const Color(0xFFB0C3D9);
  } else if (rarity.contains("industrial")) {
    return const Color(0xFF5E98D9);
  } else if (rarity.contains("mil-spec")) {
    return const Color(0xFF4B69FF);
  } else if (rarity.contains("restricted")) {
    return const Color(0xFF8847FF);
  } else if (rarity.contains("classified")) {
    return const Color(0xFFD32CE6);
  } else if (rarity.contains("covert")) {
    return const Color(0xFFEB4B4B);
  } else if (rarity.contains("exceed") || rarity.contains("rare")) {
    return const Color(0xFFFFD700);
  }

  return Colors.grey;
}
