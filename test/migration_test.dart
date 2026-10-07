// Phase 2 migration tests: legacy prefs JSON -> SQLite, with real
// file-backed Drift databases in systemTemp (true close/reopen across
// "launches") and mocked SharedPreferences.
//
// VM-only (dart:io + drift native); never compiled to web. All fixture data
// is synthetic (see test/fixtures/phase0/README.md).
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:expense/data/app_db.dart';
import 'package:expense/data/domain_store.dart';
import 'package:expense/data/drift_domain_store.dart';
import 'package:expense/models.dart';
import 'package:expense/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _marker = 'expense_db_migrated_v1';
const _kCats = 'expense_cats_v1';
const _kTxns = 'expense_txns_v1';
const _kLoans = 'expense_loans_v1';
const _kProjects = 'expense_projects_v1';

String _fixture(String name) =>
    File('test/fixtures/phase0/$name').readAsStringSync();

DomainData _domainOf(ExpenseStore s) => DomainData(
  categories: List.of(s.categories),
  transactions: List.of(s.transactions),
  loans: List.of(s.loans),
  projects: List.of(s.projects),
);

/// Expected domain state for a fixture snapshot, mirroring the store's
/// date-descending transaction order (load() always sorts).
DomainData _expectedFrom(Snapshot snap) {
  final txns = List.of(snap.transactions)
    ..sort((a, b) => b.date.compareTo(a.date));
  return DomainData(
    categories: snap.categories,
    transactions: txns,
    loans: snap.loans,
    projects: snap.projects,
  );
}

/// Mirrors the store's fuel upgrade (legacy loads insert Fuel before Other),
/// so expectations match migrated state for pre-fuel fixtures.
Snapshot _withFuelUpgrade(Snapshot snap) {
  final cats = List.of(snap.categories);
  if (cats.isNotEmpty && cats.every((c) => c.id != 'fuel')) {
    const fuel = Category(id: 'fuel', name: 'Fuel', icon: 0, color: 0xFF795548);
    final at = cats.indexWhere((c) => c.id == 'other');
    if (at < 0) {
      cats.add(fuel);
    } else {
      cats.insert(at, fuel);
    }
  }
  return Snapshot(
    version: snap.version,
    updatedAt: snap.updatedAt,
    deviceId: snap.deviceId,
    deviceName: snap.deviceName,
    categories: cats,
    transactions: snap.transactions,
    loans: snap.loans,
    projects: snap.projects,
  );
}

/// File-backed backend without subdirectories: on Windows an awaited
/// database close can still hold a directory handle briefly, so each test
/// uses one file directly in systemTemp (deleted with retries on dispose).
/// Reopen via [relaunch] models a second app launch on the same file.
class _TempDb {
  DriftDomainStore backend;
  final File file;
  _TempDb._(this.backend, this.file);

