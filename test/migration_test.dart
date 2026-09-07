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
    const fuel =
        Category(id: 'fuel', name: 'Fuel', icon: 0, color: 0xFF795548);
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
    final file =
        File('${Directory.systemTemp.path}/dhadda_p2_$name.sqlite');
    for (final suffix in ['', '-journal', '-wal', '-shm']) {
      final f = suffix.isEmpty ? file : File('${file.path}$suffix');
      if (await f.exists()) {
        try {
          await f.delete();
        } catch (_) {}
      }
    }
    return _TempDb._(
        DriftDomainStore(AppDb(NativeDatabase(file))), file);
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
  Future<void> upsertLoan(Loan l) => inner.upsertLoan(l);
  @override
  Future<void> upsertProject(Project p) => inner.upsertProject(p);
  @override
  Future<void> upsertTransaction(Txn t) => inner.upsertTransaction(t);
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

void main() {
  test('fresh install seeds, migrates, reloads from DB on 2nd launch',
      () async {
    SharedPreferences.setMockInitialValues({});
    final tempDb = await _TempDb.open('fresh');
    try {
      final a = ExpenseStore(domainOverride: tempDb.backend);
      await a.load();
      expect(a.categories.map((c) => c.id),
          containsAll(['food', 'fuel', 'other']));
      expect(a.categories.last.id, 'other');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(_marker), 1);
      final first = _domainOf(a).summarize();

      final b = ExpenseStore(
          domainOverride: await tempDb.relaunch());
      await b.load();
      expect(_domainOf(b).summarize().matches(first), isTrue);
    } finally {
      await tempDb.dispose();
    }
  });

  test('populated legacy migrates with identical meaning, keys kept',
      () async {
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
      expect(_domainOf(a).summarize().matches(expected.summarize()),
          isTrue);
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
      expect(_domainOf(a).summarize().matches(expected.summarize()),
          isTrue);
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
      expect(_domainOf(b).summarize().matches(_domainOf(a).summarize()),
          isTrue);
    } finally {
      await tempDb.dispose();
    }
  });

  test('corrupt legacy keys migrate to empty without throwing', () async {
    SharedPreferences.setMockInitialValues({
      _kCats: '{"truncated":',
      _kTxns: '[1,2',
      _kLoans: 'nope',
    });
    final tempDb = await _TempDb.open('corrupt');
    try {
      final a = ExpenseStore(domainOverride: tempDb.backend);
      await a.load();
      expect(a.transactions, isEmpty);
      expect(a.loans, isEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(_marker), 1);
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
      final tempDb = await _TempDb.open(
          name.replaceAll('.json', ''));
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
          expect(got.transactionCount, expected.transactionCount,
              reason: name);
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
}
