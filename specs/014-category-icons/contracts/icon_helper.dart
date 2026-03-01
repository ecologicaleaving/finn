// Contract: Icon Helper Service
// Feature: 014-category-icons
// Purpose: Convert between icon names and IconData

import 'package:flutter/material.dart';

/// Helper service for converting Material Icons names to IconData.
///
/// Wraps flutter_iconpicker functionality for type-safe icon resolution.
abstract class IconHelper {
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
  static IconData getIconFromName(String iconName);

  /// Convert IconData to icon name string.
  ///
  /// Example: Icons.shopping_cart -> 'shopping_cart'
  static String getNameFromIcon(IconData icon);

  /// Validate if an icon name is valid Material Icons name.
  ///
  /// Returns true if the icon can be resolved, false otherwise.
  static bool isValidIconName(String iconName);
}
