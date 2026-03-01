import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/widget_config_model.dart';
import '../models/widget_data_model.dart';
import 'widget_local_datasource.dart';

/// Implementation of WidgetLocalDataSource using SharedPreferences and home_widget plugin
class WidgetLocalDataSourceImpl implements WidgetLocalDataSource {
  final SharedPreferences sharedPreferences;
  final MethodChannel? platformChannel;

  static const String _widgetDataKey = 'widget_data';
  static const String _widgetConfigKey = 'widget_config';
  static const String _appGroupSuiteName = 'group.com.ecologicaleaving.fin';

  WidgetLocalDataSourceImpl({
    required this.sharedPreferences,
    this.platformChannel,
  });

  @override
  Future<void> saveWidgetData(WidgetDataModel data) async {
    final jsonString = data.toJsonString();

    // Save to Flutter SharedPreferences
    await sharedPreferences.setString(_widgetDataKey, jsonString);

    // iOS: Also save to App Group UserDefaults via MethodChannel
    if (Platform.isIOS && platformChannel != null) {
      try {
        await platformChannel!.invokeMethod('saveWidgetData', {
          'data': jsonString,
        });
      } catch (e) {
        // Log error but don't throw - this is a non-critical operation
        print('Failed to save to iOS App Group: $e');
      }
    }
  }

  @override
  Future<WidgetDataModel?> getCachedWidgetData() async {
    final jsonString = sharedPreferences.getString(_widgetDataKey);
    if (jsonString == null) return null;

    try {
      return WidgetDataModel.fromJsonString(jsonString);
    } catch (e) {
      print('Failed to parse cached widget data: $e');
      return null;
    }
  }

  @override
  Future<void> saveWidgetConfig(WidgetConfigModel config) async {
    final jsonString = config.toJsonString();
    await sharedPreferences.setString(_widgetConfigKey, jsonString);
  }

  @override
  Future<WidgetConfigModel?> getWidgetConfig() async {
    final jsonString = sharedPreferences.getString(_widgetConfigKey);
    if (jsonString == null) return null;

    try {
      return WidgetConfigModel.fromJsonString(jsonString);
    } catch (e) {
      print('Failed to parse widget config: $e');
      return null;
    }
  }

  @override
  Future<void> updateNativeWidget(WidgetDataModel data) async {
    try {
      print('WidgetLocalDataSource: Updating widget with data:');
      print('  - groupAmount: ${data.groupAmount}');
      print('  - personalAmount: ${data.personalAmount}');
      print('  - totalAmount: ${data.totalAmount}');
      print('  - expenseCount: ${data.expenseCount}');
      print('  - month: ${data.month}');

      // Also save JSON for Flutter-side caching
      final jsonString = data.toJsonString();
      print('WidgetLocalDataSource: Saving JSON: $jsonString');

      final result = await HomeWidget.saveWidgetData<String>('widgetDataJson', jsonString);
      print('WidgetLocalDataSource: JSON save result: $result');

      // Save each field individually for native widget access
      print('WidgetLocalDataSource: Saving individual fields...');
      await HomeWidget.saveWidgetData<double>('groupAmount', data.groupAmount);
      await HomeWidget.saveWidgetData<double>('personalAmount', data.personalAmount);
      await HomeWidget.saveWidgetData<double>('totalAmount', data.totalAmount);
      await HomeWidget.saveWidgetData<String>('expenseCount', data.expenseCount.toString());
      await HomeWidget.saveWidgetData<String>('month', data.month);
      await HomeWidget.saveWidgetData<String>('currency', data.currency);
      await HomeWidget.saveWidgetData<bool>('isDarkMode', data.isDarkMode);
      await HomeWidget.saveWidgetData<bool>('hasError', data.hasError);
      await HomeWidget.saveWidgetData<String>(
        'lastUpdated',
        data.lastUpdated.millisecondsSinceEpoch.toString(),
      );
      await HomeWidget.saveWidgetData<String>('groupName', data.groupName ?? '');
      print('WidgetLocalDataSource: All fields saved');

      // Trigger widget update
      print('WidgetLocalDataSource: Triggering widget update...');

      if (Platform.isAndroid && platformChannel != null) {
        // Use direct intent to update widget (bypasses flavor issue)
        print('WidgetLocalDataSource: Using platform channel to update widget');
        await platformChannel!.invokeMethod('updateWidget');
        print('WidgetLocalDataSource: Widget updated via platform channel');
      } else if (Platform.isIOS) {
        final updateResult = await HomeWidget.updateWidget(
          androidName: 'BudgetWidgetProvider',
          iOSName: 'BudgetWidget',
        );
        print('WidgetLocalDataSource: Widget update result: $updateResult');
      } else {
        print('WidgetLocalDataSource: Platform channel not available, widget update skipped');
      }

      print('WidgetLocalDataSource: Widget update complete');
    } catch (e, stackTrace) {
      print('WidgetLocalDataSource: ERROR updating widget: $e');
      print('WidgetLocalDataSource: Stack trace: $stackTrace');
      rethrow;
    }
  }
}
