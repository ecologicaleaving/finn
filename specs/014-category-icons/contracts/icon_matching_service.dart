// Contract: Icon Matching Service
// Feature: 014-category-icons
// Purpose: Deterministic icon matching for Italian category names

import 'package:flutter/material.dart';

/// Service for matching Italian category names to Material Icons.
///
/// Provides deterministic icon selection based on Italian keywords.
/// Used for migration backfill and fallback display logic.
abstract class IconMatchingService {
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
  static String getDefaultIconNameForCategory(String categoryName);

  /// Get IconData for a category based on stored icon name or name matching.
  ///
  /// This method mirrors the existing CategoryDropdown._getCategoryIcon() logic.
  static IconData getDefaultIconForCategory(String categoryName);

  /// Italian-to-English keyword translation map for icon search.
  ///
  /// Used by icon picker to enable bilingual search.
  /// Maps Italian keywords to Material Icons names.
  static const Map<String, String> italianToEnglishIconKeywords = {
    'spesa': 'shopping_cart',
    'alimentari': 'local_grocery_store',
    'benzina': 'local_gas_station',
    'casa': 'home',
    // ... (full map in implementation)
  };
}