  static Future<_TempDb> open(String name) async {
    final file = File('${Directory.systemTemp.path}/dhadda_p2_$name.sqlite');
    for (final suffix in ['', '-journal', '-wal', '-shm']) {
      final f = suffix.isEmpty ? file : File('${file.path}$suffix');
      if (await f.exists()) {
        try {
          await f.delete();
        } catch (_) {}
      }
    }
    return _TempDb._(DriftDomainStore(AppDb(NativeDatabase(file))), file);
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

/// Fails replaceAll while armed, delegates otherwise: simulates a crash
/// before any database write lands.
class _ThrowingBackend implements DomainStore {
  final DomainStore inner;
  bool armed = true;
  _ThrowingBackend(this.inner);

  @override
  Future<void> replaceAll(DomainData data) async {
    if (armed) throw StateError('simulated crash mid-migration');
    return inner.replaceAll(data);
  }

  @override
  Future<Map<String, RecordMeta>> loadRecordMeta() => inner.loadRecordMeta();
  @override
  Future<void> saveRecordMeta(String t, String id, int rev, String by) =>
      inner.saveRecordMeta(t, id, rev, by);
  @override
  Future<List<TombEntry>> loadTombstones() => inner.loadTombstones();
  @override
  Future<void> saveTombstone(TombEntry t) => inner.saveTombstone(t);
  @override
  Future<void> deleteTombstone(String t, String id) =>
      inner.deleteTombstone(t, id);
  @override
  Future<void> resetSyncMeta() => inner.resetSyncMeta();
  @override
  Future<void> applyV2({
    required DomainData data,
    required Map<String, RecordMeta> meta,
    required List<TombEntry> tombs,
  }) => inner.applyV2(data: data, meta: meta, tombs: tombs);

  @override
  Future<Map<String, int>> counts() => inner.counts();
  @override
  Future<void> close() => inner.close();
  @override
  Future<void> deleteLoan(String id) => inner.deleteLoan(id);
  @override
  Future<void> deleteProject(String id) => inner.deleteProject(id);
  @override
  Future<void> deleteTransaction(String id) => inner.deleteTransaction(id);
  @override
  Future<DomainData> loadDomain() => inner.loadDomain();
  @override
  Future<void> saveCategories(List<Category> c) => inner.saveCategories(c);
  @override
  Future<void> saveTransactions(List<Txn> t) => inner.saveTransactions(t);
  @override
  Future<void> upsertLoan(Loan l, {int? rev, String? by}) =>
      inner.upsertLoan(l, rev: rev, by: by);
  @override
  Future<void> upsertProject(Project p, {int? rev, String? by}) =>
      inner.upsertProject(p, rev: rev, by: by);
  @override
  Future<void> upsertTransaction(Txn t, {int? rev, String? by}) =>
      inner.upsertTransaction(t, rev: rev, by: by);
}

DomainData _synthetic(int n) => DomainData(
  categories: const [
    Category(id: 'c0', name: 'C0', icon: 0, color: 0xFF000000),
    Category(id: 'other', name: 'Other', icon: 0, color: 0xFF000000),
  ],
  transactions: [
    for (var i = 0; i < n; i++)
      Txn(
        id: 's-$i',
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

/// Fails exactly the named DomainStore ops, delegates the rest: proves
/// persist-or-revert semantics without touching real failure modes.
class _FailingBackend implements DomainStore {
  final DomainStore inner;
  final Set<String> failOps;
  _FailingBackend(this.inner, this.failOps);

  void _maybe(String op) {
    if (failOps.contains(op)) throw StateError('injected $op failure');
  }

  @override
  Future<void> replaceAll(DomainData d) async {
    _maybe('replaceAll');
    return inner.replaceAll(d);
  }

  @override
  Future<void> saveCategories(List<Category> c) async {
    _maybe('saveCategories');
    return inner.saveCategories(c);
  }

  @override
  Future<void> saveTransactions(List<Txn> t) async {
    _maybe('saveTransactions');
    return inner.saveTransactions(t);
  }

  @override
  Future<void> upsertTransaction(Txn t, {int? rev, String? by}) async {
    _maybe('upsertTransaction');
    return inner.upsertTransaction(t, rev: rev, by: by);
  }

  @override
  Future<void> deleteTransaction(String id) async {
    _maybe('deleteTransaction');
    return inner.deleteTransaction(id);
  }

  @override
  Future<void> upsertLoan(Loan l, {int? rev, String? by}) async {
    _maybe('upsertLoan');
    return inner.upsertLoan(l, rev: rev, by: by);
  }

  @override
  Future<void> deleteLoan(String id) async {
    _maybe('deleteLoan');
    return inner.deleteLoan(id);
  }

  @override
  Future<void> upsertProject(Project p, {int? rev, String? by}) async {
    _maybe('upsertProject');
    return inner.upsertProject(p, rev: rev, by: by);
  }

  @override
  Future<void> deleteProject(String id) async {
    _maybe('deleteProject');
    return inner.deleteProject(id);
  }

  @override
  Future<Map<String, int>> counts() => inner.counts();
  @override
  Future<DomainData> loadDomain() => inner.loadDomain();
  @override
  Future<void> close() => inner.close();
  @override
  Future<Map<String, RecordMeta>> loadRecordMeta() => inner.loadRecordMeta();
  @override
  Future<void> saveRecordMeta(String t, String id, int rev, String by) =>
      inner.saveRecordMeta(t, id, rev, by);
  @override
  Future<List<TombEntry>> loadTombstones() => inner.loadTombstones();
  @override
  Future<void> saveTombstone(TombEntry t) => inner.saveTombstone(t);
  @override
  Future<void> deleteTombstone(String t, String id) =>
      inner.deleteTombstone(t, id);
  @override
  Future<void> resetSyncMeta() => inner.resetSyncMeta();
  @override
  Future<void> applyV2({
    required DomainData data,
    required Map<String, RecordMeta> meta,
    required List<TombEntry> tombs,
  }) => inner.applyV2(data: data, meta: meta, tombs: tombs);
}

/// Seeds the populated fixture through a working backend; returns the temp
/// DB (marker set in the shared mock prefs) and its summary.
Future<(_TempDb, DomainSummary)> _seedPopulated(String name) async {
  final raw = jsonDecode(_fixture('snapshot_populated.json'));
  SharedPreferences.setMockInitialValues({
    _kCats: jsonEncode(raw['categories']),
    _kTxns: jsonEncode(raw['transactions']),
    _kLoans: jsonEncode(raw['loans']),
    _kProjects: jsonEncode(raw['projects']),
  });
  final tempDb = await _TempDb.open(name);
  final s = ExpenseStore(domainOverride: tempDb.backend);
  await s.load();
  return (tempDb, _domainOf(s).summarize());
}

void main() {
  test(
    'fresh install seeds, migrates, reloads from DB on 2nd launch',
    () async {
      SharedPreferences.setMockInitialValues({});
      final tempDb = await _TempDb.open('fresh');
      try {
        final a = ExpenseStore(domainOverride: tempDb.backend);
        await a.load();
        expect(
          a.categories.map((c) => c.id),
          containsAll(['food', 'fuel', 'other']),
        );
        expect(a.categories.last.id, 'other');
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getInt(_marker), 1);
        final first = _domainOf(a).summarize();

        final b = ExpenseStore(domainOverride: await tempDb.relaunch());
        await b.load();
        expect(_domainOf(b).summarize().matches(first), isTrue);
      } finally {
        await tempDb.dispose();
      }
    },
  );

  test('populated legacy migrates with identical meaning, keys kept', () async {
    final raw = jsonDecode(_fixture('snapshot_populated.json'));
    final catsRaw = jsonEncode(raw['categories']);
    final txnsRaw = jsonEncode(raw['transactions']);
    final loansRaw = jsonEncode(raw['loans']);
    final projectsRaw = jsonEncode(raw['projects']);
    SharedPreferences.setMockInitialValues({
      _kCats: catsRaw,
      _kTxns: txnsRaw,
      _kLoans: loansRaw,
      _kProjects: projectsRaw,
    });
    final tempDb = await _TempDb.open('populated');
    try {
      final a = ExpenseStore(domainOverride: tempDb.backend);
      await a.load();
      final snap = Snapshot.decode(_fixture('snapshot_populated.json'));
      final expected = _expectedFrom(snap);
      expect(_domainOf(a).summarize().matches(expected.summarize()), isTrue);
      expect(a.pendingLoansTotal, 4000);
      expect(a.pendingBorrowedTotal, 6000);
      // Marker set, legacy source keys preserved byte-identical.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(_marker), 1);
      expect(prefs.getString(_kCats), catsRaw);
      expect(prefs.getString(_kTxns), txnsRaw);
      expect(prefs.getString(_kLoans), loansRaw);
      expect(prefs.getString(_kProjects), projectsRaw);
      // Reloading the same instance is stable (no duplication).
      await a.load();
      expect(_domainOf(a).summarize().matches(expected.summarize()), isTrue);
      expect((await tempDb.backend.counts())['transactions'], 8);
    } finally {
      await tempDb.dispose();
    }
  });

  test('interrupted migration falls back and retries cleanly', () async {
    final raw = jsonDecode(_fixture('snapshot_populated.json'));
    SharedPreferences.setMockInitialValues({
      _kCats: jsonEncode(raw['categories']),
      _kTxns: jsonEncode(raw['transactions']),
      _kLoans: jsonEncode(raw['loans']),
      _kProjects: jsonEncode(raw['projects']),
    });
    final tempDb = await _TempDb.open('interrupted');
    try {
      final throwing = _ThrowingBackend(tempDb.backend);
      final a = ExpenseStore(domainOverride: throwing);
      await a.load(); // replaceAll throws -> prefs fallback, no marker
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(_marker), isNot(1));
      // In-memory state is still the full legacy state.
      expect(a.transactions, hasLength(8));

      // Retry with a working backend against the intact legacy keys.
      throwing.armed = false;
      final b = ExpenseStore(domainOverride: throwing);
      await b.load();
      expect(prefs.getInt(_marker), 1);
      expect(
        _domainOf(b).summarize().matches(_domainOf(a).summarize()),
        isTrue,
      );
    } finally {
      await tempDb.dispose();
    }
  });

  test('malformed legacy keys refuse migration, retry later', () async {
    const badCats = '{"truncated":';
    const badTxns = '[1,2';
    const badLoans = 'nope';
    SharedPreferences.setMockInitialValues({
      _kCats: badCats,
      _kTxns: badTxns,
      _kLoans: badLoans,
    });
    final tempDb = await _TempDb.open('corrupt');
    try {
      final a = ExpenseStore(domainOverride: tempDb.backend);
      await a.load();
      // Legacy lenient state preserved in memory (as before Phase 2)…
      expect(a.transactions, isEmpty);
      expect(a.loans, isEmpty);
      // …but migration is REFUSED: no marker, legacy bytes untouched.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(_marker), isNot(1));
      expect(prefs.getString(_kCats), badCats);
      expect(prefs.getString(_kTxns), badTxns);
      expect(prefs.getString(_kLoans), badLoans);
      // The session still works on the prefs backend.
      await a.addTransaction(
        type: 'expense',
        amount: 10,
        categoryId: 'food',
        date: DateTime(2026, 9, 6),
      );
      expect(a.transactions, hasLength(1));

      // After the underlying problem is fixed, migration proceeds.
      final raw = jsonDecode(_fixture('snapshot_populated.json'));
      await prefs.setString(_kCats, jsonEncode(raw['categories']));
      await prefs.setString(_kTxns, jsonEncode(raw['transactions']));
      await prefs.setString(_kLoans, jsonEncode(raw['loans']));
      await prefs.setString(_kProjects, jsonEncode(raw['projects']));
      final tempDb2 = await _TempDb.open('corrupt-retry');
      try {
        final b = ExpenseStore(domainOverride: tempDb2.backend);
        await b.load();
        expect(prefs.getInt(_marker), 1);
        expect(b.transactions, hasLength(8));
      } finally {
        await tempDb2.dispose();
      }
    } finally {
      await tempDb.dispose();
    }
  });

  test('wrong top-level legacy types refuse migration', () async {
    SharedPreferences.setMockInitialValues({
      _kCats: '{"a":1}', // valid JSON, wrong type (object, not list)
      _kTxns: '"just-a-string"',
      _kLoans: '42',
      _kProjects: '[]', // valid empty list: fine on its own
    });
    final tempDb = await _TempDb.open('wrongtype');
    try {
      final a = ExpenseStore(domainOverride: tempDb.backend);
      await a.load();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(_marker), isNot(1));
      expect(prefs.getString(_kCats), '{"a":1}');
    } finally {
      await tempDb.dispose();
    }
  });

  test('lenient field-level issues still migrate with defaults', () async {
    SharedPreferences.setMockInitialValues({
      _kCats: jsonEncode([
        {'id': 'food'},
      ]),
      _kTxns: jsonEncode([
        {
          'id': 'len-1',
          'type': 'transfer', // unknown -> expense
          'amount': '100', // non-numeric -> 0
          'date': 'yesterday', // non-int -> now
          'categoryId': 'nope',
          'mode': 'crypto', // unknown passes through
        },
        {'id': 'len-2', 'type': 'income', 'amount': 50, 'date': 1788220800000},
      ]),
      _kLoans: jsonEncode([
        {'id': 'loan-x'},
      ]),
      _kProjects: jsonEncode([]),
    });
    final tempDb = await _TempDb.open('lenient');
    try {
      final a = ExpenseStore(domainOverride: tempDb.backend);
      await a.load();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(_marker), 1);
      expect(a.transactions, hasLength(2));
      expect(a.transactions[0].type, 'expense');
      expect(a.transactions[0].amount, 0);
      expect(a.loans.single.person, '');
      // Reload from the database: same lenient state.
      final b = ExpenseStore(domainOverride: tempDb.backend);
      await b.load();
      expect(b.transactions, hasLength(2));
    } finally {
      await tempDb.dispose();
    }
  });

  test('duplicate IDs refuse migration instead of dropping records', () async {
    const dupTxns =
        '[{"id":"dup-1","type":"expense","amount":10,'
        '"categoryId":"food","date":1788220800000},'
        '{"id":"dup-1","type":"income","amount":50,'
        '"date":1788220800000}]';
    SharedPreferences.setMockInitialValues({
      _kCats: jsonEncode([
        {'id': 'food', 'name': 'Food'},
      ]),
      _kTxns: dupTxns,
    });
    final tempDb = await _TempDb.open('dupids');
    try {
      final a = ExpenseStore(domainOverride: tempDb.backend);
      await a.load();
      // Both records stay visible in the session…
      expect(a.transactions, hasLength(2));
      // …but migration is refused: no marker, source bytes kept.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(_marker), isNot(1));
      expect(prefs.getString(_kTxns), dupTxns);
    } finally {
      await tempDb.dispose();
    }
  });

  test('bulk + legacy + unicode fixtures migrate exactly', () async {
    for (final name in [
      'snapshot_bulk.json',
      'snapshot_legacy.json',
      'snapshot_unicode.json',
      'snapshot_single.json',
    ]) {
      final snap = Snapshot.decode(_fixture(name));
      SharedPreferences.setMockInitialValues({
        _kCats: jsonEncode([for (final c in snap.categories) c.toJson()]),
        _kTxns: jsonEncode([for (final t in snap.transactions) t.toJson()]),
        _kLoans: jsonEncode([for (final l in snap.loans) l.toJson()]),
        _kProjects: jsonEncode([for (final p in snap.projects) p.toJson()]),
      });
      final tempDb = await _TempDb.open(name.replaceAll('.json', ''));
      try {
        final a = ExpenseStore(domainOverride: tempDb.backend);
        final stopwatch = Stopwatch()..start();
        await a.load();
        stopwatch.stop();
        final expected = _expectedFrom(_withFuelUpgrade(snap)).summarize();
        // Legacy fixture: model-level legacy handling (fuel insert,
        // remindFreq) already applied by the legacy load before migration.
        final got = _domainOf(a).summarize();
        if (name == 'snapshot_legacy.json') {
          expect(a.loans.single.remindAt, greaterThan(0), reason: name);
          expect(got.transactionCount, expected.transactionCount, reason: name);
        } else {
          expect(got.matches(expected), isTrue, reason: name);
        }
        expect(stopwatch.elapsed < const Duration(seconds: 60), isTrue);
      } finally {
        await tempDb.dispose();
      }
    }
  });

  test('synthetic 1k/5k replaceAll sanity (timing observation)', () async {
    final tempDb = await _TempDb.open('perf');
    try {
      for (final n in [1000, 5000]) {
        final data = _synthetic(n);
        final stopwatch = Stopwatch()..start();
        await tempDb.backend.replaceAll(data);
        final back = await tempDb.backend.loadDomain();
        stopwatch.stop();
        expect(back.summarize().matches(data.summarize()), isTrue);
        // Generous bound: proves feasibility, not a benchmark.
        expect(stopwatch.elapsed < const Duration(seconds: 60), isTrue);
      }
    } finally {
      await tempDb.dispose();
    }
  });

  test('failed txn add reverts, records error, DB intact', () async {
    final (tempDb, before) = await _seedPopulated('fail-txn');
    try {
      final failing = _FailingBackend(tempDb.backend, {'upsertTransaction'});
      final s = ExpenseStore(domainOverride: failing);
      await s.load();
      expect(s.transactions, hasLength(8));
      final stamp = s.updatedAt;
      await s.addTransaction(
        type: 'expense',
        amount: 999,
        categoryId: 'food',
        date: DateTime(2026, 9, 6),
      );
      // Reverted: no phantom entry, stamp restored, error recorded.
      expect(s.transactions, hasLength(8));
      expect(s.updatedAt, stamp);
      expect(s.lastPersistError, isNotNull);
      // H1 contract: mutations report failure instead of letting the
      // UI claim success over reverted state.
      final okAgain = await s.addTransaction(
        type: 'expense',
        amount: 50,
        categoryId: 'food',
        date: DateTime(2026, 9, 6),
      );
      expect(okAgain, isFalse);
      expect(s.transactions, hasLength(8));
      final okEdit = await s.updateTransaction(
        'txn-0001',
        amount: 123,
      );
      expect(okEdit, isFalse);
      expect(
        s.transactions.firstWhere((t) => t.id == 'txn-0001').amount,
        isNot(123),
      );
      // Reopening is consistent; prior data undamaged.
      final s2 = ExpenseStore(domainOverride: tempDb.backend);
      await s2.load();
      expect(_domainOf(s2).summarize().matches(before), isTrue);
      // A later success clears the recorded error.
      await s2.addTransaction(
        type: 'expense',
        amount: 1,
        categoryId: 'food',
        date: DateTime(2026, 9, 6),
      );
      expect(s2.lastPersistError, isNull);
      expect(s2.transactions, hasLength(9));
    } finally {
      await tempDb.dispose();
    }
  });

  test('failed category/loan/project/delete ops revert cleanly', () async {
    final (tempDb, before) = await _seedPopulated('fail-others');
    try {
      Future<ExpenseStore> failingStore(Set<String> ops) async {
        final s = ExpenseStore(
          domainOverride: _FailingBackend(tempDb.backend, ops),
        );
        await s.load();
        return s;
      }

      var s = await failingStore({'saveCategories'});
      var stamp = s.updatedAt;
      await s.addCategory('Nope');
      expect(s.categories.any((c) => c.name == 'Nope'), isFalse);
      expect(s.updatedAt, stamp);
      expect(s.lastPersistError, isNotNull);

      s = await failingStore({'upsertLoan'});
      stamp = s.updatedAt;
      await s.addLoan(person: 'Ghost', amount: 5, date: DateTime(2026, 9, 6));
      expect(s.loans.any((l) => l.person == 'Ghost'), isFalse);
      expect(s.updatedAt, stamp);

      s = await failingStore({'deleteLoan'});
      stamp = s.updatedAt;
      await s.deleteLoan('loan-0001');
      expect(s.loans.any((l) => l.id == 'loan-0001'), isTrue);
      expect(s.updatedAt, stamp);

      s = await failingStore({'upsertProject'});
      stamp = s.updatedAt;
      await s.addProject('Ghost event', '');
      expect(s.projects.any((p) => p.name == 'Ghost event'), isFalse);
      expect(s.updatedAt, stamp);

      s = await failingStore({'deleteTransaction'});
      stamp = s.updatedAt;
      await s.deleteTransaction('txn-0001');
      expect(s.transactions.any((t) => t.id == 'txn-0001'), isTrue);
      expect(s.updatedAt, stamp);

      // Nothing phantom anywhere; database still the seeded state.
      final s2 = ExpenseStore(domainOverride: tempDb.backend);
      await s2.load();
      expect(_domainOf(s2).summarize().matches(before), isTrue);
    } finally {
      await tempDb.dispose();
    }
  });

  test('failed delete still leaves a durable tombstone (tombstone-first order)', () async {
    final (tempDb, before) = await _seedPopulated('fail-tomb-first');
    expect(before.transactionIds, contains('txn-0001'), reason: 'precondition');
    try {
      // The row delete fails after the tombstone has already been written.
      // That is the safe half-order: the merge converges to deleted either
      // way, whereas the old delete-then-tombstone order left the row gone
      // with nothing recording it, so the next merge re-adopted the record
      // from any peer still holding it and the deletion un-did itself.
      final s = ExpenseStore(
        domainOverride: _FailingBackend(tempDb.backend, {'deleteTransaction'}),
      );
      await s.load();
      await s.deleteTransaction('txn-0001');

      // Memory reverted: the entry is still on screen and lastPersistError
      // is set, so the user is told the save failed.
      expect(s.transactions.any((t) => t.id == 'txn-0001'), isTrue);
      expect(s.lastPersistError, isNotNull);

      // But the deletion itself is durably recorded, which is the whole
      // point: a crash here converges to deleted instead of resurrecting.
      final tombs = await tempDb.backend.loadTombstones();
      expect(tombs.any((t) => t.type == 'txn' && t.id == 'txn-0001'), isTrue);
      // And the row it refers to is still there, so nothing was lost yet.
      final after = await tempDb.backend.loadDomain();
      expect(after.transactions.any((t) => t.id == 'txn-0001'), isTrue);
    } finally {
      await tempDb.dispose();
    }
  });

  test('failed import restores state and says so', () async {
    final (tempDb, before) = await _seedPopulated('fail-import');
    try {
      // A newer snapshot carrying one extra transaction.
      final map = jsonDecode(
        _fixture('snapshot_populated.json'),
      ) as Map<String, dynamic>;
      map['updatedAt'] = '2027-01-01T00:00:00.000Z';
      (map['transactions'] as List).add({
        'id': 'txn-new',
        'type': 'expense',
        'amount': 11,
        'categoryId': 'food',
        'date': 1798761600000,
        'note': 'intruder',
        'mode': 'cash',
        'projectId': '',
      });
      final failing = _FailingBackend(tempDb.backend, {'replaceAll'});
      final s = ExpenseStore(domainOverride: failing);
      await s.load();
      final stamp = s.updatedAt;
      final msg = await s.importSnapshotString(jsonEncode(map));
      expect(msg, 'Could not save the import. Nothing was changed.');
      expect(s.transactions, hasLength(8));
      expect(s.transactions.any((t) => t.id == 'txn-new'), isFalse);
      expect(s.updatedAt, stamp);
      expect(s.lastPersistError, isNotNull);
      // Reopening is consistent with the pre-import state.
      final s2 = ExpenseStore(domainOverride: tempDb.backend);
      await s2.load();
      expect(_domainOf(s2).summarize().matches(before), isTrue);
    } finally {
      await tempDb.dispose();
    }
  });

  test('budgets survive migration, reload, export/import', () async {
    final (tempDb, _) = await _seedPopulated('budgets');
    try {
      Map<String, double> budgets(ExpenseStore s) => {
        for (final c in s.categories) c.id: c.budget,
      };
      final s = ExpenseStore(domainOverride: tempDb.backend);
      await s.load();
      // OLD (prefs JSON) -> DB: food 15000, travel 8000, pets 2000.
      expect(budgets(s), containsPair('food', 15000));
      expect(budgets(s), containsPair('travel', 8000));
      expect(budgets(s), containsPair('pets', 2000));
      // DB reload keeps them.
      final s2 = ExpenseStore(domainOverride: tempDb.backend);
      await s2.load();
      expect(budgets(s2), containsPair('food', 15000));
      // Snapshot v1 export/import round-trip keeps them (same representation).
      final exported = Snapshot.decode(s2.exportJson());
      final byId = {for (final c in exported.categories) c.id: c.budget};
      expect(byId['food'], 15000);
      expect(byId['pets'], 2000);
      SharedPreferences.setMockInitialValues({});
      final rt = await _TempDb.open('budgets-rt');
      try {
        final s3 = ExpenseStore(domainOverride: rt.backend);
        await s3.load();
        expect(
          await s3.importSnapshotString(s2.exportJson(), force: true),
          contains('Synced'),
        );
        expect(budgets(s3), containsPair('travel', 8000));
      } finally {
        await rt.dispose();
      }
    } finally {
      await tempDb.dispose();
    }
  });
}
