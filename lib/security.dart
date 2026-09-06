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