// Phase 6 benchmarks: deterministic synthetic datasets, comparative timings.
//
// Run (default 1k, fast enough to document the command):
//   flutter test benchmark/store_bench_test.dart
// Maintainer full sweep (NOT CI):
//   flutter test benchmark/store_bench_test.dart \
//     --dart-define=PERF_SIZES=1000,5000,20000,50000
//
// This directory is intentionally outside test/, so plain `flutter test`
// (CI) never runs it. No real data: seeded Random only.
// Numbers are comparative engineering measurements on the author's machine,
// not guarantees. Methodology: warmup iters, then timed iters, mean reported.
// ignore_for_file: avoid_print, invalid_use_of_visible_for_testing_member
import 'dart:math';

import 'package:drift/native.dart';
import 'package:expense/analytics.dart';
import 'package:expense/data/app_db.dart';
import 'package:expense/data/domain_store.dart';
import 'package:expense/data/drift_domain_store.dart';
import 'package:expense/models.dart';
import 'package:expense/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _catIds = [
  'food',
  'travel',
  'fuel',
  'rent',
  'shopping',
  'bills',
  'health',
  'other',
];
const _modes = ['cash', 'bank', 'card', 'ewallet'];
const _words = [
  'tea',
  'lunch',
  'bus',
  'rent',
  'groceries',
  'fuel',
  'medicine',
  'books',
  'repairs',
  'gift',
  'चिया',
  'खाजा',
  '☕',
];

/// Deterministic synthetic domain: N txns spread over ~24 months.
DomainData buildDataset(int n) {
  final rnd = Random(1234);
  final base = DateTime(2024, 1, 1).millisecondsSinceEpoch;
  const day = 24 * 3600 * 1000;
  final txns = <Txn>[
    for (var i = 0; i < n; i++)
      Txn(
        id: 'bench-txn-$i',
        type: rnd.nextDouble() < 0.8 ? 'expense' : 'income',
        amount: (rnd.nextInt(200000) + 1) / 100.0,
        categoryId: _catIds[i % _catIds.length],
        date: base + rnd.nextInt(730) * day + rnd.nextInt(day),
        note: '${_words[i % _words.length]} #$i',
        mode: _modes[i % _modes.length],
        projectId: i % 25 == 0 ? 'bench-proj' : '',
      ),
  ];
  // Newest-first, matching ExpenseStore's in-memory order.
  txns.sort((a, b) => b.date.compareTo(a.date));
  return DomainData(
    categories: [
      for (var i = 0; i < _catIds.length; i++)
        Category(id: _catIds[i], name: _catIds[i], icon: 0, color: 0xFF607D8B),
    ],
    transactions: txns,
    loans: const [],
    projects: const [],
  );
}

Future<DriftDomainStore> openBenchDb() async {
  final backend = DriftDomainStore(AppDb(NativeDatabase.memory()));
  addTearDown(backend.close);
  return backend;
}

/// Mean milliseconds over [iters] runs after [warmup] untimed runs.
Future<double> timeIt(
  Future<void> Function() fn, {
  int warmup = 3,
  int iters = 10,
}) async {
  for (var i = 0; i < warmup; i++) {
    await fn();
  }
  final sw = Stopwatch()..start();
  for (var i = 0; i < iters; i++) {
    await fn();
  }
  sw.stop();
  return sw.elapsedMicroseconds / 1000.0 / iters;
}

double timeItSync(void Function() fn, {int warmup = 3, int iters = 10}) {
  for (var i = 0; i < warmup; i++) {
    fn();
  }
  final sw = Stopwatch()..start();
  for (var i = 0; i < iters; i++) {
    fn();
  }
  sw.stop();
  return sw.elapsedMicroseconds / 1000.0 / iters;
}

void report(int n, String op, double ms, {String unit = 'ms'}) =>
    print('PERF n=$n op=$op mean=${ms.toStringAsFixed(2)}$unit');

/// History-screen predicate, copied semantics (type/cat/day/query).
int historyFilter(List<Txn> all, Map<String, String> catNames) {
  const type = 'all';
  const cat = 'all';
  const query = 'tea';
  var hits = 0;
  final q = query.toLowerCase();
  for (final t in all) {
    if (type != 'all' && t.type != type) continue;
    if (cat != 'all' && t.categoryId != cat) continue;
    final c = (catNames[t.categoryId] ?? '').toLowerCase();
    if (!t.note.toLowerCase().contains(q) &&
        !c.contains(q) &&
        !t.mode.contains(q)) {
      continue;
    }
    hits++;
  }
  return hits;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final sizes = const String.fromEnvironment('PERF_SIZES', defaultValue: '1000')
      .split(',')
      .map((s) => int.tryParse(s.trim()) ?? 0)
      .where((n) => n > 0)
      .toList();

  for (final n in sizes) {
    test('bench n=$n', () async {
      // Pretend the Phase 2 migration already ran, so ExpenseStore.load()
      // takes the database path instead of migrating (empty) legacy keys
      // over the seeded backend.
      SharedPreferences.setMockInitialValues({'expense_db_migrated_v1': 1});
      final data = buildDataset(n);
      final backend = await openBenchDb();
      await backend.replaceAll(data);

      // Fewer iters at large N to keep the sweep practical.
      final iters = n <= 5000 ? 10 : 3;

      // 1. Startup proxy: full domain reload from SQLite.
      report(
        n,
        'loadDomain',
        await timeIt(() async {
          await backend.loadDomain();
        }, iters: iters),
      );

      // 2. Real store over the Drift backend (in-memory analytics path).
      final store = ExpenseStore(domainOverride: backend);
      await store.load();
      // Guard against silently benchmarking an empty store.
      expect(store.transactions.length, n);
      final month = DateTime(2025, 6, 1);
      report(
        n,
        'dashboard_aggregates',
        timeItSync(() {
          store.monthSpend(month);
          store.monthIncome(month);
          store.spendByCategory(month);
        }, iters: iters),
      );

      // 3. Cold compute: rotating months defeat the memo, measuring the
      // single-pass implementation itself (what a data change costs).
      var coldI = 0;
      report(
        n,
        'dashboard_compute_cold',
        timeItSync(() {
          coldI++;
          computeMonthlyAnalytics(
            store.transactions,
            DateTime(2024 + (coldI % 3), (coldI % 12) + 1, 1),
          );
        }, iters: iters),
      );

      // 4. History filter + search scan over the working set.
      final catNames = {for (final c in data.categories) c.id: c.name};
      report(
        n,
        'history_filter_search',
        timeItSync(() {
          historyFilter(store.transactions, catNames);
        }, iters: iters),
      );

      // 4. Add-transaction latency (upsert + resort + notify, no listeners).
      var addI = 0;
      report(
        n,
        'add_txn',
        await timeIt(() async {
          addI++;
          await store.addTransaction(
            type: 'expense',
            amount: 10,
            categoryId: 'food',
            date: DateTime(2025, 6, 15, 12, 0).add(Duration(seconds: addI)),
            note: 'bench-add $addI',
          );
        }, iters: n <= 5000 ? 10 : 3),
      );

      // 5. Snapshot v1 export generation.
      report(
        n,
        'export_v1_json',
        timeItSync(() {
          store.exportJson();
        }, iters: iters),
      );

      // 6. Backend row counts.
      report(
        n,
        'counts',
        await timeIt(() async {
          await backend.counts();
        }, iters: iters),
      );
    });
  }
}
