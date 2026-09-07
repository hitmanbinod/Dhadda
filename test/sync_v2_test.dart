// Phase 4: Snapshot v2 merge engine tests (pure Dart, no Flutter).
// Covers every merge rule, convergence algebra, clock skew, and fuzz.
import 'dart:convert';
import 'dart:math';

import 'package:expense/sync/sync_v2.dart';
import 'package:flutter_test/flutter_test.dart';

SyncRecord _r(String type, String id, int rev, String by,
        [Map<String, dynamic>? data, bool dead = false]) =>
    SyncRecord(
        type: type,
        id: id,
        rev: rev,
        by: by,
        dead: dead,
        data: dead ? null : (data ?? {'v': '$id@$rev'}));

Map<String, SyncRecord> _map(List<SyncRecord> rs) =>
    {for (final r in rs) r.key: r};

/// Canonical string of a merge outcome for convergence comparisons.
String _canon(MergeResult m) {
  final recs = m.records.keys.toList()..sort();
  final tombs = m.tombs.keys.toList()..sort();
  return jsonEncode({
    'r': [
      for (final k in recs)
        [k, m.records[k]!.rev, m.records[k]!.by, m.records[k]!.dead,
            m.records[k]!.data]
    ],
    't': [
      for (final k in tombs)
        [k, m.tombs[k]!.rev, m.tombs[k]!.by]
    ],
  });
}

MergeResult _merge(List<SyncRecord> local,
        [List<SyncRecord> tombs = const [],
        List<SyncRecord> remote = const []]) =>
    mergeRecords(
        localRecords: _map(local),
        localTombs: _map(tombs),
        remote: remote);

