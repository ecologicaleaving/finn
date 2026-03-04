import 'package:flutter/material.dart';

/// Transaction type for expenses table entries
enum TransactionType {
  /// Regular expense (money out)
  expense('expense', 'Spesa'),

  /// Income entry (money in)
  income('income', 'Entrata');

  const TransactionType(this.value, this.label);

  /// Database value (stored in Supabase)
  final String value;

  /// Human-readable Italian label for UI display
  final String label;

  /// Parse from database string value
  static TransactionType fromString(String value) {
    return TransactionType.values.firstWhere(
      (e) => e.value == value,
      orElse: () => TransactionType.expense,
    );
  }

  /// Whether this is an income transaction
  bool get isIncome => this == TransactionType.income;

  /// Whether this is an expense transaction
  bool get isExpense => this == TransactionType.expense;

  /// Get icon for this type
  IconData get icon {
    switch (this) {
      case TransactionType.expense:
        return Icons.arrow_downward;
      case TransactionType.income:
        return Icons.arrow_upward;
    }
  }

  /// Get color for this type
  Color getColor(ColorScheme colorScheme) {
    switch (this) {
      case TransactionType.expense:
        return colorScheme.error;
      case TransactionType.income:
        return const Color(0xFF2E7D32); // Green 800
    }
  }
}
