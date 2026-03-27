// Theme Compatibility Layer
// Maps old Italian Brutalism theme to new Flourishing Finances design system
// This allows existing code to work with new design system without immediate refactoring

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// Export new design system
export '../core/theme/app_colors.dart' hide AppColors;
export '../core/theme/app_text_styles.dart';
export '../core/theme/app_constants.dart';
export '../core/theme/app_theme.dart';

import '../core/theme/app_colors.dart' as NewColors;
import '../core/theme/app_constants.dart' as NewConstants;

/// Compatibility layer for AppColors
/// Maps old color names to new design system
class AppColors {
  AppColors._();

  // Map old primary colors to new ones
  static const terracotta = NewColors.AppColors.terracotta; // Keep terracotta for expenses
  static Color get terracottaLight => NewColors.AppColors.terracottaLight;
  static const terracottaDark = NewColors.AppColors.deepForest;

  // Backgrounds - map to new warm backgrounds
  static const parchment = NewColors.AppColors.bgSecondary; // warmSand
  static const parchmentDark = NewColors.AppColors.warmSand;
  static const cream = NewColors.AppColors.cream;

  // Accent - map copper to sage green
  static const copper = NewColors.AppColors.sageGreen;
  static Color get copperLight => NewColors.AppColors.sageGreenLight;

  // Text colors
  static const ink = NewColors.AppColors.textPrimary;
  static const inkLight = NewColors.AppColors.textSecondary;
  static const inkFaded = NewColors.AppColors.textTertiary;

  // Highlights - map gold to amber
  static const gold = NewColors.AppColors.amberHoney;
  static Color get goldLight => NewColors.AppColors.amberLight;

  // Semantic colors
  static const success = NewColors.AppColors.success;
  static const warning = NewColors.AppColors.warning;
  static const error = NewColors.AppColors.error;

  // Category colors - use new palette
  static const categoryGrocery = NewColors.AppColors.sageGreen;
  static const categoryHome = NewColors.AppColors.amberHoney;
  static const categoryTransport = NewColors.AppColors.mistyBlue;
  static const categoryBills = NewColors.AppColors.terracotta;
  static const categoryRestaurant = NewColors.AppColors.amberHoney;
  static const categoryHealth = NewColors.AppColors.softCoral;
  static const categoryEntertainment = NewColors.AppColors.sageGreen;
  static const categoryClothing = NewColors.AppColors.terracotta;

  // Expense type colors (#36)
  static const groupExpenseColor = NewColors.AppColors.mistyBlue;     // Blue for group expenses
  static const personalExpenseColor = NewColors.AppColors.sageGreen;  // Green for personal expenses

  // Dark theme (keep same for now)
  static const darkSurface = Color(0xFF1A1815);
  static const darkCard = Color(0xFF2A2520);
  static const darkCardElevated = Color(0xFF3A352F);
}

/// Compatibility layer for AppTypography
/// Maps to new AppTextStyles
class AppTypography {
  AppTypography._();

  static TextTheme get lightTextTheme => TextTheme(
    displayLarge: GoogleFonts.crimsonPro(
      fontSize: 57,
      fontWeight: FontWeight.w400,
      letterSpacing: -0.25,
      color: NewColors.AppColors.textPrimary,
    ),
    displayMedium: GoogleFonts.crimsonPro(
      fontSize: 45,
      fontWeight: FontWeight.w400,
      color: NewColors.AppColors.textPrimary,
    ),
    displaySmall: GoogleFonts.crimsonPro(
      fontSize: 36,
      fontWeight: FontWeight.w400,
      color: NewColors.AppColors.textPrimary,
    ),
    headlineLarge: GoogleFonts.crimsonPro(
      fontSize: 32,
      fontWeight: FontWeight.w600,
      color: NewColors.AppColors.textPrimary,
    ),
    headlineMedium: GoogleFonts.crimsonPro(
      fontSize: 28,
      fontWeight: FontWeight.w500,
      color: NewColors.AppColors.textPrimary,
    ),
    headlineSmall: GoogleFonts.crimsonPro(
      fontSize: 24,
      fontWeight: FontWeight.w500,
      color: NewColors.AppColors.textPrimary,
    ),
    titleLarge: GoogleFonts.dmSans(
      fontSize: 22,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.15,
      color: NewColors.AppColors.textPrimary,
    ),
    titleMedium: GoogleFonts.dmSans(
      fontSize: 16,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.15,
      color: NewColors.AppColors.textPrimary,
    ),
    titleSmall: GoogleFonts.dmSans(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.1,
      color: NewColors.AppColors.textPrimary,
    ),
    bodyLarge: GoogleFonts.dmSans(
      fontSize: 16,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.15,
      color: NewColors.AppColors.textPrimary,
    ),
    bodyMedium: GoogleFonts.dmSans(
      fontSize: 14,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.25,
      color: NewColors.AppColors.textPrimary,
    ),
    bodySmall: GoogleFonts.dmSans(
      fontSize: 12,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.4,
      color: NewColors.AppColors.textSecondary,
    ),
    labelLarge: GoogleFonts.dmSans(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.5,
      color: NewColors.AppColors.textPrimary,
    ),
    labelMedium: GoogleFonts.dmSans(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.5,
      color: NewColors.AppColors.textSecondary,
    ),
    labelSmall: GoogleFonts.dmSans(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.5,
      color: NewColors.AppColors.textTertiary,
    ),
  );

