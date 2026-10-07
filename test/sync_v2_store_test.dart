// Phase 4 store-level sync tests: revisions, tombstones, merge apply,
// v1 compat, schema upgrade, failure safety. Real file-backed Drift DBs
// (true close/reopen) + mocked prefs. VM-only; never compiled to web.
//
// Device identity is assigned per store after load (public field) so two
// stores in one test converge deterministically with distinct authors.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:expense/data/app_db.dart';
import 'package:expense/data/domain_store.dart';
import 'package:expense/data/drift_domain_store.dart';
import 'package:expense/data/prefs_domain_store.dart';
import 'package:expense/models.dart';
import 'package:expense/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

class _Db {
  DriftDomainStore backend;
  final File file;
  _Db._(this.backend, this.file);

  static Future<_Db> open(String name) async {
    final file = File('${Directory.systemTemp.path}/dhadda_p4_$name.sqlite');
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

Future<ExpenseStore> _store(
  DomainStore backend,
  String device, {
  bool resetMocks = true,
}) async {
  if (resetMocks) SharedPreferences.setMockInitialValues({});
  final s = ExpenseStore(domainOverride: backend);
  await s.load();
  s.deviceId = device;
  return s;
}

Future<void> _addTxn(ExpenseStore s, String note, double amount) =>
    s.addTransaction(
      type: 'expense',
      amount: amount,
      categoryId: 'food',
      date: DateTime(2026, 9, 6),
      note: note,
    );

/// Backend whose merge-apply always fails (proves revert discipline).
class _NoApply extends DriftDomainStore {
  _NoApply(super.db);

  @override
  Future<void> applyV2({
    required DomainData data,
    required Map<String, RecordMeta> meta,
    required List<TombEntry> tombs,
  }) => throw StateError('disk gone');
}

/// Backend whose merge-apply pauses mid-write until a concurrent mutator
/// tries to write (or a short grace period expires). Models the exact window
/// where Dart's await-yield used to let a just-saved entry be overwritten by a
/// wholesale replace computed from older state.
class _RacingBackend implements DomainStore {
  _RacingBackend(this.inner);

  final DomainStore inner;
  final applyV2Entered = Completer<void>();
  final concurrentWrite = Completer<void>();
  bool blockApplies = true;

  @override
  Future<void> applyV2({
    required DomainData data,
    required Map<String, RecordMeta> meta,
    required List<TombEntry> tombs,
  }) async {
    if (!applyV2Entered.isCompleted) applyV2Entered.complete();
    if (blockApplies) {
      await Future.any<Object?>([
        concurrentWrite.future,
        Future<Object?>.delayed(const Duration(seconds: 3)),
      ]);
    }
    return inner.applyV2(data: data, meta: meta, tombs: tombs);
  }

  @override
  Future<void> upsertTransaction(Txn txn, {int? rev, String? by}) {
    if (!concurrentWrite.isCompleted) concurrentWrite.complete();
    return inner.upsertTransaction(txn, rev: rev, by: by);
  }

  @override
  Future<DomainData> loadDomain() => inner.loadDomain();

  @override
  Future<void> replaceAll(DomainData d) => inner.replaceAll(d);

  @override
  Future<void> saveCategories(List<Category> c) => inner.saveCategories(c);

  @override
  Future<void> saveTransactions(List<Txn> t) => inner.saveTransactions(t);

  @override
  Future<void> deleteTransaction(String id) => inner.deleteTransaction(id);

  @override
  Future<void> upsertLoan(Loan l, {int? rev, String? by}) =>
      inner.upsertLoan(l, rev: rev, by: by);

  @override
  Future<void> deleteLoan(String id) => inner.deleteLoan(id);

  @override
  Future<void> upsertProject(Project p, {int? rev, String? by}) =>
      inner.upsertProject(p, rev: rev, by: by);

  @override
  Future<void> deleteProject(String id) => inner.deleteProject(id);

  @override
  Future<Map<String, int>> counts() => inner.counts();

  @override
  Future<void> close() => inner.close();

  @override
  Future<Map<String, RecordMeta>> loadRecordMeta() => inner.loadRecordMeta();

  @override
  Future<void> saveRecordMeta(String type, String id, int rev, String by) =>
      inner.saveRecordMeta(type, id, rev, by);

  @override
  Future<List<TombEntry>> loadTombstones() => inner.loadTombstones();

  @override
  Future<void> saveTombstone(TombEntry tomb) => inner.saveTombstone(tomb);

  @override
  Future<void> deleteTombstone(String type, String id) =>
      inner.deleteTombstone(type, id);

  @override
  Future<void> resetSyncMeta() => inner.resetSyncMeta();
}

void main() {
  test('headline: offline adds on both sides union', () async {
    final dba = await _Db.open('headline-a');
    final dbb = await _Db.open('headline-b');
    try {
      final a = await _store(dba.backend, 'devA');
      final b = await _store(dbb.backend, 'devB');
      await _addTxn(a, 'A1', 100);
      await _addTxn(b, 'B1', 200);
      expect(
        await b.importSnapshotV2(a.exportSnapshotV2()),
        startsWith('Synced'),
      );
      expect(b.transactions.any((t) => t.note == 'A1'), isTrue);
      expect(b.transactions.any((t) => t.note == 'B1'), isTrue);
      expect(
        await a.importSnapshotV2(b.exportSnapshotV2()),
        startsWith('Synced'),
      );
      expect(a.transactions.any((t) => t.note == 'A1'), isTrue);
      expect(a.transactions.any((t) => t.note == 'B1'), isTrue);
      // Second exchange in both directions: nothing left to do.
      expect(
        await a.importSnapshotV2(b.exportSnapshotV2()),
        'Already in sync.',
      );
      expect(
        await b.importSnapshotV2(a.exportSnapshotV2()),
        'Already in sync.',
      );
    } finally {
      await dba.dispose();
      await dbb.dispose();
    }
  });

  test('edited record beats unchanged copy', () async {
    final dba = await _Db.open('edit-a');
    final dbb = await _Db.open('edit-b');
    try {
      final a = await _store(dba.backend, 'devA');
      final b = await _store(dbb.backend, 'devB');
      await _addTxn(a, 'X', 100);
      await b.importSnapshotV2(a.exportSnapshotV2());
      final id = b.transactions.singleWhere((t) => t.note == 'X').id;
      await a.updateTransaction(id, amount: 150);
      expect(
        await b.importSnapshotV2(a.exportSnapshotV2()),
        startsWith('Synced'),
      );
      expect(b.transactions.singleWhere((t) => t.id == id).amount, 150);
    } finally {
      await dba.dispose();
      await dbb.dispose();
    }
  });

  test('concurrent edit converges on the smaller author', () async {
    final dba = await _Db.open('conc-a');
    final dbb = await _Db.open('conc-b');
    try {
      final a = await _store(dba.backend, 'devA');
      final b = await _store(dbb.backend, 'devB');
      await _addTxn(a, 'X', 100);
      await b.importSnapshotV2(a.exportSnapshotV2());
      final id = a.transactions.single.id;
      await a.updateTransaction(id, amount: 111);
      await b.updateTransaction(id, amount: 222);
      await a.importSnapshotV2(b.exportSnapshotV2());
      await b.importSnapshotV2(a.exportSnapshotV2());
      final fa = a.transactions.singleWhere((t) => t.id == id).amount;
      final fb = b.transactions.singleWhere((t) => t.id == id).amount;
      expect(fa, fb); // converged
      expect(fa, 111); // devA < devB wins the rev tie
    } finally {
      await dba.dispose();
      await dbb.dispose();
    }
  });

  test('delete beats unchanged and older updates', () async {
    final dba = await _Db.open('del-a');
    final dbb = await _Db.open('del-b');
    try {
      final a = await _store(dba.backend, 'devA');
      final b = await _store(dbb.backend, 'devB');
      await _addTxn(a, 'X', 100);
      await b.importSnapshotV2(a.exportSnapshotV2());
      final id = a.transactions.single.id;
      await a.deleteTransaction(id);
      expect(
        await b.importSnapshotV2(a.exportSnapshotV2()),
        startsWith('Synced'),
      );
      expect(b.transactions.any((t) => t.id == id), isFalse);
      // Stays deleted across further rounds (no resurrection).
      expect(
        await b.importSnapshotV2(a.exportSnapshotV2()),
        'Already in sync.',
      );
      expect(
        await a.importSnapshotV2(b.exportSnapshotV2()),
        'Already in sync.',
      );
    } finally {
      await dba.dispose();
      await dbb.dispose();
    }
  });

  test('newer update beats older deletion and vice versa', () async {
    final dba = await _Db.open('delupd-a');
    final dbb = await _Db.open('delupd-b');
    try {
      final a = await _store(dba.backend, 'devA');
      final b = await _store(dbb.backend, 'devB');
      await _addTxn(a, 'X', 100);
      await b.importSnapshotV2(a.exportSnapshotV2());
      final id = a.transactions.single.id;
      // B edits twice (rev 3); A deletes at rev 2 -> update wins.
      await b.updateTransaction(id, amount: 200);
      await b.updateTransaction(id, amount: 300);
      await a.deleteTransaction(id);
      await b.importSnapshotV2(a.exportSnapshotV2());
      expect(b.transactions.singleWhere((t) => t.id == id).amount, 300);
      // Now A sees rev 3, deletes again (tomb rev 4) -> deletion wins.
      await a.importSnapshotV2(b.exportSnapshotV2());
      await a.deleteTransaction(id);
      await b.importSnapshotV2(a.exportSnapshotV2());
      expect(b.transactions.any((t) => t.id == id), isFalse);
    } finally {
      await dba.dispose();
      await dbb.dispose();
    }
  });

  test('tombstone survives restart and suppresses stale copies', () async {
    final dba = await _Db.open('tombre-a');
    final dbb = await _Db.open('tombre-b');
    try {
      final a = await _store(dba.backend, 'devA');
      final b = await _store(dbb.backend, 'devB');
      await _addTxn(a, 'X', 100);
      final staleCopy = a.exportSnapshotV2();
      await b.importSnapshotV2(staleCopy);
      final id = a.transactions.single.id;
      await a.deleteTransaction(id);
      await b.importSnapshotV2(a.exportSnapshotV2());
      expect(b.transactions.any((t) => t.id == id), isFalse);
      // Restart B (real close + reopen): tombstone persisted.
      final b2 = ExpenseStore(domainOverride: await dbb.relaunch());
      await b2.load();
      expect(b2.transactions.any((t) => t.id == id), isFalse);
      // The stale pre-delete copy cannot resurrect it.
      expect(await b2.importSnapshotV2(staleCopy), 'Already in sync.');
      expect(b2.transactions.any((t) => t.id == id), isFalse);
    } finally {
      await dba.dispose();
      await dbb.dispose();
    }
  });

  test('wall-clock skew never decides', () async {
    final dba = await _Db.open('skew-a');
    final dbb = await _Db.open('skew-b');
    try {
      final a = await _store(dba.backend, 'devA');
      final b = await _store(dbb.backend, 'devB');
      await _addTxn(a, 'X', 100);
      await b.importSnapshotV2(a.exportSnapshotV2());
      final id = a.transactions.single.id;
      await a.updateTransaction(id, amount: 500); // higher rev, old clock
      // Craft B's copy with a far-future exportedAt but lower rev.
      final map = jsonDecode(b.exportSnapshotV2()) as Map<String, dynamic>;
      map['exportedAt'] = '2036-01-01T00:00:00.000Z';
      final msg = await a.importSnapshotV2(jsonEncode(map));
      expect(msg, 'Already in sync.');
      expect(a.transactions.singleWhere((t) => t.id == id).amount, 500);
    } finally {
      await dba.dispose();
      await dbb.dispose();
    }
  });

  test(
    'category reorder and budget edits converge deterministically',
    () async {
      final dba = await _Db.open('cat-a');
      final dbb = await _Db.open('cat-b');
      try {
        final a = await _store(dba.backend, 'devA');
        final b = await _store(dbb.backend, 'devB');
        final foodA = a.categories.firstWhere((c) => c.id == 'food');
        final travelB = b.categories.firstWhere((c) => c.id == 'travel');
        await a.moveCategoryTo('food', 0);
        await b.moveCategoryTo('travel', 0);
        await a.setBudget(foodA.id, 11111);
        await b.setBudget(travelB.id, 22222);
        await a.importSnapshotV2(b.exportSnapshotV2());
        await b.importSnapshotV2(a.exportSnapshotV2());
        expect(a.categories.map((c) => c.id), b.categories.map((c) => c.id));
        expect(a.categories.last.id, 'other'); // invariant holds
        expect(
          a.categories.map((c) => c.budget),
          b.categories.map((c) => c.budget),
        );
      } finally {
        await dba.dispose();
        await dbb.dispose();
      }
    },
  );

  test('loan edits, top-ups, repayments union; delete is safe', () async {
    final dba = await _Db.open('loan-a');
    final dbb = await _Db.open('loan-b');
    try {
      final a = await _store(dba.backend, 'devA');
      final b = await _store(dbb.backend, 'devB');
      await a.addLoan(person: 'Asha', amount: 5000, date: DateTime(2026, 9, 1));
      await b.importSnapshotV2(a.exportSnapshotV2());
      final id = a.loans.single.id;
      // Concurrent: A tops up, B records a repayment + sets a reminder.
      await a.lendMore(id, 2000, DateTime(2026, 9, 2), 'extra');
      await b.addRepayment(id, 1000, DateTime(2026, 9, 3), 'part');
      await b.setReminderAt(id, DateTime(2026, 9, 10));
      await a.importSnapshotV2(b.exportSnapshotV2());
      await b.importSnapshotV2(a.exportSnapshotV2());
      Loan la() => a.loans.singleWhere((l) => l.id == id);
      Loan lb() => b.loans.singleWhere((l) => l.id == id);
      expect(la().topups, hasLength(1)); // union, not clobber
      expect(lb().repayments, hasLength(1));
      expect(la().pending, lb().pending);
      expect(la().remindAt, lb().remindAt);
      // Delete on A converges; children go with it.
      await a.deleteLoan(id);
      await b.importSnapshotV2(a.exportSnapshotV2());
      expect(b.loans.any((l) => l.id == id), isFalse);
    } finally {
      await dba.dispose();
      await dbb.dispose();
    }
  });

  test('projects update independently and concurrently', () async {
    final dba = await _Db.open('proj-a');
    final dbb = await _Db.open('proj-b');
    try {
      final a = await _store(dba.backend, 'devA');
      final b = await _store(dbb.backend, 'devB');
      final trek = await a.addProject('Trek', '');
      await b.importSnapshotV2(a.exportSnapshotV2());
      await a.updateProject(trek, note: 'autumn');
      final camp = await b.addProject('Camp', '');
      expect(camp, isNotEmpty);
      await a.importSnapshotV2(b.exportSnapshotV2());
      await b.importSnapshotV2(a.exportSnapshotV2());
      expect(a.projects.map((p) => p.id), containsAll([trek, camp]));
      expect(a.projects.firstWhere((p) => p.id == trek).note, 'autumn');
      expect(b.projects.map((p) => p.id), containsAll([trek, camp]));
    } finally {
      await dba.dispose();
      await dbb.dispose();
    }
  });

  test('three devices A-B-C-A converge', () async {
    final dbs = [
      await _Db.open('tri-a'),
      await _Db.open('tri-b'),
      await _Db.open('tri-c'),
    ];
    try {
      final stores = [
        await _store(dbs[0].backend, 'devA'),
        await _store(dbs[1].backend, 'devB'),
        await _store(dbs[2].backend, 'devC'),
      ];
      await _addTxn(stores[0], 'A1', 10);
      await _addTxn(stores[1], 'B1', 20);
      await _addTxn(stores[2], 'C1', 30);
      Future<void> sync(int from, int to) async {
        await stores[to].importSnapshotV2(stores[from].exportSnapshotV2());
      }

      await sync(0, 1);
      await sync(1, 2);
      await sync(2, 0);
      // Second round: already quiet.
      await sync(0, 1);
      await sync(1, 2);
      await sync(2, 0);
      final notes = [
        for (final s in stores) {for (final t in s.transactions) t.note},
      ];
      expect(notes[0], containsAll(['A1', 'B1', 'C1']));
      expect(notes[0], notes[1]);
      expect(notes[1], notes[2]);
    } finally {
      for (final d in dbs) {
        await d.dispose();
      }
    }
  });

  test('v1 peer content unions via rev-0 ingest (legacy interop)', () async {
    final dba = await _Db.open('v1a');
    final dbb = await _Db.open('v1b');
    try {
      final a = await _store(dba.backend, 'devA');
      final b = await _store(dbb.backend, 'devB');
      await _addTxn(a, 'A1', 100);
      // B is "v1-only": its export is v1 bytes; A merges them as baseline.
      await _addTxn(b, 'B1', 200);
      expect(
        await a.ingestPeerSnapshot(b.exportJson(), peerName: 'B'),
        startsWith('Synced'),
      );
      expect(a.transactions.any((t) => t.note == 'B1'), isTrue);
      expect(a.transactions.any((t) => t.note == 'A1'), isTrue);
      // And B can still take A's v1 export the legacy way it understands.
      expect(await b.importSnapshotString(a.exportJson()), isNotEmpty);
    } finally {
      await dba.dispose();
      await dbb.dispose();
    }
  });

  test('v1 import flavors handle tombstones correctly', () async {
    final dba = await _Db.open('rekey');
    try {
      final a = await _store(dba.backend, 'devA');
      await _addTxn(a, 'Keep', 10);
      await _addTxn(a, 'Doomed', 20);
      final doomed = a.transactions.singleWhere((t) => t.note == 'Doomed');
      await a.deleteTransaction(doomed.id);
      // Ambient v1 sync carrying the deleted record: deletion stands.
      final incoming = jsonDecode(a.exportJson()) as Map<String, dynamic>;
      (incoming['transactions'] as List).add(doomed.toJson());
      incoming['updatedAt'] = '2027-01-01T00:00:00.000Z';
      final msg = await a.importSnapshotString(jsonEncode(incoming));
      expect(msg, startsWith('Synced'));
      expect(a.transactions.any((t) => t.id == doomed.id), isFalse);
      // User-picked file with the record: resurrects (old UX preserved).
      incoming['updatedAt'] = '2027-06-01T00:00:00.000Z';
      final msg2 = await a.importFilePayload(jsonEncode(incoming));
      expect(msg2, startsWith('Synced'));
      expect(a.transactions.any((t) => t.id == doomed.id), isTrue);
      // Force restore drops every tombstone.
      await a.deleteTransaction(doomed.id);
      final msg3 = await a.importSnapshotString(
        jsonEncode(incoming),
        force: true,
      );
      expect(msg3, startsWith('Synced'));
      expect(a.transactions.any((t) => t.id == doomed.id), isTrue);
    } finally {
      await dba.dispose();
    }
  });

  test(
    'crafted payloads: other-tomb ignored, refs repaired, orphans dropped',
    () async {
      final dba = await _Db.open('craft');
      try {
        final a = await _store(dba.backend, 'devA');
        String rec(
          String t,
          String id,
          int rev,
          String by, [
          Map<String, dynamic>? d,
          bool dead = false,
        ]) => jsonEncode({
          't': t,
          'id': id,
          'rev': rev,
          'by': by,
          if (dead) 'dead': true,
          'd': ?d,
        });
        final payload = jsonEncode({
          'format': 2,
          'deviceId': 'devX',
          'deviceName': 'X',
          'exportedAt': '2026-09-07T00:00:00.000Z',
          'records': [
            jsonDecode(rec('cat', 'other', 9, 'devX', null, true)),
            jsonDecode(
              rec('txn', 'stray', 1, 'devX', {
                'id': 'stray',
                'type': 'expense',
                'amount': 5,
                'categoryId': 'ghost-cat',
                'date': 1788220800000,
                'note': '',
                'mode': 'cash',
                'projectId': 'ghost-proj',
              }),
            ),
            jsonDecode(
              rec('topup', 'orphan', 1, 'devX', {
                'id': 'orphan',
                'amount': 5,
                'date': 1788220800000,
                'note': '',
              }),
            ),
          ],
        });
        // NOTE: topup without parent is rejected at parse; build it raw.
        final map = jsonDecode(payload) as Map<String, dynamic>;
        ((map['records'] as List).last as Map<String, dynamic>)['parent'] =
            'ghost-loan';
        final msg = await a.importSnapshotV2(jsonEncode(map));
        expect(msg, startsWith('Synced'));
        // Other survives, stray is remapped, orphan is gone.
        expect(a.categories.any((c) => c.id == 'other'), isTrue);
        final stray = a.transactions.singleWhere((t) => t.id == 'stray');
        expect(stray.categoryId, 'other');
        expect(stray.projectId, '');
      } finally {
        await dba.dispose();
      }
    },
  );

  test('schema upgrades v1 -> v2 preserving data', () async {
    // Unique per run: never reuse a file a killed run may have touched.
    final file = File(
      '${Directory.systemTemp.path}/dhadda_p4_upgrade_${DateTime.now().microsecondsSinceEpoch}.sqlite',
    );
    for (final s in ['', '-journal', '-wal', '-shm']) {
      final f = s.isEmpty ? file : File('${file.path}$s');
      if (await f.exists()) {
        try {
          await f.delete();
        } catch (_) {}
      }
    }
    final raw = sqlite3.sqlite3.open(file.path);
    raw.execute(
      'CREATE TABLE categories (id TEXT NOT NULL PRIMARY KEY, name TEXT NOT NULL, icon INTEGER NOT NULL, color INTEGER NOT NULL, budget REAL NOT NULL, sort_order INTEGER NOT NULL)',
    );
    raw.execute(
      'CREATE TABLE transactions (id TEXT NOT NULL PRIMARY KEY, type TEXT NOT NULL, amount REAL NOT NULL, category_id TEXT NOT NULL, date INTEGER NOT NULL, note TEXT NOT NULL, mode TEXT NOT NULL, project_id TEXT NOT NULL)',
    );
    raw.execute(
      'CREATE TABLE projects (id TEXT NOT NULL PRIMARY KEY, name TEXT NOT NULL, note TEXT NOT NULL, created INTEGER NOT NULL, icon INTEGER NOT NULL, color INTEGER NOT NULL)',
    );
    raw.execute(
      'CREATE TABLE loans (id TEXT NOT NULL PRIMARY KEY, person TEXT NOT NULL, kind TEXT NOT NULL, principal REAL NOT NULL, date_lent INTEGER NOT NULL, due_date INTEGER, note TEXT NOT NULL, remind_at INTEGER NOT NULL)',
    );
    raw.execute(
      'CREATE TABLE loan_topups (id TEXT NOT NULL PRIMARY KEY, loan_id TEXT NOT NULL, amount REAL NOT NULL, date INTEGER NOT NULL, note TEXT NOT NULL)',
    );
    raw.execute(
      'CREATE TABLE loan_repayments (id TEXT NOT NULL PRIMARY KEY, loan_id TEXT NOT NULL, amount REAL NOT NULL, date INTEGER NOT NULL, note TEXT NOT NULL)',
    );
    raw.execute(
      "INSERT INTO categories VALUES ('food','Food',0,0,15000.0,0),('other','Other',0,0,0.0,1)",
    );
    raw.execute(
      "INSERT INTO transactions VALUES ('t1','expense',250.0,'food',1788220800000,'lunch','cash','')",
    );
    raw.execute(
      "INSERT INTO loans VALUES ('l1','Asha','lent',5000.0,1788220800000,NULL,'',0)",
    );
    raw.execute(
      "INSERT INTO loan_repayments VALUES ('r1','l1',1000.0,1788566400000,'')",
    );
    // Real Phase-2 databases record schema version 1: without this, drift
    // treats version 0 as "just created" and runs onCreate instead.
    raw.execute('PRAGMA user_version = 1');
    raw.close();
    DriftDomainStore? backend;
    try {
      backend = DriftDomainStore(AppDb(NativeDatabase(file)));
      final data = await backend.loadDomain();
      expect(data.categories.map((c) => c.id), ['food', 'other']);
      expect(data.categories.firstWhere((c) => c.id == 'food').budget, 15000);
      expect(data.transactions.single.amount, 250);
      expect(data.loans.single.pending, 4000);
      // Revision columns defaulted; tombstones table exists and is empty.
      final meta = await backend.loadRecordMeta();
      expect(meta['txn/t1'], isNotNull);
      expect(meta['txn/t1']!.rev, 0);
      expect(await backend.loadTombstones(), isEmpty);
      final idx = await backend.db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='index' AND name LIKE 'idx_%'",
          )
          .get();
      expect(
        idx.map((r) => r.read<String>('name')),
        containsAll(['idx_transactions_date']),
      );
      await backend.close();
      backend = null;
    } finally {
      try {
        await backend?.close();
      } catch (_) {}
      for (final s in ['', '-journal', '-wal', '-shm']) {
        final f = s.isEmpty ? file : File('${file.path}$s');
        if (await f.exists()) {
          try {
            await f.delete();
          } catch (_) {}
        }
      }
    }
  });

  test('interrupted schema upgrade resumes instead of failing forever', () async {
    // A crash between the addColumn statements of onUpgrade leaves user_version
    // at 1 with only some of the rev columns applied. A bare addColumn would
    // then throw "duplicate column name" on every later launch, and drift
    // caches that error — the file becomes permanently unreadable. The
    // guarded upgrade must instead skip what is already there and finish.
    final file = File(
      '${Directory.systemTemp.path}/dhadda_p4_partial_${DateTime.now().microsecondsSinceEpoch}.sqlite',
    );
    for (final s in ['', '-journal', '-wal', '-shm']) {
      final f = s.isEmpty ? file : File('${file.path}$s');
      if (await f.exists()) {
        try {
          await f.delete();
        } catch (_) {}
      }
    }
    final raw = sqlite3.sqlite3.open(file.path);
    // Same v1 schema the test above builds, then apply only the FIRST pair of
    // the twelve addColumn calls — exactly the mid-upgrade crash state.
    raw.execute(
      'CREATE TABLE categories (id TEXT NOT NULL PRIMARY KEY, name TEXT NOT NULL, icon INTEGER NOT NULL, color INTEGER NOT NULL, budget REAL NOT NULL, sort_order INTEGER NOT NULL)',
    );
    raw.execute(
      'ALTER TABLE categories ADD COLUMN rev INTEGER NOT NULL DEFAULT 0',
    );
    raw.execute(
      "ALTER TABLE categories ADD COLUMN rev_by TEXT NOT NULL DEFAULT ''",
    );
    raw.execute(
      'CREATE TABLE transactions (id TEXT NOT NULL PRIMARY KEY, type TEXT NOT NULL, amount REAL NOT NULL, category_id TEXT NOT NULL, date INTEGER NOT NULL, note TEXT NOT NULL, mode TEXT NOT NULL, project_id TEXT NOT NULL)',
    );
    raw.execute(
      'CREATE TABLE projects (id TEXT NOT NULL PRIMARY KEY, name TEXT NOT NULL, note TEXT NOT NULL, created INTEGER NOT NULL, icon INTEGER NOT NULL, color INTEGER NOT NULL)',
    );
    raw.execute(
      'CREATE TABLE loans (id TEXT NOT NULL PRIMARY KEY, person TEXT NOT NULL, kind TEXT NOT NULL, principal REAL NOT NULL, date_lent INTEGER NOT NULL, due_date INTEGER, note TEXT NOT NULL, remind_at INTEGER NOT NULL)',
    );
    raw.execute(
      'CREATE TABLE loan_topups (id TEXT NOT NULL PRIMARY KEY, loan_id TEXT NOT NULL, amount REAL NOT NULL, date INTEGER NOT NULL, note TEXT NOT NULL)',
    );
    raw.execute(
      'CREATE TABLE loan_repayments (id TEXT NOT NULL PRIMARY KEY, loan_id TEXT NOT NULL, amount REAL NOT NULL, date INTEGER NOT NULL, note TEXT NOT NULL)',
    );
    raw.execute(
      "INSERT INTO categories VALUES ('food','Food',0,0,15000.0,0,0,'')",
    );
    raw.execute(
      "INSERT INTO transactions VALUES ('t1','expense',250.0,'food',1788220800000,'lunch','cash','')",
    );
    raw.execute('PRAGMA user_version = 1');
    raw.close();

    DriftDomainStore? backend;
    try {
      // Before the fix this threw "duplicate column name: rev" here.
      backend = DriftDomainStore(AppDb(NativeDatabase(file)));
      final data = await backend.loadDomain();
      expect(data.categories.map((c) => c.id), ['food']);
      expect(data.categories.single.budget, 15000);
      expect(data.transactions.single.amount, 250);

      // Every table now carries both revision columns, not just the ones the
      // interrupted run happened to reach.
      for (final table in [
        'categories',
        'transactions',
        'projects',
        'loans',
        'loan_topups',
        'loan_repayments',
      ]) {
        final cols = await backend.db
            .customSelect('PRAGMA table_info($table)')
            .get();
        final names = cols.map((r) => r.read<String>('name')).toSet();
        expect(names, containsAll(['rev', 'rev_by']), reason: table);
      }
      // Pre-v2 rows kept their rev-0 baseline through the resumed upgrade.
      final meta = await backend.loadRecordMeta();
      expect(meta['txn/t1']!.rev, 0);
      expect(meta['cat/food']!.rev, 0);
      // And the tombstones table was created despite being absent before.
      expect(await backend.loadTombstones(), isEmpty);

      await backend.close();
      backend = null;
    } finally {
      try {
        await backend?.close();
      } catch (_) {}
      for (final s in ['', '-journal', '-wal', '-shm']) {
        final f = s.isEmpty ? file : File('${file.path}$s');
        if (await f.exists()) {
          try {
            await f.delete();
          } catch (_) {}
        }
      }
    }
  });

  test('a merge in flight cannot erase an entry saved concurrently', () async {
    // Dart yields at every await, and _mergeAndApply computes its merge from
    // memory before replacing all seven tables wholesale. Without the domain
    // write lock the concurrent addTransaction commits its row, and the merge
    // -- built from the older snapshot -- then deletes it. No error surfaces:
    // the entry is simply gone.
    final dba = await _Db.open('race-a');
    final dbb = await _Db.open('race-b');
    try {
      final peer = await _store(dbb.backend, 'devPeer');
      await _addTxn(peer, 'FromPeer', 500);

      final racing = _RacingBackend(dba.backend);
      final a = await _store(racing, 'devA');

      // Start the merge; it parks inside applyV2.
      final merge = a.importSnapshotV2(peer.exportSnapshotV2());
      await racing.applyV2Entered.future;

      // Now save an entry locally while the merge is mid-write.
      final save = _addTxn(a, 'SavedDuringMerge', 123);

      await Future.wait([merge, save]);

      // The entry the user just saved must still be there, on disk and in
      // memory, alongside the record the merge adopted.
      final onDisk = await dba.backend.loadDomain();
      expect(
        onDisk.transactions.any((t) => t.note == 'SavedDuringMerge'),
        isTrue,
        reason: 'concurrently saved entry survived the merge',
      );
      expect(
        onDisk.transactions.any((t) => t.note == 'FromPeer'),
        isTrue,
        reason: 'merge still adopted the peer record',
      );
      expect(a.transactions.any((t) => t.note == 'SavedDuringMerge'), isTrue);
      expect(a.transactions.any((t) => t.note == 'FromPeer'), isTrue);
      expect(a.lastPersistError, isNull);
    } finally {
      await dba.dispose();
      await dbb.dispose();
    }
  });

  test('eraseAll drops tombstones and revisions so a wipe cannot delete peers records', () async {
    // prefs.clear() removes the migration marker, so load() re-migrates into the
    // same SQLite file. replaceAll never touched the tombstones table, so before
    // this fix a freshly wiped device re-published every pre-wipe deletion to
    // peers on its next sync -- deleting records the user believed erased.
    final dba = await _Db.open('eraseall');
    try {
      final a = await _store(dba.backend, 'devA');
      await _addTxn(a, 'Doomed', 42);
      await a.deleteTransaction(a.transactions.single.id);
      expect(a.tombstoneCount, 1, reason: 'precondition: one tombstone');
      expect(
        await dba.backend.loadTombstones().then((t) => t.length),
        1,
        reason: 'precondition: tombstone persisted',
      );
      // Bump a revision so we can prove the reset reaches the row too.
      await _addTxn(a, 'Second', 7);
      expect(
        (await dba.backend.loadRecordMeta())['txn/${a.transactions.last.id}']!.rev,
        greaterThan(0),
      );

      await a.eraseAll();

      expect(a.tombstoneCount, 0, reason: 'memory tombstones cleared');
      expect(
        await dba.backend.loadTombstones(),
        isEmpty,
        reason: 'tombstones table cleared on disk',
      );
      expect(a.transactions, isEmpty);
      // Reseeded defaults rejoin at the rev-0 baseline rather than inheriting
      // the pre-wipe revision, so a peer holding the old history cannot
      // outrank them forever.
      expect(
        (await dba.backend.loadRecordMeta()).values.every((m) => m.rev == 0),
        isTrue,
      );
    } finally {
      await dba.dispose();
    }
  });

  test('merge-apply failure leaves memory and DB consistent', () async {
    final dba = await _Db.open('failapply');
    try {
      final a = await _store(dba.backend, 'devA');
      await _addTxn(a, 'Keep', 10);
      final before = a.exportSnapshotV2();
      // A store on the same database whose merge-apply always throws.
      // Mocks are shared on purpose: the marker set above stays visible.
      final broken = await _store(
        _NoApply(dba.backend.db),
        'devA',
        resetMocks: false,
      );
      // Force a real change so merge reaches applyV2 (identical state
      // would short-circuit before it).
      final map = jsonDecode(before) as Map<String, dynamic>;
      (map['records'] as List).add({
        't': 'txn',
        'id': 'intruder',
        'rev': 1,
        'by': 'devA',
        'd': {
          'id': 'intruder',
          'type': 'expense',
          'amount': 1,
          'categoryId': 'food',
          'date': 1788220800000,
          'note': '',
          'mode': 'cash',
          'projectId': '',
        },
      });
      final msg = await broken.importSnapshotV2(jsonEncode(map));
      expect(msg, 'Could not save the sync merge. Nothing was changed.');
      expect(broken.lastPersistError, isNotNull);
      expect(broken.transactions.any((t) => t.id == 'intruder'), isFalse);
      // Reopening the working backend shows undamaged prior state.
      final c = await _store(dba.backend, 'devA', resetMocks: false);
      expect(c.transactions.any((t) => t.note == 'Keep'), isTrue);
    } finally {
      await dba.dispose();
    }
  });

  test('prefs backend round-trips revs and tombstones', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final backend = PrefsDomainStore(prefs);
    await backend.saveRecordMeta('txn', 'x', 7, 'devQ');
    await backend.saveTombstone(
      const TombEntry(type: 'txn', id: 'gone', rev: 3, by: 'devQ'),
    );
    expect((await backend.loadRecordMeta())['txn/x']!.rev, 7);
    expect((await backend.loadTombstones()).single.id, 'gone');
    await backend.deleteTombstone('txn', 'gone');
    expect(await backend.loadTombstones(), isEmpty);
    // A prefs-backed store speaks v2 end to end.
    final s = ExpenseStore(domainOverride: backend);
    await s.load();
    await _addTxn(s, 'W', 5);
    expect(await s.importSnapshotV2(s.exportSnapshotV2()), 'Already in sync.');
  });

