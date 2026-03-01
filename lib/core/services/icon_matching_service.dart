// Icon Matching Service
// Feature: 014-category-icons
// Purpose: Deterministic icon matching for Italian category names

import 'package:flutter/material.dart';
import 'icon_helper.dart';

/// Service for matching Italian category names to Material Icons.
///
/// Provides deterministic icon selection based on Italian keywords.
/// Used for migration backfill and fallback display logic.
class IconMatchingService {
  /// Get default icon name for a category based on Italian keyword matching.
  ///
  /// Returns Material Icons name (e.g., 'shopping_cart', 'restaurant').
  /// Falls back to 'category' for unrecognized names.
  ///
  /// Example:
  /// ```dart
  /// getDefaultIconNameForCategory("Spesa") // Returns "shopping_cart"
  /// getDefaultIconNameForCategory("Benzina") // Returns "local_gas_station"
  /// getDefaultIconNameForCategory("Unknown") // Returns "category"
  /// ```
  static String getDefaultIconNameForCategory(String categoryName) {
    final name = categoryName.toLowerCase();

    // Shopping & Food
    if (name.contains('spesa') || name.contains('alimentari')) {
      return 'shopping_cart';
    }
    if (name.contains('ristorante') || name.contains('cibo')) {
      return 'restaurant';
    }

    // Transportation
    if (name.contains('benzina') || name.contains('carburante')) {
      return 'local_gas_station';
    }
    if (name.contains('trasporti') || name.contains('taxi')) {
      return 'directions_bus';
    }

    // Home & Utilities
    if (name.contains('casa') || name.contains('affitto')) {
      return 'home';
    }
    if (name.contains('bollette') || name.contains('utenze')) {
      return 'receipt_long';
    }

    // Health & Wellness
    if (name.contains('salute') || name.contains('farmacia')) {
      return 'medical_services';
    }
    if (name.contains('sport') || name.contains('palestra')) {
      return 'fitness_center';
    }

    // Entertainment
    if (name.contains('svago') || name.contains('divertimento')) {
      return 'celebration';
    }

    // Shopping
    if (name.contains('abbigliamento') || name.contains('vestiti')) {
      return 'checkroom';
    }
    if (name.contains('tecnologia') || name.contains('elettronica')) {
      return 'devices';
    }

    // Education & Work
    if (name.contains('istruzione') || name.contains('scuola')) {
      return 'school';
    }

    // Travel & Leisure
    if (name.contains('viaggio') || name.contains('vacanza')) {
      return 'flight';
    }

    // Gifts & Special
    if (name.contains('regalo')) {
      return 'card_giftcard';
    }
    if (name.contains('animali') || name.contains('pet')) {
      return 'pets';
    }

    // Default fallback
    return 'category';
  }

  /// Get IconData for a category based on stored icon name or name matching.
  ///
  /// This method mirrors the existing CategoryDropdown._getCategoryIcon() logic.
  static IconData getDefaultIconForCategory(String categoryName) {
    final iconName = getDefaultIconNameForCategory(categoryName);
    return IconHelper.getIconFromName(iconName);
  }

  /// Italian-to-English keyword translation map for icon search.
  ///
  /// Used by icon picker to enable bilingual search.
  /// Maps Italian keywords to Material Icons names.
  static const Map<String, String> italianToEnglishIconKeywords = {
    // Shopping & Food
    'spesa': 'shopping_cart',
    'alimentari': 'local_grocery_store',
    'cibo': 'restaurant',
    'ristorante': 'restaurant',

    // Transportation
    'benzina': 'local_gas_station',
    'carburante': 'local_gas_station',
    'trasporti': 'directions_bus',
    'taxi': 'local_taxi',
    'macchina': 'directions_car',

    // Home & Utilities
    'casa': 'home',
    'affitto': 'apartment',
    'bollette': 'receipt_long',
    'utenze': 'receipt_long',

    // Health & Wellness
    'salute': 'medical_services',
    'farmacia': 'local_pharmacy',
    'sport': 'fitness_center',
    'palestra': 'fitness_center',

    // Entertainment
    'svago': 'celebration',
    'divertimento': 'celebration',

    // Shopping
    'abbigliamento': 'checkroom',
    'vestiti': 'checkroom',
    'tecnologia': 'devices',
    'elettronica': 'devices',

    // Education & Work
    'istruzione': 'school',
    'scuola': 'school',

    // Travel & Leisure
    'viaggio': 'flight',
    'vacanza': 'beach_access',

    // Gifts & Special
    'regalo': 'card_giftcard',
    'animali': 'pets',
    'pet': 'pets',
  };
}
