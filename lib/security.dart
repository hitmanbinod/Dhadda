import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Local-only PIN vault. The PIN itself is never stored — only a
/// PBKDF2-HMAC-SHA256 hash with a per-user random salt, encoded as
/// `pbkdf2$iterations$salt-b64$hash-b64` in SharedPreferences
/// (per-device storage). Legacy entries from the old static-salt
/// SHA-256 scheme still verify; they upgrade to PBKDF2 the next time
/// the PIN is set. Threat model: casual snoopers, not forensics.
/// $0, no server.
class PinVault {
  static const storageKey = 'expense_pin_hash_v1';
  static const biometricKey = 'expense_biometric_v1';
  static const _legacySalt = 'expense-tracker::pin::v1';

  /// PBKDF2 iterations for new hashes. Chosen so verification stays
  /// well under a frame on a mid-range phone (~10ms in debug VM) while
  /// raising offline cost per guess ~10,000x over the old single SHA-256.
  static const _pbkdf2Iterations = 10000;
  static const _saltBytes = 16;

  final SharedPreferences prefs;
  PinVault(this.prefs);

  static Future<PinVault> open() async =>
      PinVault(await SharedPreferences.getInstance());

  bool get isEnabled => (prefs.getString(storageKey) ?? '').isNotEmpty;

  /// Legacy format (kept for verification of old stored hashes only).
  static String legacyHashOf(String pin) =>
      sha256.convert(utf8.encode('$_legacySalt::$pin')).toString();

  /// Sync PBKDF2-HMAC-SHA256 (RFC 2898) so [verify] stays callable from
  /// synchronous UI code, exactly like the old hashOf contract.
  static List<int> _pbkdf2(List<int> password, List<int> salt, int iterations) {
    final mac = Hmac(sha256, password);
    // One block: 32-byte key fits in a single SHA-256 block (u1 = HMAC(pwd,
    // salt || INT(1)); uN = HMAC(pwd, u(N-1)); XOR the chain).
    var u = mac.convert([...salt, 0, 0, 0, 1]).bytes;
    final out = List<int>.of(u);
    for (var i = 1; i < iterations; i++) {
      u = mac.convert(u).bytes;
      for (var j = 0; j < out.length; j++) {
        out[j] ^= u[j];
      }
    }
    return out;
  }

  static String hashOf(String pin) {
    final rand = Random.secure();
    final salt = List<int>.generate(_saltBytes, (_) => rand.nextInt(256));
    final key = _pbkdf2(utf8.encode(pin), salt, _pbkdf2Iterations);
    return 'pbkdf2\$$_pbkdf2Iterations\$${base64Encode(salt)}\$${base64Encode(key)}';
  }

  /// True when [stored] matches [pin] under either the current PBKDF2
  /// scheme or the legacy static-salt SHA-256 scheme (pre-upgrade entries).
  static bool matches(String stored, String pin) {
    if (stored.startsWith('pbkdf2\$')) {
      final parts = stored.split('\$');
      if (parts.length != 4) return false;
      final iterations = int.tryParse(parts[1]);
      if (iterations == null || iterations < 1 || iterations > 1 << 20) {
        return false;
      }
      final salt = base64Decode(parts[2]);
      final expected = base64Decode(parts[3]);
      final actual = _pbkdf2(utf8.encode(pin), salt, iterations);
      if (actual.length != expected.length) return false;
      var diff = 0;
      for (var i = 0; i < actual.length; i++) {
        diff |= actual[i] ^ expected[i];
      }
      return diff == 0;
    }
    // Legacy static-salt SHA-256 (no prefix on old entries).
    return stored == legacyHashOf(pin);
  }

  Future<void> setPin(String pin) => prefs.setString(storageKey, hashOf(pin));

  bool verify(String pin) {
    final stored = prefs.getString(storageKey) ?? '';
    if (stored.isEmpty) return false;
    return matches(stored, pin);
  }

  Future<void> clear() => prefs.remove(storageKey);

  bool get biometric => prefs.getBool(biometricKey) ?? false;

  Future<void> setBiometric(bool v) => prefs.setBool(biometricKey, v);
}

/// Progressive-delay guard for the 4-digit app lock.
///
/// The PIN has only 10,000 combinations, so this does NOT make it
/// cryptographic: it makes casual guessing tedious while staying usable.
/// Policy: failures 0-4 verify immediately; from the 5th failure the
/// required wait doubles (5s, 10s, 20s …) up to a 5-minute cap. No
/// permanent lockout, no network. State lives in SharedPreferences so
/// delays survive app restart. A successful unlock (PIN pad or biometric)
/// resets the counter; changing/removing the PIN never resets it.
class PinThrottle {
  static const attemptsKey = 'expense_pin_fails_v1';
  static const lastFailKey = 'expense_pin_lastfail_v1';
  static const maxDelay = Duration(minutes: 5);

  final SharedPreferences prefs;
  final DateTime Function() now;
  PinThrottle(this.prefs, {DateTime Function()? now})
    : now = now ?? DateTime.now;

  int get failures {
    try {
      final v = prefs.getInt(attemptsKey);
      return (v == null || v < 0) ? 0 : v;
    } catch (_) {
      // Corrupt value (e.g. wrong type from manual editing): fail open to
      // no delay rather than crashing the lock screen.
      return 0;
    }
  }

  /// Required wait before the next attempt. Zero means "go ahead".
  Duration delayRemaining() {
    final fails = failures;
    final wait = delayForFailures(fails);
    if (wait == Duration.zero) return Duration.zero;
    int last;
    try {
      last = prefs.getInt(lastFailKey) ?? 0;
    } catch (_) {
      return Duration.zero;
    }
    final elapsed = now().millisecondsSinceEpoch - (last < 0 ? 0 : last);
    final remainMs = wait.inMilliseconds - elapsed;
    return remainMs <= 0 ? Duration.zero : Duration(milliseconds: remainMs);
  }

  static Duration delayForFailures(int fails) {
    if (fails < 5) return Duration.zero;
    var seconds = 5 << (fails - 5); // 5, 10, 20, 40, …
    if (seconds > maxDelay.inSeconds) seconds = maxDelay.inSeconds;
    return Duration(seconds: seconds);
  }

  Future<void> recordFailure() async {
    await prefs.setInt(attemptsKey, failures + 1);
    await prefs.setInt(lastFailKey, now().millisecondsSinceEpoch);
  }

  /// Call on successful PIN-pad unlock AND on biometric success (both
  /// prove the legitimate user is present; biometrics cannot be guessed).
  Future<void> recordSuccess() async {
    await prefs.setInt(attemptsKey, 0);
    await prefs.setInt(lastFailKey, 0);
  }
}