  test('bulk 300 merge converges quickly', () async {
    final dba = await _Db.open('bulk-a');
    final dbb = await _Db.open('bulk-b');
    try {
      final a = await _store(dba.backend, 'devA');
      final b = await _store(dbb.backend, 'devB');
      final snap = Snapshot.decode(
        File('test/fixtures/phase0/snapshot_bulk.json').readAsStringSync(),
      );
      await a.importSnapshotString(
        Snapshot(
          version: snap.version,
          updatedAt: '2026-09-06T12:00:00.000Z',
          deviceId: snap.deviceId,
          deviceName: snap.deviceName,
          categories: snap.categories,
          transactions: snap.transactions,
          loans: snap.loans,
          projects: snap.projects,
        ).encode(),
        force: true,
      );
      final stopwatch = Stopwatch()..start();
      expect(
        await b.importSnapshotV2(a.exportSnapshotV2()),
        startsWith('Synced'),
      );
      expect(
        await a.importSnapshotV2(b.exportSnapshotV2()),
        'Already in sync.',
      );
      stopwatch.stop();
      expect(b.transactions, hasLength(300));
      expect(stopwatch.elapsed < const Duration(seconds: 60), isTrue);
    } finally {
      await dba.dispose();
      await dbb.dispose();
    }
  });

