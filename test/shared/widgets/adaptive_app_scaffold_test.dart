import 'package:family_expense_tracker/shared/widgets/adaptive_app_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final width in [390.0, 1440.0]) {
    testWidgets('navigation and add remain usable at width $width',
        (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      int? selected;
      var added = false;
      await tester.pumpWidget(MaterialApp(
        home: AdaptiveAppScaffold(
          body: const Center(child: Text('Dati Finn')),
          destinations: const [
            NavigationDestination(
                icon: Icon(Icons.dashboard), label: 'Dashboard'),
            NavigationDestination(icon: Icon(Icons.receipt), label: 'Spese'),
            NavigationDestination(
                icon: Icon(Icons.settings), label: 'Impostazioni'),
          ],
          selectedIndex: 0,
          onDestinationSelected: (index) => selected = index,
          onAdd: () => added = true,
        ),
      ));
      expect(find.text('Dati Finn'), findsOneWidget);
      expect(find.byType(width >= 900 ? NavigationRail : NavigationBar),
          findsOneWidget);
      await tester.tap(find.text('Spese'));
      expect(selected, 1);
      await tester.tap(find.byType(FloatingActionButton));
      expect(added, isTrue);
      expect(tester.takeException(), isNull);
    });
  }
}
