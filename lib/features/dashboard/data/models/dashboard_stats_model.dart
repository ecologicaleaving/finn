import '../../domain/entities/dashboard_stats_entity.dart';

/// Model class for category breakdown with JSON serialization.
class CategoryBreakdownModel extends CategoryBreakdown {
  const CategoryBreakdownModel({
    required super.category,
    required super.total,
    required super.count,
    required super.percentage,
  });

  factory CategoryBreakdownModel.fromJson(Map<String, dynamic> json) {
    return CategoryBreakdownModel(
      category: json['category'] as String? ?? 'altro',
      total: (json['total'] as num?)?.toDouble() ?? 0.0,
      count: json['count'] as int? ?? 0,
      percentage: (json['percentage'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'category': category,
      'total': total,
      'count': count,
      'percentage': percentage,
    };
  }

  factory CategoryBreakdownModel.fromEntity(CategoryBreakdown entity) {
    return CategoryBreakdownModel(
      category: entity.category,
      total: entity.total,
      count: entity.count,
      percentage: entity.percentage,
    );
  }
}

/// Model class for member breakdown with JSON serialization.
class MemberBreakdownModel extends MemberBreakdown {
  const MemberBreakdownModel({
    required super.userId,
    required super.displayName,
    required super.total,
    required super.count,
    required super.percentage,
  });

  factory MemberBreakdownModel.fromJson(Map<String, dynamic> json) {
    return MemberBreakdownModel(
      userId: json['user_id'] as String? ?? '',
      displayName: json['display_name'] as String? ?? 'Utente',
      total: (json['total'] as num?)?.toDouble() ?? 0.0,
      count: json['count'] as int? ?? 0,
      percentage: (json['percentage'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'display_name': displayName,
      'total': total,
      'count': count,
      'percentage': percentage,
    };
  }

  factory MemberBreakdownModel.fromEntity(MemberBreakdown entity) {
    return MemberBreakdownModel(
      userId: entity.userId,
      displayName: entity.displayName,
      total: entity.total,
      count: entity.count,
      percentage: entity.percentage,
    );
  }
}

/// Model class for trend data point with JSON serialization.
class TrendDataPointModel extends TrendDataPoint {
  const TrendDataPointModel({
    required super.date,
    required super.total,
    required super.count,
  });

  factory TrendDataPointModel.fromJson(Map<String, dynamic> json) {
    return TrendDataPointModel(
      date: DateTime.parse(json['date'] as String),
      total: (json['total'] as num?)?.toDouble() ?? 0.0,
      count: json['count'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'date': date.toIso8601String().split('T')[0],
      'total': total,
      'count': count,
    };
  }

  factory TrendDataPointModel.fromEntity(TrendDataPoint entity) {
    return TrendDataPointModel(
      date: entity.date,
      total: entity.total,
      count: entity.count,
    );
  }
}

/// Model class for dashboard stats with JSON serialization.
class DashboardStatsModel extends DashboardStats {
  const DashboardStatsModel({
    required super.period,
    required super.startDate,
    required super.endDate,
    required super.totalAmount,
    required super.expenseCount,
    required super.averageExpense,
    required super.byCategory,
    required super.byMember,
    required super.trend,
    super.totalIncome = 0,
    super.incomeCount = 0,
  });

  factory DashboardStatsModel.fromJson(
    Map<String, dynamic> json,
    DashboardPeriod period,
  ) {
    return DashboardStatsModel(
      period: period,
      startDate: DateTime.parse(json['start_date'] as String),
      endDate: DateTime.parse(json['end_date'] as String),
      totalAmount: (json['total_amount'] as num?)?.toDouble() ?? 0.0,
      expenseCount: json['expense_count'] as int? ?? 0,
      averageExpense: (json['average_expense'] as num?)?.toDouble() ?? 0.0,
      byCategory: (json['by_category'] as List<dynamic>?)
              ?.map((e) =>
                  CategoryBreakdownModel.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      byMember: (json['by_member'] as List<dynamic>?)
              ?.map((e) =>
                  MemberBreakdownModel.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      trend: (json['trend'] as List<dynamic>?)
              ?.map((e) =>
                  TrendDataPointModel.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'period': period.apiValue,
      'start_date': startDate.toIso8601String().split('T')[0],
      'end_date': endDate.toIso8601String().split('T')[0],
      'total_amount': totalAmount,
      'expense_count': expenseCount,
      'average_expense': averageExpense,
      'by_category': byCategory
          .map((e) => CategoryBreakdownModel.fromEntity(e).toJson())
          .toList(),
      'by_member': byMember
          .map((e) => MemberBreakdownModel.fromEntity(e).toJson())
          .toList(),
      'trend': trend
          .map((e) => TrendDataPointModel.fromEntity(e).toJson())
          .toList(),
    };
  }

  factory DashboardStatsModel.fromEntity(DashboardStats entity) {
    return DashboardStatsModel(
      period: entity.period,
      startDate: entity.startDate,
      endDate: entity.endDate,
      totalAmount: entity.totalAmount,
      expenseCount: entity.expenseCount,
      averageExpense: entity.averageExpense,
      byCategory: entity.byCategory,
      byMember: entity.byMember,
      trend: entity.trend,
    );
  }
}
