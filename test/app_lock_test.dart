import 'package:expense/main.dart';
import 'package:expense/screens/lock_screen.dart';
import 'package:expense/security.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The lock gate replaces `home`, but screens like SyncScreen and AddScreen are
/// pushed onto the root navigator, where they sit above the locked home and
/// stay mounted and interactive. Returning from the background used to leave
/// the pairing screen -- PIN and link secret on screen -- fully usable with no
/// PIN or biometric prompt at all.
/// Drives the real lifecycle transitions the platform would emit. The state
/// machine rejects skips (paused -> resumed), so both directions are spelled
/// out.
void _sendLifecycle(WidgetTester tester, List<AppLifecycleState> states) {
  for (final s in states) {
    tester.binding.handleAppLifecycleStateChanged(s);
  }
}

void main() {
  testWidgets('backgrounding pops pushed routes so the lock screen shows',
      (tester) async {
    // Enable the lock before the app reads the vault at startup.
    SharedPreferences.setMockInitialValues({});
    final vault = PinVault(await SharedPreferences.getInstance());
    await vault.setPin('1234');

    await tester.pumpWidget(const ExpenseApp());
    await tester.pumpAndSettle();
    expect(find.byType(LockScreen), findsOneWidget, reason: 'locked at boot');

    // Unlock so we can reach the shell.
    await tester.tap(find.text('1'));
    await tester.pump();
    await tester.tap(find.text('2'));
    await tester.pump();
    await tester.tap(find.text('3'));
    await tester.pump();
    await tester.tap(find.text('4'));
    await tester.pumpAndSettle();
    expect(find.byType(LockScreen), findsNothing, reason: 'unlocked');

    // Push a screen the way the app bar's sync button does. This stands in
    // for SyncScreen/AddScreen/ScanScreen: anything above the locked home.
    final pushed = GlobalKey<NavigatorState>();
    expect(pushed, isNotNull);
    kRootNavigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('SECRET PAIRING VIEW')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('SECRET PAIRING VIEW'), findsOneWidget);

// Background, then return: the app must re-lock AND drop the pushed
    // route, so the secret view is not what the user comes back to.
    _sendLifecycle(tester, [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]);
    await tester.pumpAndSettle();
    _sendLifecycle(tester, [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]);
    await tester.pumpAndSettle();

    expect(
      find.text('SECRET PAIRING VIEW'),
      findsNothing,
      reason: 'pushed route must be popped when re-locking',
    );
    expect(find.byType(LockScreen), findsOneWidget, reason: 're-locked');
  });
}