import 'package:flutter/material.dart';

/// App color palette - "Flourishing Finances" design system
///
/// An earth-toned, organic color palette inspired by natural growth
/// and financial prosperity. Warm, professional, and optimistic.
class AppColors {
  // Primary Palette - Earth & Growth
  /// Main brand color - growth, balance, prosperity
  static const Color sageGreen = Color(0xFF7A9B76);

  /// Primary text and important elements - stability, trust
  static const Color deepForest = Color(0xFF3D5A3C);

  /// Expenses and primary accents - professional, calm
  static const Color terracotta = Color(0xFFA8BFC4); // Misty Blue

  /// Secondary background - soft, warm
  static const Color warmSand = Color(0xFFF5EFE7);

  /// Primary background - replaces pure white
  static const Color cream = Color(0xFFFFFBF5);

  // Accents
  /// Goals, achievements, highlights
  static const Color amberHoney = Color(0xFFE8B44F);

  /// Soft error state
  static const Color softCoral = Color(0xFFE88D7A);

  /// Info states, calm notifications
  static const Color mistyBlue = Color(0xFFA8BFC4);

  /// Primary text color
  static const Color charcoal = Color(0xFF2C3333);

  // Semantic Colors
  static const Color success = sageGreen;
  static const Color warning = amberHoney;
  static const Color error = softCoral;
  static const Color info = mistyBlue;

  // Expense Type Colors
  /// Personal expenses color (green tones)
  static const Color personalExpenseColor = sageGreen;
  /// Group expenses color (blue tones)
  static const Color groupExpenseColor = mistyBlue;

  // Backgrounds
  static const Color bgPrimary = cream;
  static const Color bgSecondary = warmSand;
  static const Color bgCard = Colors.white;

  // Text Colors
  static const Color textPrimary = charcoal;
  static const Color textSecondary = Color(0xFF5A6363);
  static const Color textTertiary = Color(0xFF8A9494);

  // Utility Colors with Opacity
  static Color get sageGreenLight => sageGreen.withValues(alpha: 0.15);
  static Color get terracottaLight => terracotta.withValues(alpha: 0.15);
  static Color get amberLight => amberHoney.withValues(alpha: 0.15);

  // Shadow Colors
  static Color get shadowLight => deepForest.withValues(alpha: 0.08);
  static Color get shadowMedium => deepForest.withValues(alpha: 0.12);
  static Color get shadowDark => deepForest.withValues(alpha: 0.16);
}
