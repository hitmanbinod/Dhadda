import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Local-only PIN vault. The PIN itself is never stored - only its
/// salted SHA-256 hash in SharedPreferences (per-device storage).
/// Threat model: casual snoopers, not forensics. $0, no server.
class PinVault {
  static const storageKey = 'expense_pin_hash_v1';
  static const biometricKey = 'expense_biometric_v1';
  static const _salt = 'expense-tracker::pin::v1';

  final SharedPreferences prefs;
  PinVault(this.prefs);

  static Future<PinVault> open() async =>
      PinVault(await SharedPreferences.getInstance());

  bool get isEnabled => (prefs.getString(storageKey) ?? '').isNotEmpty;

  static String hashOf(String pin) =>
      sha256.convert(utf8.encode('$_salt::$pin')).toString();

  Future<void> setPin(String pin) =>
      prefs.setString(storageKey, hashOf(pin));

  bool verify(String pin) => prefs.getString(storageKey) == hashOf(pin);

  Future<void> clear() => prefs.remove(storageKey);

  bool get biometric => prefs.getBool(biometricKey) ?? false;

  Future<void> setBiometric(bool v) =>
      prefs.setBool(biometricKey, v);
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
    final elapsed =
        now().millisecondsSinceEpoch - (last < 0 ? 0 : last);
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