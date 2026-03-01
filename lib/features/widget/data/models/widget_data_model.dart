import 'dart:convert';
import '../../domain/entities/widget_data_entity.dart';

/// Serializable version of WidgetDataEntity for persistence and API communication
/// Shows group expenses, personal expenses, and total separately
class WidgetDataModel extends WidgetDataEntity {
  const WidgetDataModel({
    required double groupAmount,
    required double personalAmount,
    required double totalAmount,
    required int expenseCount,
    required String month,
    String currency = '€',
    required bool isDarkMode,
    bool hasError = false,
    required DateTime lastUpdated,
    required String groupId,
    String? groupName,
  }) : super(
          groupAmount: groupAmount,
          personalAmount: personalAmount,
          totalAmount: totalAmount,
          expenseCount: expenseCount,
          month: month,
          currency: currency,
          isDarkMode: isDarkMode,
          hasError: hasError,
          lastUpdated: lastUpdated,
          groupId: groupId,
          groupName: groupName,
        );

  /// Create model from entity
  factory WidgetDataModel.fromEntity(WidgetDataEntity entity) {
    return WidgetDataModel(
      groupAmount: entity.groupAmount,
      personalAmount: entity.personalAmount,
      totalAmount: entity.totalAmount,
      expenseCount: entity.expenseCount,
      month: entity.month,
      currency: entity.currency,
      isDarkMode: entity.isDarkMode,
      hasError: entity.hasError,
      lastUpdated: entity.lastUpdated,
      groupId: entity.groupId,
      groupName: entity.groupName,
    );
  }

  /// Create model from JSON
  factory WidgetDataModel.fromJson(Map<String, dynamic> json) {
    return WidgetDataModel(
      groupAmount: (json['groupAmount'] as num).toDouble(),
      personalAmount: (json['personalAmount'] as num).toDouble(),
      totalAmount: (json['totalAmount'] as num).toDouble(),
      expenseCount: json['expenseCount'] as int,
      month: json['month'] as String,
      currency: (json['currency'] as String?) ?? '€',
      isDarkMode: json['isDarkMode'] as bool,
      hasError: (json['hasError'] as bool?) ?? false,
      lastUpdated: DateTime.parse(json['lastUpdated'] as String),
      groupId: json['groupId'] as String,
      groupName: json['groupName'] as String?,
    );
  }

  /// Convert model to JSON
  Map<String, dynamic> toJson() {
    return {
      'groupAmount': groupAmount,
      'personalAmount': personalAmount,
      'totalAmount': totalAmount,
      'expenseCount': expenseCount,
      'month': month,
      'currency': currency,
      'isDarkMode': isDarkMode,
      'hasError': hasError,
      'lastUpdated': lastUpdated.toIso8601String(),
      'groupId': groupId,
      'groupName': groupName,
    };
  }

  /// Convert to JSON string
  String toJsonString() => jsonEncode(toJson());

  /// Create model from JSON string
  factory WidgetDataModel.fromJsonString(String jsonString) {
    return WidgetDataModel.fromJson(
      jsonDecode(jsonString) as Map<String, dynamic>,
    );
  }
}
