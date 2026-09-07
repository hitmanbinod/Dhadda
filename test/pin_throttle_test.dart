// Phase 3: PIN throttle tests. Deterministic via an injectable fake clock
// (no real-time waits); persistence across instances proves restart safety.
import 'package:expense/security.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Controllable clock for delay tests.
class _Clock {
  var ms = 1000000000000;
  DateTime call() => DateTime.fromMillisecondsSinceEpoch(ms);
  void advance(Duration d) => ms += d.inMilliseconds;
}

Future<PinThrottle> _throttle(_Clock clock) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return PinThrottle(prefs, now: clock.call);
}

void main() {
  test('fresh throttle allows attempts immediately', () async {
    final t = await _throttle(_Clock());
    expect(t.failures, 0);
    expect(t.delayRemaining(), Duration.zero);
  });

  test('first four failures stay free, fifth arms a delay', () async {
    final clock = _Clock();
    final t = await _throttle(clock);
    for (var i = 0; i < 4; i++) {
      await t.recordFailure();
      expect(t.delayRemaining(), Duration.zero, reason: 'fail ${i + 1}');
    }
    await t.recordFailure();
    expect(t.delayRemaining(), const Duration(seconds: 5));
  });

  test('delays progress 5/10/20/40 then cap at 5 minutes', () async {
    final clock = _Clock();
    final t = await _throttle(clock);
    final expected = [0, 0, 0, 0, 0, 5, 10, 20, 40, 80, 160, 300, 300];
    for (var i = 0; i < expected.length; i++) {
      expect(
        PinThrottle.delayForFailures(i),
        Duration(seconds: expected[i]),
        reason: 'fails=$i',
      );
    }
    for (var i = 0; i < 12; i++) {
      await t.recordFailure();
    }
    expect(t.delayRemaining(), const Duration(minutes: 5));
    // Delay decays as the fake clock advances, then clears.
    clock.advance(const Duration(minutes: 4, seconds: 59));
    expect(t.delayRemaining(), const Duration(seconds: 1));
    clock.advance(const Duration(seconds: 2));
    expect(t.delayRemaining(), Duration.zero);
  });

  test('success resets failures and delay', () async {
    final clock = _Clock();
    final t = await _throttle(clock);
    for (var i = 0; i < 6; i++) {
      await t.recordFailure();
    }
    expect(t.delayRemaining(), isNot(Duration.zero));
    await t.recordSuccess();
    expect(t.failures, 0);
    expect(t.delayRemaining(), Duration.zero);
  });

  test('state survives across instances (restart persistence)', () async {
    final clock = _Clock();
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final a = PinThrottle(prefs, now: clock.call);
    for (var i = 0; i < 5; i++) {
      await a.recordFailure();
    }
    final b = PinThrottle(prefs, now: clock.call);
    expect(b.failures, 5);
    expect(b.delayRemaining(), const Duration(seconds: 5));
    await b.recordSuccess();
    final c = PinThrottle(prefs, now: clock.call);
    expect(c.failures, 0);
  });

  test('corrupt throttle state safely defaults to no delay', () async {
    SharedPreferences.setMockInitialValues({
      'expense_pin_fails_v1': 'garbage',
      'expense_pin_lastfail_v1': -999,
    });
    final prefs = await SharedPreferences.getInstance();
    final t = PinThrottle(prefs);
    expect(t.failures, 0);
    expect(t.delayRemaining(), Duration.zero);
  });

  test('PIN verify round-trip still works alongside throttle', () async {
    final clock = _Clock();
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final vault = PinVault(prefs);
    final throttle = PinThrottle(prefs, now: clock.call);
    await vault.setPin('1234');
    expect(vault.verify('1234'), isTrue);
    expect(vault.verify('0000'), isFalse);
    await throttle.recordFailure();
    expect(throttle.failures, 1);
    // Change/remove flows keep (not reset) the counter: only unlock resets.
    await throttle.recordSuccess(); // models a successful unlock
    expect(throttle.failures, 0);
  });
}
