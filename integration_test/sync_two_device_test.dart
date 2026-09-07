// Phase 7: two-instance link sync, device side. The host drives the other
// side (Node relay + curl peer) while this test joins via manual code
// entry on a real device/emulator.
//
// Driven by --dart-define:
//   RELAY_URL   e.g. http://192.168.1.66:8099
//   LINK_ID     link box id created by the host (pre-seeded with EXPECT_NOTE)
//   LINK_PIN    pairing PIN chosen by the host
//   EXPECT_NOTE txn note the host pre-seeded (must appear after joining)
//   ADD_NOTE    txn note this device publishes (host verifies it)
//
// Run: flutter test integration_test/sync_two_device_test.dart
//        -d <device> --dart-define=RELAY_URL=... --dart-define=...
// See docs/TESTING.md for the host-side choreography.
import 'package:expense/main.dart' as app;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('two-device link sync via manual code entry', (tester) async {
    const relay = String.fromEnvironment('RELAY_URL');
    const link = String.fromEnvironment('LINK_ID');
    const pin = String.fromEnvironment('LINK_PIN');
    const expectNote = String.fromEnvironment('EXPECT_NOTE');
    const addNote = String.fromEnvironment('ADD_NOTE');
    expect(relay.isNotEmpty, isTrue, reason: 'RELAY_URL dart-define needed');
    expect(link.isNotEmpty, isTrue, reason: 'LINK_ID dart-define needed');
    expect(pin.isNotEmpty, isTrue, reason: 'LINK_PIN dart-define needed');
    // Tall surface so lazily-built form fields exist without scrolling.
    tester.view.physicalSize = const Size(720, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    app.main();
    await tester.pumpAndSettle();
    // Sync screen via Menu -> Open sync.
    await tester.tap(find.byType(NavigationDestination).at(3));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
        find.widgetWithText(FilledButton, 'Open sync'), 500);
    await tester.tap(find.widgetWithText(FilledButton, 'Open sync'));
    await tester.pumpAndSettle();

    Future<void> enterLabeled(String label, String value) async {
      final field = find.widgetWithText(TextField, label);
      await tester.scrollUntilVisible(field, 500);
      await tester.enterText(field, value);
      await tester.pump(const Duration(milliseconds: 300));
    }

    await enterLabeled('Server', relay);
    await enterLabeled('Code', link);
    await enterLabeled('PIN', pin);
    await tester.scrollUntilVisible(
        find.widgetWithText(FilledButton, 'Sync now'), 500);
    await tester.tap(find.widgetWithText(FilledButton, 'Sync now'));
    // Real network round-trips: allow generous real time.
    await tester.pump(const Duration(seconds: 15));
    await tester.pumpAndSettle(const Duration(seconds: 5));

    if (expectNote.isNotEmpty) {
      await tester.tap(find.byType(NavigationDestination).at(1));
      await tester.pumpAndSettle();
      expect(find.textContaining(expectNote), findsWidgets,
          reason: 'host-seeded record must arrive via link sync');
      // ignore: avoid_print
      print('TWO-DEVICE: converged on "$expectNote"');
    }

    if (addNote.isNotEmpty) {
      // Publish our own record through the Add UI, then let the
      // auto-sync engine announce it (debounce + poll handle timing).
      await tester.tap(find.byType(NavigationDestination).at(0));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Add expense'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.enterText(find.byType(TextField).first, '50');
      await tester.tap(find.text('Food').first);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.enterText(find.byType(TextField).last, addNote);
      await tester.scrollUntilVisible(find.text('Save'), 500);
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pump(const Duration(seconds: 2));
      // ignore: avoid_print
      print('TWO-DEVICE: published "$addNote", waiting for auto-announce');
      await tester.pump(const Duration(seconds: 20));
    }
    // ignore: avoid_print
    print('TWO-DEVICE: device side done');
  });
}