  static TextTheme get darkTextTheme => lightTextTheme;

  static TextStyle get amountStyle => GoogleFonts.jetBrainsMono(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    color: NewColors.AppColors.textPrimary,
  );

  static TextStyle get amountLarge => GoogleFonts.jetBrainsMono(
    fontSize: 36,
    fontWeight: FontWeight.w700,
    color: NewColors.AppColors.textPrimary,
  );

  static TextStyle get amountSmall => GoogleFonts.jetBrainsMono(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: NewColors.AppColors.textPrimary,
  );
}

/// Compatibility layer for BudgetDesignTokens
/// Maps to new design constants
class BudgetDesignTokens {
  BudgetDesignTokens._();

  // Spacing constants
  static const double heroHeight = 180.0;
  static const double cardBorderWidth = 0; // Remove brutalist borders
  static const double badgeSize = 32.0;
  static const double progressBarHeight = 8.0; // Softer progress bars
  static const double alertBorderWidth = 0; // Remove brutalist borders
  static const double sectionDividerThickness = 1.0;
  static const double barChartBarHeight = 24.0;
  static const double quickStatsHeight = 80.0;

  // Status colors - use new palette
  static const Color healthyBorder = NewColors.AppColors.sageGreen;
  static const Color warningBorder = NewColors.AppColors.amberHoney;
  static const Color dangerBorder = NewColors.AppColors.softCoral; // Use coral for danger

  // Badge colors
  static const Color groupBadgeBg = NewColors.AppColors.deepForest; // Dark green for group
  static const Color personalBadgeBg = NewColors.AppColors.sageGreen;
  static const Color badgeFg = NewColors.AppColors.cream;

  // Typography - map to new styles
  static TextStyle get amountHero => GoogleFonts.crimsonPro(
    fontSize: 42,
    fontWeight: FontWeight.w700,
    color: NewColors.AppColors.cream,
    letterSpacing: -0.5,
  );

  static TextStyle get labelHero => GoogleFonts.dmSans(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.5,
    color: NewColors.AppColors.cream.withValues(alpha: 0.9),
  );

  static TextStyle get sectionLabel => GoogleFonts.dmSans(
    fontSize: 12,
    fontWeight: FontWeight.w700,
    letterSpacing: 2.0,
    color: NewColors.AppColors.textSecondary,
  );

  static TextStyle get cardAmount => GoogleFonts.jetBrainsMono(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    color: NewColors.AppColors.textPrimary,
  );

  static TextStyle get categoryName => GoogleFonts.crimsonPro(
    fontSize: 18,
    fontWeight: FontWeight.w400,
    color: NewColors.AppColors.textPrimary,
  );

  static TextStyle get percentageText => GoogleFonts.jetBrainsMono(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    color: NewColors.AppColors.textPrimary,
  );

  // Shadows - use new organic shadows (const for use in const contexts)
  static const BoxShadow sharpShadow = BoxShadow(
    color: Color(0x1F3D5A3C), // deepForest.withValues(alpha: 0.12)
    blurRadius: 16,
    offset: Offset(0, 4),
  );

  // Border radius - use new soft radius (const for use in const contexts)
  static const double cardRadius = 16.0; // NewConstants.AppRadius.medium
  static const double progressBarRadius = 4.0; // NewConstants.AppRadius.small / 2
  static const double badgeRadius = 16.0;

  // Animation durations
  static const Duration snapDuration = Duration(milliseconds: 150);
  static const Duration expandDuration = Duration(milliseconds: 200);
}

/// Re-export AppTheme with new name
class AppTheme {
  static ThemeData get light => throw UnimplementedError(
    'Use AppTheme.lightTheme from core/theme/app_theme.dart instead'
  );

  static ThemeData get dark => throw UnimplementedError(
    'Use AppTheme.lightTheme from core/theme/app_theme.dart instead'
  );
}
