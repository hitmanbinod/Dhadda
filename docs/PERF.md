# Dhadda Performance Notes (Phase 6)

Comparative engineering measurements, not guarantees. Environment for
all numbers below: author Windows PC, `flutter test` debug VM,
Drift in-memory SQLite (`NativeDatabase.memory`), seeded synthetic
datasets (`benchmark/store_bench_test.dart`, `Random(1234)`, no real
data). Release-mode phones differ; treat deltas as directional.

Commands:

```text
flutter test benchmark/store_bench_test.dart
flutter test benchmark/store_bench_test.dart \
  --dart-define=PERF_SIZES=1000,5000,20000,50000
```

`benchmark/` is outside `test/`, so default CI (`flutter test`) never
runs it. There are no CI timing thresholds.

## 1. Baseline (before changes)

| op (mean) | 1k | 5k | 20k | 50k |
|---|---|---|---|---|
| loadDomain (full SQLite re-read) | 8.65ms | 34.83ms | 143.75ms | 359.51ms |
| dashboard aggregates (3× scan) | 27.82ms | 136.99ms | 545.38ms | 1375.16ms |
| history filter+search scan | 0.65ms | 1.35ms | 7.76ms | 14.78ms |
| add transaction (upsert+resort+notify) | 1.37ms | 1.41ms | 4.07ms | 9.92ms |
| Snapshot v1 export encode | 3.52ms | 16.62ms | 69.40ms | 207.15ms |
| counts() | ~1ms | ~1ms | ~1ms | ~1ms |

## 2. Bottleneck found

Dashboard aggregates dominated: `monthSpend`/`monthIncome`/
`spendByCategory` each re-scanned all transactions and constructed a
`DateTime` per row per call, on **every** Home build (three full
scans + 3N allocations). 1.4s per rebuild at 50k — the only cost on
a UI-critical path that scales catastrophically.

Everything else measured acceptable for its trigger frequency:
history filter is debounced (15ms at 50k), add/resort is 10ms at
50k, export is an explicit user action, startup load is required for
correctness (see §5).

## 3. Change: memoized single-pass analytics

- New `lib/analytics.dart`: `computeMonthlyAnalytics` — one pass,
  epoch-millis month window, no per-row `DateTime` construction.
  Membership, per-subset addition order, and map insertion order are
  identical to the old code by construction (see file header).
- `ExpenseStore` keeps its public API (`monthSpend`, `monthIncome`,
  `spendByCategory`, `monthTxns`) and adds `monthly()` memoized on
  `updatedAt` (touched by every data mutation; settings-only
  rebuilds reuse the cache). `spendByCategory` returns a fresh copy
  so callers cannot mutate the cache.
- Equivalence: `test/analytics_test.dart` (7 tests) checks the new
  implementation against an independent naive DateTime reference —
  bit-exact sums, key order — over empty/single/boundary/rollover/
  leap/populated/unicode/5k-synthetic datasets, plus memo
  hit/invalidation behavior on a real store.

## 4. After

| op (mean) | 1k | 5k | 20k | 50k | verdict |
|---|---|---|---|---|---|
| dashboard aggregates (steady state) | 0.01ms | 0.00ms | 0.00ms | 0.00ms | improved |
| dashboard cold compute (per data change) | 0.16ms | 0.17ms | 0.40ms | 0.70ms | improved (~2000× at 50k) |
| loadDomain | unchanged | unchanged | unchanged | ~430ms | unchanged/acceptable |
| history filter+search | unchanged | unchanged | unchanged | ~17ms | unchanged/acceptable |
| add transaction | unchanged | unchanged | unchanged | ~12ms | unchanged/acceptable |
| export v1 | unchanged | unchanged | unchanged | ~229ms | unchanged/acceptable |

## 5. Deliberately deferred (measured, not guessed)

- **DB-backed async aggregates**: memoization solved the rebuild
  storm without async UI surgery; SQL aggregation stays an option if
  cold compute ever matters (sub-ms today). Web keeps working
  unchanged behind the same sync API.
- **History pagination**: filter is 15–17ms debounced at 50k and
  rendering is already windowed (`ListView.builder`); materializing
  the filtered list is not the bottleneck. No DB paging added.
- **Index changes**: none — no new DB queries were introduced; the
  existing date/category/project indexes already cover the
  month/filter/project paths.
- **Provider watch restructuring**: per-notify recompute is now a
  cache-hit lookup; no mechanical `watch`→`select` conversion.
- **Lazy startup loading**: the full in-memory working set is
  required by sync/export/v2 correctness; 360–430ms at 50k stands.
- **Isolates**: nothing CPU-bound remains on UI paths that justifies
  isolate complexity.

## 6. Memory observations

Working set intentionally duplicates rows (SQLite + in-memory
models) because sync/export/v2 operate on full logical state. No
unbounded caches found (5 rolling backups, 500 SMS-ID cap, tiny
one-entry analytics memo). No listener/controller leaks introduced;
no new caches added.

## 7. Remaining bottlenecks / future work

- 50k Snapshot v1 export (~230ms) and full reload (~430ms) are linear
  and acceptable; revisit only with real-user large histories.
- On-device release-mode numbers were not captured in this phase;
  the harness runs on any `flutter test` host for comparison.
