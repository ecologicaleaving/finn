import 'package:family_expense_tracker/features/widget/data/datasources/widget_local_datasource_impl.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Issue #64 AC1: widget data of the previous user is removed (Flutter prefs
// and native home_widget keys), the device-level config is kept.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('home_widget'),
            (call) async {
      calls.add(call);
      return true;
    });
  });

  test('clearWidgetData removes widget_data, keeps widget_config', () async {
    SharedPreferences.setMockInitialValues({
      'widget_data': '{"x":1}',
      'widget_config': '{"y":2}',
    });
    final prefs = await SharedPreferences.getInstance();
    final ds = WidgetLocalDataSourceImpl(sharedPreferences: prefs);

    await ds.clearWidgetData();

    expect(prefs.containsKey('widget_data'), isFalse);
    expect(prefs.containsKey('widget_config'), isTrue);

    final saves = calls.where((c) => c.method == 'saveWidgetData').toList();
    final cleared = {
      for (final c in saves)
        (c.arguments as Map)['id'] as String: (c.arguments as Map)['data'],
    };
    expect(cleared.keys, containsAll(['widgetDataJson', 'groupAmount', 'groupName']));
    expect(cleared.values.every((v) => v == null), isTrue);
  });
}