  DomainData syntheticData(int n, String prefix) => DomainData(
    categories: const [
      Category(id: 'c0', name: 'C0', icon: 0, color: 0xFF000000),
      Category(id: 'other', name: 'Other', icon: 0, color: 0xFF000000),
    ],
    transactions: [
      for (var i = 0; i < n; i++)
        Txn(
          id: '$prefix-$i',
          type: i % 10 == 0 ? 'income' : 'expense',
          amount: i * 1.25 + 0.5,
          categoryId: 'c0',
          date: 1788220800000 + i * 60000,
          note: 'note $i',
          mode: 'cash',
        ),
    ],
    loans: const [],
    projects: const [],
  );

  test('synthetic 1k/5k merges stay feasible (timing observation)', () async {
    final dba = await _Db.open('perf-a');
    final dbb = await _Db.open('perf-b');
    try {
      for (final n in [1000, 5000]) {
        final stopwatch = Stopwatch()..start();
        // Disjoint record sets: worst case for union work.
        await dba.backend.applyV2(
          data: syntheticData(n, 'a'),
          meta: {},
          tombs: const [],
        );
        await dbb.backend.applyV2(
          data: syntheticData(n, 'b'),
          meta: {},
          tombs: const [],
        );
        // Marker preset: loads read the synthetic databases as-is.
        SharedPreferences.setMockInitialValues({
          'expense_db_migrated_v1': 1,
          'expense_sync_v2_v1': 1,
        });
        final a = ExpenseStore(domainOverride: dba.backend);
        await a.load();
        a.deviceId = 'devA';
        final b = ExpenseStore(domainOverride: dbb.backend);
        await b.load();
        b.deviceId = 'devB';
        await b.importSnapshotV2(a.exportSnapshotV2());
        await a.importSnapshotV2(b.exportSnapshotV2());
        stopwatch.stop();
        expect(a.transactions, hasLength(2 * n));
        expect(b.transactions, hasLength(2 * n));
        // Generous bound: proves feasibility, not a benchmark.
        expect(stopwatch.elapsed < const Duration(minutes: 3), isTrue);
      }
    } finally {
      await dba.dispose();
      await dbb.dispose();
    }
  });

