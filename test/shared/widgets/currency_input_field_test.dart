import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:family_expense_tracker/shared/widgets/currency_input_field.dart';

void main() {
  Future<List<int?>> pumpField(WidgetTester tester) async {
    final captured = <int?>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CurrencyInputField(onChanged: captured.add),
        ),
      ),
    );
    return captured;
  }

  String fieldText(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField)).controller!.text;

  group('CurrencyInputField decimal separator', () {
    testWidgets('accepts comma as decimal separator (1234,50 -> 1234.50 EUR)',
        (tester) async {
      final captured = await pumpField(tester);

      await tester.enterText(find.byType(TextField), '1234,50');
      await tester.pump();

      expect(fieldText(tester), '1234,50');
      expect(captured.last, 123450);
    });

    testWidgets('accepts dot as decimal separator', (tester) async {
      final captured = await pumpField(tester);

      await tester.enterText(find.byType(TextField), '12.5');
      await tester.pump();

      expect(captured.last, 1250);
    });

    testWidgets('truncates to two decimals with comma', (tester) async {
      final captured = await pumpField(tester);

      await tester.enterText(find.byType(TextField), '1234,567');
      await tester.pump();

      expect(fieldText(tester), '1234,56');
      expect(captured.last, 123456);
    });

    testWidgets('blocks a second separator', (tester) async {
      final captured = await pumpField(tester);

      await tester.enterText(find.byType(TextField), '12,5,');
      await tester.pump();

      expect(fieldText(tester), '12,5');
      expect(captured.last, 1250);
    });
  });

  group('parseCurrencyToCents', () {
    test('parses comma decimal', () {
      expect(parseCurrencyToCents('12,50'), 1250);
    });

    test('parses English thousands format', () {
      expect(parseCurrencyToCents('1,234.56'), 123456);
    });

    test('parses Italian thousands format', () {
      expect(parseCurrencyToCents('1.234,56'), 123456);
    });

    test('parses dot decimal with currency symbol', () {
      expect(parseCurrencyToCents('€ 12.50'), 1250);
    });

    test('returns null for invalid input', () {
      expect(parseCurrencyToCents('abc'), isNull);
    });
  });
}
