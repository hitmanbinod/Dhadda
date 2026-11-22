// Phase 3: the calm "Use on computer" screen and its owning controller.
import 'package:expense/screens/use_on_computer_screen.dart';
import 'package:expense/store.dart';
import 'package:expense/sync/lan_host.dart';
import 'package:expense/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ExpenseStore> readyStore() async {
  SharedPreferences.setMockInitialValues({});
  final store = ExpenseStore();
  await store.load();
  return store;
}

void main() {
  testWidgets('off state has one primary action and plain words', (tester) async {
    final store = await readyStore();
    final host = LanHostController();
    addTearDown(host.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<ExpenseStore>.value(
        value: store,
        child: MaterialApp(
          theme: AppTheme.build(const Color(0xFF009688), Brightness.dark),
          home: UseOnComputerScreen(host: host),
        ),
      ),
    );

    expect(find.text('Use on computer'), findsOneWidget);
    expect(
      find.text('See and manage your expenses on a bigger screen. '
          'Your data stays on this phone.'),
      findsOneWidget,
    );
    expect(find.byType(FilledButton), findsOneWidget);
    expect(
      find.textContaining('same Wi-Fi').evaluate().isNotEmpty ||
          find.text('Connect to Wi-Fi first').evaluate().isNotEmpty,
      isTrue,
    );
    expect(find.text('On your computer, open'), findsNothing);
    expect(
        find.text('Use only a network you trust, never public or hotel Wi-Fi.'),
        findsOneWidget);
    expect(find.text('More ways to sync'), findsOneWidget);
  });

  test('controller starts, issues a code and stops cleanly', () async {
    final store = await readyStore();
    final host = LanHostController();
    await host.start(store, port: 0);
    try {
      expect(host.running, isTrue);
      expect(host.url, contains('http://'));
      expect(host.code, isNotNull);
      expect(host.code!.length, 8);
      final before = host.code;
      expect(host.newCode(), isNot(before));
      expect(host.newCode().length, 8);
    } finally {
      await host.stop();
    }
    expect(host.running, isFalse);
    expect(host.code, isNull);
  });
}