  test('both restart then exchange stays quiet', () async {
    final dba = await _Db.open('restart-a');
    final dbb = await _Db.open('restart-b');
    try {
      final a = await _store(dba.backend, 'devA');
      final b = await _store(dbb.backend, 'devB', resetMocks: false);
      await _addTxn(a, 'A1', 10);
      await _addTxn(b, 'B1', 20);
      await b.importSnapshotV2(a.exportSnapshotV2());
      await a.importSnapshotV2(b.exportSnapshotV2());
      // Restart both (real close + reopen); mocks keep markers.
      final a2 = ExpenseStore(domainOverride: await dba.relaunch());
      await a2.load();
      a2.deviceId = 'devA';
      final b2 = ExpenseStore(domainOverride: await dbb.relaunch());
      await b2.load();
      b2.deviceId = 'devB';
      expect(a2.transactions.map((t) => t.note), containsAll(['A1', 'B1']));
      expect(b2.transactions.map((t) => t.note), containsAll(['A1', 'B1']));
      // Post-restart exchange: zero further logical changes.
      expect(
        await a2.importSnapshotV2(b2.exportSnapshotV2()),
        'Already in sync.',
      );
      expect(
        await b2.importSnapshotV2(a2.exportSnapshotV2()),
        'Already in sync.',
      );
    } finally {
      await dba.dispose();
      await dbb.dispose();
    }
  });
}
