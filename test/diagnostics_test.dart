// Phase 7: privacy-safe diagnostics report tests. Builds a populated
// store carrying distinctive secret-marked strings, then proves neither
// the report map nor its formatted text contains them.
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:expense/data/app_db.dart';
import 'package:expense/data/drift_domain_store.dart';
import 'package:expense/store.dart';
import 'package:expense/sync/diagnostics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('report carries counts and versions, never content', () async {
    final file = File('${Directory.systemTemp.path}/dhadda_p7_diag.sqlite');
    for (final s in ['', '-journal', '-wal', '-shm']) {
      final f = s.isEmpty ? file : File('${file.path}$s');
      if (await f.exists()) {
        try {
          await f.delete();
        } catch (_) {}
      }
    }
    DriftDomainStore? backend;
    try {
      SharedPreferences.setMockInitialValues({});
      backend = DriftDomainStore(AppDb(NativeDatabase(file)));
      final s = ExpenseStore(domainOverride: backend);
      await s.load();
      await s.addTransaction(
          type: 'expense',
          amount: 4321,
          categoryId: 'food',
          date: DateTime(2026, 9, 6),
          note: 'SECRETNOTE-XYZ');
      await s.addLoan(
          person: 'SECRET PERSON', amount: 99, date: DateTime(2026, 1, 1));
      await s.deleteTransaction(
          s.transactions.firstWhere((t) => t.note == 'SECRETNOTE-XYZ').id);
      final prefs = await SharedPreferences.getInstance();
      final report = DiagnosticsReport.collect(
        store: s,
        dbSchemaVersion: AppDb.dbSchemaVersion,
        migrated: prefs.getInt('expense_db_migrated_v1') == 1,
        syncV2: prefs.getInt('expense_sync_v2_v1') == 1,
        lanServing: true,
      );
      // Keys are allow-listed by construction.
      expect(report.keys.toSet().difference(kDiagnosticsKeys), isEmpty);
      expect(report['transactions'], 0); // added then deleted
      expect(report['loans'], 1);
      expect(report['tombstones'], 1);
      expect(report['appVersion'], isNotEmpty);
      expect(report['dbSchemaVersion'], 2);
      expect(report['lanServing'], isTrue);
      final blob = '${jsonEncode(report)}\n${DiagnosticsReport.format(report)}';
      for (final secret in [
        'SECRETNOTE-XYZ',
        'SECRET PERSON',
        '4321',
      ]) {
        expect(blob, isNot(contains(secret)));
      }
      // Device identity is excluded entirely.
      expect(blob, isNot(contains(s.deviceId)));
      await backend.close();
    } finally {
      try {
        await backend?.close();
      } catch (_) {}
      for (final suffix in ['', '-journal', '-wal', '-shm']) {
        final f =
            suffix.isEmpty ? file : File('${file.path}$suffix');
        if (await f.exists()) {
          try {
            await f.delete();
          } catch (_) {}
        }
      }
    }
  });

  test('format refuses unknown keys (fail-closed privacy)', () {
    expect(
      () => DiagnosticsReport.format({'evil': 1, 'appVersion': 'x'}),
      throwsA(isA<ArgumentError>()),
    );
  });
}
