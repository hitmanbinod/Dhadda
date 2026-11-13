import 'package:expense/screens/sync_screen.dart';
import 'package:expense/store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Regression: the "Sync now" button under the code field must actually
/// join with that field's code. It used to read only the manual
/// Server/Code/PIN boxes, so pasting a code text (the camera-free join
/// for a PC browser, and now any device) bounced off "Fill server, code
/// and PIN" forever and pairing never completed from the pasted side.

Future<ExpenseStore> _readyStore() async {
  SharedPreferences.setMockInitialValues({});
  final store = ExpenseStore();
  await store.load();
  return store;
}

Future<void> _pumpSync(WidgetTester tester, ExpenseStore store) async {
  await tester.pumpWidget(
    MaterialApp(
      home: ChangeNotifierProvider<ExpenseStore>.value(
        value: store,
        child: const Scaffold(body: SyncScreen()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Sync now joins with a pasted code text', (tester) async {
    final store = await _readyStore();
    await _pumpSync(tester, store);

    // TEST-NET-1 address: the join is genuinely attempted, but no
    // socket can ever open inside the test zone, so the client's own
    // 10 s timeout is the first observable outcome.
    const code =
        'EXPENSESYNC2::http://192.0.2.10:9::TESTCODE::4321::deadbeef';
    await tester.enterText(
      find.widgetWithText(TextField, 'Paste code text (easiest)'),
      code,
    );
    await tester.tap(find.text('Sync now'));
    await tester.pump(const Duration(seconds: 11));
    await tester.pump();

    // The input-validation messages must not appear: the code was used.
    expect(find.textContaining('Fill server, code and PIN'), findsNothing);
    expect(find.textContaining('Paste the code text'), findsNothing);
    expect(find.textContaining('Quick sync failed'), findsOneWidget);
  });

  testWidgets('Sync now with nothing entered asks for the code',
      (tester) async {
    final store = await _readyStore();
    await _pumpSync(tester, store);

    await tester.tap(find.text('Sync now'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.textContaining('Fill server, code and PIN'), findsOneWidget);
  });
}
