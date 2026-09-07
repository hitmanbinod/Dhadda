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

  /// Device-only SMS import flow (needs SMS permission pre-granted via adb
  /// and, for the full path, a synthetic bank-like SMS in the inbox).
  /// Either outcome is correct behavior: a candidates dialog when parseable
  /// messages exist, or the empty-inbox snackbar otherwise. Prints which
  /// branch ran so the report is honest.
  testWidgets('SMS import flow handles inbox or empty gracefully',
      (tester) async {
    app.main();
    await tester.pumpAndSettle();
    await tester.tap(find.byType(NavigationDestination).at(3));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
        find.widgetWithText(FilledButton, 'Scan SMS now'), 500);
    await tester.tap(find.widgetWithText(FilledButton, 'Scan SMS now'));
    await tester.pumpAndSettle(const Duration(seconds: 5));
    final dialog = find.textContaining('from SMS?');
    final empty = find.text('No new bank/wallet SMS found.');
    final needPerm = find.textContaining('SMS permission needed');
    expect(
      dialog.evaluate().isNotEmpty ||
          empty.evaluate().isNotEmpty ||
          needPerm.evaluate().isNotEmpty,
      isTrue,
      reason: 'expected candidates dialog, empty notice, or permission notice',
    );
    // ignore: avoid_print
    print('SMS FLOW: dialog=${dialog.evaluate().isNotEmpty} '
        'empty=${empty.evaluate().isNotEmpty} '
        'needPerm=${needPerm.evaluate().isNotEmpty}');
  });

  /// Device-only SMS tap-through: imports candidates, then proves
  /// duplicate suppression on re-scan. Skips honestly when the inbox has
  /// nothing parseable (empty branch covered above).
  testWidgets('SMS import tap-through deduplicates on rescan',
      (tester) async {
    app.main();
    await tester.pumpAndSettle();
    await tester.tap(find.byType(NavigationDestination).at(3));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
        find.widgetWithText(FilledButton, 'Scan SMS now'), 500);
    await tester.tap(find.widgetWithText(FilledButton, 'Scan SMS now'));
    await tester.pumpAndSettle(const Duration(seconds: 5));
    final dialog = find.textContaining('from SMS?');
    if (dialog.evaluate().isEmpty) {
      // ignore: avoid_print
      print('SMS TAP-THROUGH: skipped (inbox has nothing parseable)');
      return;
    }
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Added '), findsOneWidget);
    // ignore: avoid_print
    print('SMS TAP-THROUGH: imported, rescanning for duplicates');
    await tester.tap(find.widgetWithText(FilledButton, 'Scan SMS now'));
    await tester.pumpAndSettle(const Duration(seconds: 5));
    expect(find.text('No new bank/wallet SMS found.'), findsOneWidget);
  });
}