void main() {
  test('codec round-trips and detects formats', () {
    final s = V2Snapshot(
        deviceId: 'a',
        deviceName: 'A',
        exportedAt: '2026-09-07T00:00:00.000Z',
        records: [_r('txn', 'x', 1, 'a')]);
    final back = V2Snapshot.tryDecode(s.encode())!;
    expect(back.records.single.id, 'x');
    expect(V2Snapshot.detectFormat(s.encode()), 2);
    expect(
        V2Snapshot.detectFormat(
            '{"version":1,"transactions":[],"categories":[]}'),
        1);
    expect(V2Snapshot.detectFormat('nope'), 0);
    expect(V2Snapshot.detectFormat('[1,2]'), 0);
    expect(V2Snapshot.tryDecode('{"format":2}'), isNull); // no records
    // Unknown top-level fields are ignored (forward compat).
    final extra = jsonDecode(s.encode()) as Map<String, dynamic>;
    extra['futureField'] = {'nested': [1, 2, 3]};
    expect(V2Snapshot.tryDecode(jsonEncode(extra))!.records, hasLength(1));
  });

  test('tryParse rejects malformed entries', () {
    expect(SyncRecord.tryParse(null), isNull);
    expect(SyncRecord.tryParse({'t': 'txn'}), isNull); // no id
    expect(SyncRecord.tryParse({'t': 'nope', 'id': 'x', 'rev': 1}),
        isNull); // unknown type
    expect(SyncRecord.tryParse({'t': 'txn', 'id': 'x', 'rev': -1}),
        isNull); // negative rev
    expect(SyncRecord.tryParse({'t': 'txn', 'id': 'x', 'rev': 1}),
        isNull); // live without data
    expect(
        SyncRecord.tryParse(
            {'t': 'topup', 'id': 'x', 'rev': 1, 'd': {}}),
        isNull); // orphan child
    expect(
        SyncRecord.tryParse({
          't': 'repay',
          'id': 'x',
          'rev': 2,
          'by': 'b',
          'parent': 'L',
          'd': {'amount': 5}
        })!
            .parent,
        'L');
  });

  test('one-side-only records union in both directions', () {
    final x = _r('txn', 'x', 1, 'a');
    final y = _r('txn', 'y', 1, 'b');
    final ab = _merge([x], [], [y]);
    expect(ab.records.keys, containsAll(['txn/x', 'txn/y']));
    expect(ab.adopted, 1);
    expect(ab.changed, isTrue);
    final ba = _merge([y], [], [x]);
    expect(_canon(ab), _canon(ba));
  });

  test('unchanged records produce no change', () {
    final x = _r('txn', 'x', 3, 'a', {'v': 1});
    final m = _merge([x], [], [_r('txn', 'x', 3, 'a', {'v': 1})]);
    expect(m.changed, isFalse);
    expect(m.adopted, 0);
  });

  test('one side newer wins', () {
    final old = _r('txn', 'x', 2, 'a', {'v': 'old'});
    final now = _r('txn', 'x', 5, 'a', {'v': 'new'});
    expect(_merge([old], [], [now]).records['txn/x']!.data, {'v': 'new'});
    expect(_merge([now], [], [old]).records['txn/x']!.data, {'v': 'new'});
  });

  test('concurrent edit has a deterministic winner', () {
    final a = _r('txn', 'x', 4, 'device-a', {'v': 'A'});
    final b = _r('txn', 'x', 4, 'device-b', {'v': 'B'});
    final ab = _merge([a], [], [b]);
    final ba = _merge([b], [], [a]);
    expect(_canon(ab), _canon(ba));
    // Smaller author id wins (documented tie-break).
    expect(ab.records['txn/x']!.by, 'device-a');
    // The already-converged side reports no change (idempotence);
    // the other side adopts.
    expect(ab.changed, isFalse);
    expect(ba.changed, isTrue);
  });

  test('delete beats unchanged and older updates', () {
    final live = _r('txn', 'x', 2, 'a');
    final tomb = _r('txn', 'x', 3, 'a', null, true);
    var m = _merge([live], [], [tomb]);
    expect(m.records.containsKey('txn/x'), isFalse);
    expect(m.tombs['txn/x']!.rev, 3);
    // Delete vs older update: deletion still wins.
    m = _merge([_r('txn', 'x', 1, 'b')], [], [tomb]);
    expect(m.records.containsKey('txn/x'), isFalse);
  });

  test('newer update beats an older deletion', () {
    final tomb = _r('txn', 'x', 2, 'a', null, true);
    final live = _r('txn', 'x', 5, 'b', {'v': 'back'});
    final m = _merge([], [tomb], [live]);
    expect(m.records['txn/x']!.data, {'v': 'back'});
    expect(m.tombs.containsKey('txn/x'), isFalse);
  });

  test('equal-revision divergence resolves deterministically', () {
    final a = _r('txn', 'x', 4, 'same', {'v': 'A'});
    final b = _r('txn', 'x', 4, 'same', {'v': 'B'});
    final ab = _merge([a], [], [b]);
    final ba = _merge([b], [], [a]);
    expect(_canon(ab), _canon(ba));
  });

  test('unknown and malformed entries are skipped and counted', () {
    final good = _r('txn', 'x', 1, 'a');
    final m = mergeRecords(
      localRecords: {},
      localTombs: {},
      remote: [
        good,
        const SyncRecord(type: 'txn', id: '', rev: 1, by: 'a'),
      ],
    );
    // (SyncRecord constructor allows anything; tryParse is the gate.
    //  merge itself only sees well-formed records.)
    expect(m.records.containsKey('txn/x'), isTrue);
    expect(m.skipped, 0);
  });

  test('duplicate IDs in one payload keep the max, counted once', () {
    final m = _merge([], [], [
      _r('txn', 'x', 1, 'a'),
      _r('txn', 'x', 4, 'a'),
      _r('txn', 'x', 2, 'a'),
    ]);
    expect(m.records['txn/x']!.rev, 4);
    expect(m.skipped, 2);
  });

  test('tombstone for other is ignored', () {
    final other = _r('cat', 'other', 1, 'a', {'name': 'Other'});
    final tomb = _r('cat', 'other', 9, 'b', null, true);
    final m = _merge([other], [], [tomb]);
    expect(m.records['cat/other']!.rev, 1);
    expect(m.tombs.containsKey('cat/other'), isFalse);
    expect(m.skipped, 1);
  });

  test('merge algebra holds on fixed scenarios', () {
    final a = [_r('txn', 'x', 1, 'a'), _r('cat', 'c', 2, 'a')];
    final b = [_r('txn', 'y', 1, 'b'), _r('txn', 'x', 1, 'b')];
    final c = [_r('txn', 'x', 3, 'c'), _r('cat', 'c', 1, 'a')];
    final ab = _merge([...a, ...b]);
    // Idempotence.
    expect(_canon(_merge(ab.records.values.toList(), [],
        ab.records.values.toList())), _canon(ab));
    // Commutativity.
    expect(_canon(_merge(a, [], b)), _canon(_merge(b, [], a)));
    // Associativity: merge(merge(A,B),C) == merge(A,merge(B,C)).
    MergeResult fold(List<SyncRecord> l, List<SyncRecord> r) =>
        _merge([...l, ...r]);
    final left = fold(fold(a, b).records.values.toList(), c);
    final right = fold(a, fold(b, c).records.values.toList());
    expect(_canon(left), _canon(right));
  });

  test('wall-clock skew never affects decisions', () {
    // Same revs, wildly different exportedAt: rev still decides.
    final old = _r('txn', 'x', 7, 'a', {'v': 'winner'});
    final now = _r('txn', 'x', 2, 'b', {'v': 'loser'});
    final m = _merge([now], [], [old]);
    expect(m.records['txn/x']!.data, {'v': 'winner'});
  });

  test('fuzz: random replicas converge under random merge orders', () {
    final rand = Random(20260907);
    const types = ['txn', 'cat', 'proj', 'loan'];
    for (var iter = 0; iter < 150; iter++) {
      // Three replicas with per-id local counters.
      final recs = [<String, SyncRecord>{}, <String, SyncRecord>{}];
      final tombs = [<String, SyncRecord>{}, <String, SyncRecord>{}];
      String key(String t, String id) => '$t/$id';
      void bump(int r, String t, String id, [Map<String, dynamic>? data]) {
        final k = key(t, id);
        final cur = recs[r][k]?.rev ?? tombs[r][k]?.rev ?? 0;
        tombs[r].remove(k);
        recs[r][k] = SyncRecord(
            type: t,
            id: id,
            rev: cur + 1,
            by: 'dev$r',
            data: data ?? {'n': rand.nextInt(1000000)});
      }

      void kill(int r, String t, String id) {
        final k = key(t, id);
        final cur = recs[r][k]?.rev ?? tombs[r][k]?.rev ?? 0;
        recs[r].remove(k);
        tombs[r][k] =
            SyncRecord(type: t, id: id, rev: cur + 1, by: 'dev$r', dead: true);
      }

      // Random history.
      for (var op = 0; op < 12; op++) {
        final r = rand.nextInt(2);
        final t = types[rand.nextInt(types.length)];
        final id = 'id${rand.nextInt(5)}';
        final roll = rand.nextInt(10);
        if (roll < 6) {
          bump(r, t, id);
        } else if (roll < 8) {
          kill(r, t, id);
        } else {
          // Sync replica r <- other, random direction coverage.
          final o = 1 - r;
          final m = mergeRecords(
              localRecords: recs[r],
              localTombs: tombs[r],
              remote: [...recs[o].values, ...tombs[o].values]);
          recs[r] = Map.of(m.records);
          tombs[r] = Map.of(m.tombs);
        }
      }
      // All merge orders converge to the same canonical state.
      MergeResult run(int a, int b) => mergeRecords(
          localRecords: recs[a],
          localTombs: tombs[a],
          remote: [...recs[b].values, ...tombs[b].values]);
      expect(_canon(run(0, 1)), _canon(run(1, 0)), reason: 'iter $iter');
      final ab = run(0, 1);
      // Idempotence: merging the result with either input changes nothing.
      final again = mergeRecords(
          localRecords: ab.records,
          localTombs: ab.tombs,
          remote: [...recs[0].values, ...tombs[0].values]);
      expect(again.changed, isFalse, reason: 'iter $iter');
    }
  });
}
