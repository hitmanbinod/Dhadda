import 'package:expense/security.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('pin set / verify / change / disable round-trip', () async {
    SharedPreferences.setMockInitialValues({});
    final vault = PinVault(await SharedPreferences.getInstance());

    expect(vault.isEnabled, isFalse);
    expect(vault.verify('1234'), isFalse);

    await vault.setPin('1234');
    expect(vault.isEnabled, isTrue);
    expect(vault.verify('1234'), isTrue);
    expect(vault.verify('0000'), isFalse);

    await vault.setPin('987654');
    expect(vault.verify('1234'), isFalse);
    expect(vault.verify('987654'), isTrue);

    await vault.clear();
    expect(vault.isEnabled, isFalse);
  });

  test('stored value is a hash, not the pin', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final vault = PinVault(prefs);
    await vault.setPin('1234');
    final stored = prefs.getString(PinVault.storageKey) ?? '';
    expect(stored, isNotEmpty);
    expect(stored.contains('1234'), isFalse);
    // PBKDF2 scheme: random per-user salt means two hashes of the same
    // PIN differ; verification is scheme-aware, not string equality.
    expect(stored.startsWith('pbkdf2\$'), isTrue);
    expect(PinVault.matches(stored, '1234'), isTrue);
    expect(PinVault.matches(stored, '0000'), isFalse);
  });

  test('legacy sha256 entries still verify (upgrade path)', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final vault = PinVault(prefs);
    await prefs.setString(PinVault.storageKey, PinVault.legacyHashOf('1234'));
    expect(vault.verify('1234'), isTrue);
    expect(vault.verify('0000'), isFalse);
  });
}