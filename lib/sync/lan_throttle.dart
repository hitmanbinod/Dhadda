// LAN-side PIN/auth throttling (Phase 5).
//
// Separate from the app-PIN PinThrottle: this guards network endpoints
// against rapid guessing. Deliberately in-memory and bounded (two counters
// per scope, no per-attacker state that could grow without limit):
//   - WiFi sender / phone-host meta scope: one GLOBAL bucket per server
//     (servers live minutes-to-hours; restart resets, which is documented).
//   - Link mailboxes: one bucket PER BOX (boxes already cap at 50 with TTL;
//     guessing at box X never locks out box Y).
// Policy: 10 free failures, then HTTP 429 with Retry-After for 60 s.
// Any success resets. No permanent lockout. Injectable clock for tests.
//
// This does not stop a passive observer (plain HTTP) or a distributed
// guessing fleet; it makes casual brute force infeasible inside short
// credential lifetimes (5-minute senders, per-pairing link boxes).
class LanThrottle {
  static const freeAttempts = 10;
  static const cooldown = Duration(seconds: 60);

  final DateTime Function() now;
  final Map<String, _Bucket> _buckets = {};

  LanThrottle({DateTime Function()? now}) : now = now ?? DateTime.now;

  /// True when [scope] may attempt authentication now.
  bool allowed(String scope) => remaining(scope) == Duration.zero;

  /// Seconds the caller must wait (0 = go ahead). For Retry-After headers.
  Duration remaining(String scope) {
    final b = _buckets[scope];
    if (b == null || b.fails < freeAttempts) return Duration.zero;
    final elapsed = now().difference(b.windowStart);
    // Cooldown runs from the most recent failure.
    final remain = cooldown - elapsed;
    return remain.isNegative ? Duration.zero : remain;
  }

  /// Records a failed attempt. Old windows slide: failures older than the
  /// cooldown stop counting, so stale bursts never accumulate.
  void failed(String scope) {
    final t = now();
    final b = _buckets.putIfAbsent(scope, () => _Bucket(0, t));
    if (t.difference(b.windowStart) > cooldown) {
      b.fails = 1;
      b.windowStart = t;
    } else {
      b.fails++;
      b.windowStart = t;
    }
    // Hard bound even if scopes proliferate unexpectedly.
    if (_buckets.length > 512) _buckets.clear();
  }

  /// Records a success: the scope starts clean.
  void passed(String scope) => _buckets.remove(scope);

  /// Scopes currently tracked (diagnostics only; never secrets).
  int get trackedScopes => _buckets.length;
}

class _Bucket {
  int fails;
  DateTime windowStart;
  _Bucket(this.fails, this.windowStart);
}
