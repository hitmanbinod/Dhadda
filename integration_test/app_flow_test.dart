// Phase 7: device integration foundation — full app boot plus the core
// add-expense journey through real UI, store, and on-device persistence.
//
// Run on Android emulator/device:
//   flutter test integration_test -d <device-id>
// Run on Windows desktop (real file-backed Drift via path_provider):
//   flutter test integration_test -d windows
// NOT run by plain `flutter test` (that covers test/ only).
// See docs/TESTING.md for the device matrix and manual procedures.
import 'package:expense/main.dart' as app;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('fresh boot reaches Home with bottom navigation', (tester) async {
    app.main();
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationDestination), findsNWidgets(4));
  });

  testWidgets('add-expense journey persists and shows in History', (
    tester,
  ) async {
    app.main();
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Add expense'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '250');
    await tester.tap(find.text('Food').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'IntegrationTea');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(find.text('Saved'), findsOneWidget);
    await tester.tap(find.byType(NavigationDestination).at(1));
    await tester.pumpAndSettle();
    expect(find.textContaining('IntegrationTea'), findsWidgets);
  });
}
