// Phase 5: LanThrottle unit tests. Deterministic via injectable fake clock.
import 'package:expense/sync/lan_throttle.dart';
import 'package:flutter_test/flutter_test.dart';

class _Clock {
  var ms = 2000000000000;
  DateTime call() => DateTime.fromMillisecondsSinceEpoch(ms);
  void advance(Duration d) => ms += d.inMilliseconds;
}

void main() {
  test('first ten failures are free, eleventh is throttled', () {
    final clock = _Clock();
    final t = LanThrottle(now: clock.call);
    for (var i = 0; i < 10; i++) {
      expect(t.allowed('s'), isTrue, reason: 'attempt ${i + 1}');
      t.failed('s');
    }
    expect(t.allowed('s'), isFalse);
    expect(t.remaining('s'), const Duration(seconds: 60));
  });

  test('cooldown decays and clears without new failures', () {
    final clock = _Clock();
    final t = LanThrottle(now: clock.call);
    for (var i = 0; i < 11; i++) {
      t.failed('s');
    }
    clock.advance(const Duration(seconds: 59));
    expect(t.remaining('s'), const Duration(seconds: 1));
    clock.advance(const Duration(seconds: 2));
    expect(t.allowed('s'), isTrue);
  });

  test('stale bursts do not accumulate', () {
    final clock = _Clock();
    final t = LanThrottle(now: clock.call);
    for (var i = 0; i < 9; i++) {
      t.failed('s');
    }
    clock.advance(const Duration(minutes: 5)); // window slides past
    t.failed('s');
    expect(t.allowed('s'), isTrue); // counted as a fresh first failure
  });

  test('success resets the scope', () {
    final clock = _Clock();
    final t = LanThrottle(now: clock.call);
    for (var i = 0; i < 11; i++) {
      t.failed('s');
    }
    expect(t.allowed('s'), isFalse);
    t.passed('s');
    expect(t.allowed('s'), isTrue);
    expect(t.remaining('s'), Duration.zero);
  });

  test('scopes are isolated and bounded', () {
    final clock = _Clock();
    final t = LanThrottle(now: clock.call);
    for (var i = 0; i < 11; i++) {
      t.failed('box:A');
    }
    expect(t.allowed('box:A'), isFalse);
    expect(t.allowed('box:B'), isTrue); // guessing at A never locks B
    for (var i = 0; i < 600; i++) {
      t.failed('box:$i');
    }
    expect(t.trackedScopes, lessThanOrEqualTo(512));
  });
}
