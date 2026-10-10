import '../models/widget_config_model.dart';
import '../models/widget_data_model.dart';

/// Abstract interface for widget local storage operations
abstract class WidgetLocalDataSource {
  /// Save widget data to SharedPreferences
  Future<void> saveWidgetData(WidgetDataModel data);

  /// Load cached widget data
  Future<WidgetDataModel?> getCachedWidgetData();

  /// Save widget configuration
  Future<void> saveWidgetConfig(WidgetConfigModel config);

  /// Load widget configuration
  Future<WidgetConfigModel?> getWidgetConfig();

  /// Update native widget via home_widget plugin
  Future<void> updateNativeWidget(WidgetDataModel data);

  /// Remove the widget data of the previous user (logout / account switch).
  /// Keeps the device-level widget configuration.
  Future<void> clearWidgetData();
}
