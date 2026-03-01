// Icon Helper Service
// Feature: 014-category-icons
// Purpose: Convert between icon names and IconData

import 'package:flutter/material.dart';

/// Helper service for converting Material Icons names to IconData.
///
/// Uses a static map of Material Icons for reliable icon resolution.
class IconHelper {
  /// Convert icon name string to IconData.
  ///
  /// Example: 'shopping_cart' -> Icons.shopping_cart
  /// Falls back to Icons.category for invalid names.
  ///
  /// Usage:
  /// ```dart
  /// final icon = IconHelper.getIconFromName('shopping_cart');
  /// Icon(icon) // Displays shopping cart icon
  /// ```
  static IconData getIconFromName(String iconName) {
    return _iconMap[iconName] ?? Icons.category;
  }

  /// Convert IconData to icon name string.
  ///
  /// Example: Icons.shopping_cart -> 'shopping_cart'
  static String getNameFromIcon(IconData icon) {
    // Find the icon name by matching codePoint
    for (final entry in _iconMap.entries) {
      if (entry.value.codePoint == icon.codePoint) {
        return entry.key;
      }
    }
    return 'category';
  }

  /// Validate if an icon name is valid Material Icons name.
  ///
  /// Returns true if the icon can be resolved, false otherwise.
  static bool isValidIconName(String iconName) {
    return _iconMap.containsKey(iconName);
  }

  /// Map of common Material Icons used in expense categories
  static final Map<String, IconData> _iconMap = {
    // Shopping & Food
    'shopping_cart': Icons.shopping_cart,
    'local_grocery_store': Icons.local_grocery_store,
    'restaurant': Icons.restaurant,
    'local_dining': Icons.local_dining,
    'fastfood': Icons.fastfood,
    'local_cafe': Icons.local_cafe,
    'local_pizza': Icons.local_pizza,

    // Transportation
    'local_gas_station': Icons.local_gas_station,
    'directions_car': Icons.directions_car,
    'directions_bus': Icons.directions_bus,
    'local_taxi': Icons.local_taxi,
    'directions_bike': Icons.directions_bike,
    'train': Icons.train,
    'flight': Icons.flight,
    'directions_subway': Icons.directions_subway,

    // Home & Utilities
    'home': Icons.home,
    'apartment': Icons.apartment,
    'house': Icons.house,
    'receipt_long': Icons.receipt_long,
    'receipt': Icons.receipt,
    'bolt': Icons.bolt,
    'water_drop': Icons.water_drop,
    'wifi': Icons.wifi,

    // Health & Wellness
    'medical_services': Icons.medical_services,
    'local_pharmacy': Icons.local_pharmacy,
    'local_hospital': Icons.local_hospital,
    'fitness_center': Icons.fitness_center,
    'sports_gymnastics': Icons.sports_gymnastics,
    'spa': Icons.spa,

    // Entertainment
    'celebration': Icons.celebration,
    'movie': Icons.movie,
    'theaters': Icons.theaters,
    'sports_soccer': Icons.sports_soccer,
    'music_note': Icons.music_note,
    'videogame_asset': Icons.videogame_asset,

    // Shopping
    'checkroom': Icons.checkroom,
    'shopping_bag': Icons.shopping_bag,
    'local_mall': Icons.local_mall,

    // Technology
    'devices': Icons.devices,
    'phone_android': Icons.phone_android,
    'computer': Icons.computer,
    'tablet': Icons.tablet,
    'laptop': Icons.laptop,

    // Education & Work
    'school': Icons.school,
    'work': Icons.work,
    'business': Icons.business,
    'book': Icons.book,

    // Travel & Leisure
    'beach_access': Icons.beach_access,
    'hotel': Icons.hotel,
    'luggage': Icons.luggage,

    // Gifts & Special
    'card_giftcard': Icons.card_giftcard,
    'redeem': Icons.redeem,
    'pets': Icons.pets,
    'favorite': Icons.favorite,

    // Finance
    'payments': Icons.payments,
    'account_balance': Icons.account_balance,
    'credit_card': Icons.credit_card,
    'savings': Icons.savings,
    'attach_money': Icons.attach_money,

    // Default
    'category': Icons.category,
  };

  /// Get all available icons (for picker)
  static Map<String, IconData> getAllIcons() => Map.from(_iconMap);
}
