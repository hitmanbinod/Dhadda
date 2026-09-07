// Phase 7: backup/restore integration through public store paths with
// real file-backed databases and real restarts between phases.
//
// Plaintext: seed -> export -> mutate -> import -> verify legacy
// whole-replace semantics -> reload from reopened DB -> verify persisted.
// Encrypted: export -> encrypt -> wrong password (no mutation) ->
// decrypt -> import -> verify -> reload.
// VM-only; all fixture data synthetic.
import 'dart:io';

import 'package:drift/native.dart';
import 'package:expense/data/app_db.dart';
import 'package:expense/data/drift_domain_store.dart';
import 'package:expense/models.dart';
import 'package:expense/store.dart';
import 'package:expense/sync/backup_crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _fixture(String name) =>
    File('test/fixtures/phase0/$name').readAsStringSync();

class _Db {
  DriftDomainStore backend;
  final File file;
  _Db._(this.backend, this.file);

  static Future<_Db> open(String name) async {
    final file = File('${Directory.systemTemp.path}/dhadda_p7_$name.sqlite');
    for (final s in ['', '-journal', '-wal', '-shm']) {
      final f = s.isEmpty ? file : File('${file.path}$s');
      if (await f.exists()) {
        try {
          await f.delete();
        } catch (_) {}
      }
    }
    return _Db._(DriftDomainStore(AppDb(NativeDatabase(file))), file);
  }

  Future<DriftDomainStore> relaunch() async {
    try {
      await backend.close();
    } catch (_) {}
    backend = DriftDomainStore(AppDb(NativeDatabase(file)));
    return backend;
  }

  Future<void> dispose() async {
    try {
      await backend.close();
    } catch (_) {}
    for (var i = 0; i < 20; i++) {
      try {
        if (await file.exists()) await file.delete();
        return;
      } catch (_) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
    }
  }
}

Future<ExpenseStore> _freshStore(DriftDomainStore backend) async {
  SharedPreferences.setMockInitialValues({});
  final s = ExpenseStore(domainOverride: backend);
  await s.load();
  return s;
}

Future<void> _seedPopulated(ExpenseStore s) async {
  final msg = await s.importSnapshotString(
    _fixture('snapshot_populated.json'),
    force: true,
  );
  expect(msg, startsWith('Synced'));
  expect(s.transactions, hasLength(8));
}

void main() {
  test('plaintext backup round-trip with restart', () async {
    final db = await _Db.open('plain');
    try {
      final a = await _freshStore(db.backend);
      await _seedPopulated(a);
      final backup = a.exportJson();
      // Mutate away from the backup: add one, delete one.
      await a.addTransaction(
        type: 'expense',
        amount: 1,
        categoryId: 'food',
        date: DateTime(2026, 9, 6),
      );
      final doomed = a.transactions.first.id;
      await a.deleteTransaction(doomed);
      expect(a.transactions, hasLength(8));
      // Restore: legacy whole-replace semantics bring back exactly 8.
      expect(
        await a.importSnapshotString(backup, force: true),
        startsWith('Synced'),
      );
      expect(a.transactions, hasLength(8));
      expect(a.transactions.any((t) => t.id == doomed), isTrue);
      expect(a.pendingLoansTotal, 4000);
      expect(a.pendingBorrowedTotal, 6000);
      expect(a.categories.firstWhere((c) => c.id == 'food').budget, 15000);
      // Restart: reopened database serves the restored state.
      final b = ExpenseStore(domainOverride: await db.relaunch());
      await b.load();
      expect(
        b.transactions.map((t) => t.id),
        orderedEquals(a.transactions.map((t) => t.id)),
      );
      expect(b.pendingLoansTotal, 4000);
      // Export stays a valid v1 snapshot with the same meaning.
      final snap = Snapshot.decode(b.exportJson());
      expect(snap.transactions, hasLength(8));
      expect(
        snap.loans.singleWhere((l) => l.id == 'loan-0001').topups,
        hasLength(1),
      );
    } finally {
      await db.dispose();
    }
  });

  test('encrypted backup round-trip, wrong password mutates nothing', () async {
    final db = await _Db.open('enc');
    try {
      final a = await _freshStore(db.backend);
      await _seedPopulated(a);
      final enc = await BackupCrypto.encrypt(a.exportJson(), 's3cret!');
      expect(BackupCrypto.isEncrypted(enc), isTrue);
      // Wrong password: throws, store untouched.
      await expectLater(
        BackupCrypto.decrypt(enc, 'nope'),
        throwsA(isA<FormatException>()),
      );
      expect(a.transactions, hasLength(8));
      // Mutate, then restore from the decrypted backup.
      await a.deleteTransaction(a.transactions.first.id);
      expect(a.transactions, hasLength(7));
      final clear = await BackupCrypto.decrypt(enc, 's3cret!');
      expect(
        await a.importSnapshotString(clear, force: true),
        startsWith('Synced'),
      );
      expect(a.transactions, hasLength(8));
      // Restart: restored state persisted, revisions intact.
      final b = ExpenseStore(domainOverride: await db.relaunch());
      await b.load();
      expect(b.transactions, hasLength(8));
      expect(b.revisionCount, greaterThan(0));
      expect(b.categories.firstWhere((c) => c.id == 'pets').budget, 2000);
    } finally {
      await db.dispose();
    }
  });

  test('unicode backup survives encrypt/decrypt/import exactly', () async {
    final db = await _Db.open('uni');
    try {
      final a = await _freshStore(db.backend);
      expect(
        await a.importSnapshotString(
          _fixture('snapshot_unicode.json'),
          force: true,
        ),
        startsWith('Synced'),
      );
      final enc = await BackupCrypto.encrypt(a.exportJson(), 'pw');
      final clear = await BackupCrypto.decrypt(enc, 'pw');
      SharedPreferences.setMockInitialValues({});
      final db2 = await _Db.open('uni2');
      try {
        final b = ExpenseStore(domainOverride: db2.backend);
        await b.load();
        expect(
          await b.importSnapshotString(clear, force: true),
          startsWith('Synced'),
        );
        expect(
          b.transactions.map((t) => t.note).join('|'),
          contains('दाल भात'),
        );
        expect(
          b.transactions.map((t) => t.amount),
          containsAll([185.5, 0.01, 99999999.99]),
        );
      } finally {
        await db2.dispose();
      }
    } finally {
      await db.dispose();
    }
  });
}
