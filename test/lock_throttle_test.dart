// Phase 7: LockScreen + PinThrottle integration (real widgets, fake clock).
// Proves the UI enforces delays, blocks verification while waiting, and
// unlocks + resets on the correct PIN. No real-time waits anywhere.
import 'package:expense/screens/lock_screen.dart';
import 'package:expense/security.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Clock {
  var ms = 3000000000000;
  DateTime call() => DateTime.fromMillisecondsSinceEpoch(ms);
  void advance(Duration d) => ms += d.inMilliseconds;
}

Future<void> _tapPin(WidgetTester tester, String pin) async {
  for (final ch in pin.split('')) {
    await tester.tap(find.text(ch));
    await tester.pump(const Duration(milliseconds: 10));
  }
}

void main() {
  testWidgets('throttled lock blocks verify and shows the wait', (
    tester,
  ) async {
    final clock = _Clock();
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final vault = PinVault(prefs);
    await vault.setPin('1234');
    final throttle = PinThrottle(prefs, now: clock.call);
    for (var i = 0; i < 5; i++) {
      await throttle.recordFailure();
    }
    var unlocked = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LockScreen(
            vault: vault,
            throttle: throttle,
            onUnlock: () => unlocked = true,
          ),
        ),
      ),
    );
    await _tapPin(tester, '0000');
    await tester.pump(const Duration(seconds: 1));
    expect(unlocked, isFalse);
    expect(find.textContaining('Try again in'), findsOneWidget);
    // After the wait elapses, the correct PIN unlocks and resets.
    clock.advance(const Duration(minutes: 6));
    await _tapPin(tester, '1234');
    await tester.pump(const Duration(seconds: 1));
    expect(unlocked, isTrue);
    expect(throttle.failures, 0);
  });

  testWidgets('correct PIN first try unlocks with no delay', (tester) async {
    final clock = _Clock();
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final vault = PinVault(prefs);
    await vault.setPin('1234');
    var unlocked = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LockScreen(
            vault: vault,
            throttle: PinThrottle(prefs, now: clock.call),
            onUnlock: () => unlocked = true,
          ),
        ),
      ),
    );
    await _tapPin(tester, '1234');
    await tester.pump(const Duration(seconds: 1));
    expect(unlocked, isTrue);
  });

  testWidgets('wrong PIN shows error and counts the failure', (tester) async {
    final clock = _Clock();
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final vault = PinVault(prefs);
    await vault.setPin('1234');
    final throttle = PinThrottle(prefs, now: clock.call);
    var unlocked = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LockScreen(
            vault: vault,
            throttle: throttle,
            onUnlock: () => unlocked = true,
          ),
        ),
      ),
    );
    await _tapPin(tester, '0000');
    await tester.pump(const Duration(seconds: 1));
    expect(unlocked, isFalse);
    expect(find.textContaining('Wrong PIN'), findsOneWidget);
    expect(throttle.failures, 1);
  });
}
