import 'package:flutter/foundation.dart';

/// Represents a breakdown of expenses by category.
@immutable
class CategoryBreakdown {
  const CategoryBreakdown({
    required this.category,
    required this.total,
    required this.count,
    required this.percentage,
  });

  final String category;
  final double total;
  final int count;
  final double percentage;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CategoryBreakdown &&
          runtimeType == other.runtimeType &&
          category == other.category &&
          total == other.total &&
          count == other.count &&
          percentage == other.percentage;

  @override
  int get hashCode =>
      category.hashCode ^ total.hashCode ^ count.hashCode ^ percentage.hashCode;

  @override
  String toString() =>
      'CategoryBreakdown(category: $category, total: $total, count: $count, percentage: $percentage)';
}

/// Represents a breakdown of expenses by group member.
@immutable
class MemberBreakdown {
  const MemberBreakdown({
    required this.userId,
    required this.displayName,
    required this.total,
    required this.count,
    required this.percentage,
  });

  final String userId;
  final String displayName;
  final double total;
  final int count;
  final double percentage;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MemberBreakdown &&
          runtimeType == other.runtimeType &&
          userId == other.userId &&
          displayName == other.displayName &&
          total == other.total &&
          count == other.count &&
          percentage == other.percentage;

  @override
  int get hashCode =>
      userId.hashCode ^
      displayName.hashCode ^
      total.hashCode ^
      count.hashCode ^
      percentage.hashCode;

  @override
  String toString() =>
      'MemberBreakdown(userId: $userId, displayName: $displayName, total: $total, count: $count, percentage: $percentage)';
}

/// Represents a single data point in the expense trend.
@immutable
class TrendDataPoint {
  const TrendDataPoint({
    required this.date,
    required this.total,
    required this.count,
  });

  final DateTime date;
  final double total;
  final int count;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TrendDataPoint &&
          runtimeType == other.runtimeType &&
          date == other.date &&
          total == other.total &&
          count == other.count;

  @override
  int get hashCode => date.hashCode ^ total.hashCode ^ count.hashCode;

  @override
  String toString() =>
      'TrendDataPoint(date: $date, total: $total, count: $count)';
}

/// Time period for dashboard statistics.
enum DashboardPeriod {
  week,
  month,
  year;

  String get label {
    switch (this) {
      case DashboardPeriod.week:
        return 'Settimana';
      case DashboardPeriod.month:
        return 'Mese';
      case DashboardPeriod.year:
        return 'Anno';
    }
  }

  String get apiValue {
    switch (this) {
      case DashboardPeriod.week:
        return 'week';
      case DashboardPeriod.month:
        return 'month';
      case DashboardPeriod.year:
        return 'year';
    }
  }
}

/// Dashboard statistics entity containing all aggregated data.
@immutable
class DashboardStats {
  const DashboardStats({
    required this.period,
    required this.startDate,
    required this.endDate,
    required this.totalAmount,
    required this.expenseCount,
    required this.averageExpense,
    required this.byCategory,
    required this.byMember,
    required this.trend,
    this.totalIncome = 0,
    this.incomeCount = 0,
  });

  final DashboardPeriod period;
  final DateTime startDate;
  final DateTime endDate;
  /// Total expenses amount (money out)
  final double totalAmount;
  final int expenseCount;
  final double averageExpense;
  final List<CategoryBreakdown> byCategory;
  final List<MemberBreakdown> byMember;
  final List<TrendDataPoint> trend;
  /// Total income amount (money in)
  final double totalIncome;
  final int incomeCount;

  /// Net balance (income - expenses)
  double get netBalance => totalIncome - totalAmount;

  /// Creates an empty dashboard stats object.
  factory DashboardStats.empty(DashboardPeriod period) {
    final now = DateTime.now();
    final startDate = _calculateStartDate(period, now);

    return DashboardStats(
      period: period,
      startDate: startDate,
      endDate: now,
      totalAmount: 0,
      expenseCount: 0,
      averageExpense: 0,
      byCategory: const [],
      byMember: const [],
      trend: const [],
      totalIncome: 0,
      incomeCount: 0,
    );
  }

  static DateTime _calculateStartDate(DashboardPeriod period, DateTime endDate) {
    switch (period) {
      case DashboardPeriod.week:
        return endDate.subtract(const Duration(days: 7));
      case DashboardPeriod.month:
        return DateTime(endDate.year, endDate.month - 1, endDate.day);
      case DashboardPeriod.year:
        return DateTime(endDate.year - 1, endDate.month, endDate.day);
    }
  }

  /// Returns true if there are no expenses in the period.
  bool get isEmpty => expenseCount == 0;

  /// Returns the top category by spending amount.
  CategoryBreakdown? get topCategory =>
      byCategory.isNotEmpty ? byCategory.first : null;

  /// Returns the top spender by total amount.
  MemberBreakdown? get topSpender =>
      byMember.isNotEmpty ? byMember.first : null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DashboardStats &&
          runtimeType == other.runtimeType &&
          period == other.period &&
          startDate == other.startDate &&
          endDate == other.endDate &&
          totalAmount == other.totalAmount &&
          expenseCount == other.expenseCount &&
          averageExpense == other.averageExpense &&
          listEquals(byCategory, other.byCategory) &&
          listEquals(byMember, other.byMember) &&
          listEquals(trend, other.trend) &&
          totalIncome == other.totalIncome &&
          incomeCount == other.incomeCount;

  @override
  int get hashCode =>
      period.hashCode ^
      startDate.hashCode ^
      endDate.hashCode ^
      totalAmount.hashCode ^
      expenseCount.hashCode ^
      averageExpense.hashCode ^
      byCategory.hashCode ^
      byMember.hashCode ^
      trend.hashCode;

  @override
  String toString() =>
      'DashboardStats(period: $period, totalAmount: $totalAmount, expenseCount: $expenseCount)';
}
