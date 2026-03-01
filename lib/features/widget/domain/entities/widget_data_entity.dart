import 'package:equatable/equatable.dart';
import 'package:intl/intl.dart';

/// Entity representing the current state of the widget displayed on the home screen
/// Shows group expenses, personal expenses, and total separately
class WidgetDataEntity extends Equatable {
  final double groupAmount;
  final double personalAmount;
  final double totalAmount;
  final int expenseCount;
  final String month;
  final String currency;
  final bool isDarkMode;
  final bool hasError;
  final DateTime lastUpdated;
  final String groupId;
  final String? groupName;

  const WidgetDataEntity({
    required this.groupAmount,
    required this.personalAmount,
    required this.totalAmount,
    required this.expenseCount,
    required this.month,
    this.currency = '€',
    required this.isDarkMode,
    this.hasError = false,
    required this.lastUpdated,
    required this.groupId,
    this.groupName,
  });

  /// Format total amount with currency (e.g., "€342,50")
  String get formattedTotal {
    final formatter = NumberFormat.currency(
      symbol: currency,
      decimalDigits: 2,
      locale: 'it_IT',
    );
    return formatter.format(totalAmount);
  }

  /// Display text for widget: "€342,50 • 12 spese"
  String get displayText => '$formattedTotal • $expenseCount spese';

  /// Is data stale (last updated more than 24 hours ago)
  bool get isStale => DateTime.now().difference(lastUpdated).inHours > 24;

  /// Human-readable freshness indicator (e.g., "Aggiornato 2 ore fa")
  String get freshnessText {
    final diff = DateTime.now().difference(lastUpdated);
    if (diff.inMinutes < 1) return 'Aggiornato ora';
    if (diff.inMinutes < 60) return 'Aggiornato ${diff.inMinutes} minuti fa';
    if (diff.inHours < 24) return 'Aggiornato ${diff.inHours} ore fa';
    return 'Aggiornato ${diff.inDays} giorni fa';
  }

  @override
  List<Object?> get props => [
        groupAmount,
        personalAmount,
        totalAmount,
        expenseCount,
        month,
        currency,
        isDarkMode,
        hasError,
        lastUpdated,
        groupId,
        groupName,
      ];
}
