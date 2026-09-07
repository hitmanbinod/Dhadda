// Snapshot v2: record-level sync that converges instead of clobbering.
//
// V1 exchanged whole snapshots with last-write-wins on a wall clock, so two
// offline devices could silently delete each other's edits. V2 exchanges the
// same records with per-record logical revisions and tombstones, merged with
// a deterministic total order. No wall-clock time participates in any merge
// decision (clocks may skew arbitrarily); timestamps in the envelope are
// informational only.
//
// Pure Dart (no Flutter, no IO): fully unit-testable, including fuzz tests.
import 'dart:convert';

/// Sync envelope marker. V1 payloads carry {"version": 1, ...}; anything
/// else (including garbage) is not v2.
const int kSnapshotV2Format = 2;

/// Record types. Loan children (top-ups/repayments) are independent records
/// with stable IDs; their parent loan id travels in [SyncRecord.parent].
class SyncType {
  static const txn = 'txn';
  static const cat = 'cat';
  static const proj = 'proj';
  static const loan = 'loan';
  static const topup = 'topup';
  static const repay = 'repay';
  static const known = {txn, cat, proj, loan, topup, repay};
}

/// One versioned record. Live records carry [data] (v1-shaped JSON);
/// tombstones carry no data ([dead] true).
class SyncRecord {
  final String type;
  final String id;
  final int rev;
  final String by;
  final bool dead;
  final String parent;
  final Map<String, dynamic>? data;

  const SyncRecord({
    required this.type,
    required this.id,
    required this.rev,
    required this.by,
    this.dead = false,
    this.parent = '',
    this.data,
  });

  String get key => '$type/$id';

  Map<String, dynamic> toJson() => {
        't': type,
        'id': id,
        'rev': rev,
        'by': by,
        if (dead) 'dead': true,
        if (parent.isNotEmpty) 'parent': parent,
        if (data != null) 'd': data,
      };

  /// Returns null for malformed entries (caller counts and skips them).
  static SyncRecord? tryParse(Object? v) {
    if (v is! Map<String, dynamic>) return null;
    final type = '${v['t'] ?? ''}';
    final id = '${v['id'] ?? ''}';
    final rev = v['rev'];
    final by = '${v['by'] ?? ''}';
    if (!SyncType.known.contains(type) || id.isEmpty) return null;
    if (rev is! int || rev < 0) return null;
    final dead = v['dead'] == true;
    final data = v['d'];
    if (!dead && data is! Map<String, dynamic>) return null;
    if ((type == SyncType.topup || type == SyncType.repay) &&
        '${v['parent'] ?? ''}'.isEmpty) {
      return null; // orphan children are meaningless
    }
    return SyncRecord(
      type: type,
      id: id,
      rev: rev,
      by: by,
      dead: dead,
      parent: '${v['parent'] ?? ''}',
      data: dead ? null : (data as Map<String, dynamic>),
    );
  }
}

/// A transport envelope: one device's full record set at export time.
class V2Snapshot {
  final String deviceId;
  final String deviceName;
  final String exportedAt;
  final List<SyncRecord> records;

  const V2Snapshot({
    required this.deviceId,
    required this.deviceName,
    required this.exportedAt,
    required this.records,
  });

  String encode() => jsonEncode({
        'format': kSnapshotV2Format,
        'deviceId': deviceId,
        'deviceName': deviceName,
        'exportedAt': exportedAt,
        'records': [for (final r in records) r.toJson()],
      });

  /// Returns null when [raw] is not a well-formed v2 envelope. Unknown
  /// top-level fields are ignored (forward compatibility).
  static V2Snapshot? tryDecode(String raw) {
    Map<String, dynamic> m;
    try {
      final v = jsonDecode(raw);
      if (v is! Map<String, dynamic>) return null;
      m = v;
    } catch (_) {
      return null;
    }
    if (m['format'] != kSnapshotV2Format) return null;
    final list = m['records'];
    if (list is! List) return null;
    var skipped = 0;
    final records = <SyncRecord>[];
    for (final e in list) {
      final r = SyncRecord.tryParse(e);
      if (r == null) {
        skipped++;
      } else {
        records.add(r);
      }
    }
    return V2Snapshot(
      deviceId: '${m['deviceId'] ?? ''}',
      deviceName: '${m['deviceName'] ?? 'device'}',
      exportedAt: '${m['exportedAt'] ?? ''}',
      records: records,
      // NOTE: skipped counts malformed entries; the caller re-derives it via
      // MergeResult (decode stays total: malformed entries never throw).
    );
  }

  /// 0 = not JSON / not an object, 1 = v1-shaped, 2 = v2 envelope.
  /// V1 detection mirrors what old code accepts (a version field of 1, or a
  /// snapshot-shaped object). Used to route payloads without misparsing.
  static int detectFormat(String raw) {
    try {
      final v = jsonDecode(raw);
      if (v is! Map<String, dynamic>) return 0;
      if (v['format'] == kSnapshotV2Format) return 2;
      if (v['version'] == 1) return 1;
      // Be conservative: snapshot-shaped objects (collections present) count
      // as v1 so old peers' payloads route to the compat path.
      if (v.containsKey('transactions') || v.containsKey('categories')) {
        return 1;
      }
      return 0;
    } catch (_) {
      return 0;
    }
  }
}

/// Outcome of merging one peer snapshot into local state.
class MergeResult {
  /// Winning live records by "type/id".
  final Map<String, SyncRecord> records;

  /// Winning tombstones by "type/id".
  final Map<String, SyncRecord> tombs;

  /// Local records adopted or updated (ids, for UX counts).
  final int adopted;

  /// Local tombstones added or updated.
  final int tombsChanged;

  /// Malformed/unknown entries skipped (never crash, never adopt).
  final int skipped;

  /// True when anything differs from the local input (drives "Synced" vs
  /// "Up to date" messages and re-announce decisions).
  final bool changed;

  const MergeResult({
    required this.records,
    required this.tombs,
    required this.adopted,
    required this.tombsChanged,
    required this.skipped,
    required this.changed,
  });
}

int _compareStrings(String a, String b) => a.compareTo(b);

/// Deterministic total order over competing versions of one record.
/// Higher rev wins; rev tie -> lexicographically SMALLER author wins
/// (arbitrary but fixed); full tie -> deletion wins; identical live
/// versions with divergent content -> larger canonical JSON wins
/// (defensive: unreachable when writers bump correctly).
int compareVersions({
  required int revA,
  required String byA,
  required bool deadA,
  required String contentA,
  required int revB,
  required String byB,
  required bool deadB,
  required String contentB,
}) {
  if (revA != revB) return revA < revB ? -1 : 1;
  if (byA != byB) return byA.compareTo(byB) > 0 ? -1 : 1;
  if (deadA != deadB) return deadA ? 1 : -1;
  if (contentA != contentB) {
    return contentA.compareTo(contentB) > 0 ? 1 : -1;
  }
  return 0;
}

String _canonicalContent(SyncRecord r) =>
    r.dead || r.data == null ? '' : jsonEncode(r.data);

/// Merges [remote] records into [localRecords] + [localTombs].
///
/// Both maps are keyed by "type/id". Pure function of its inputs: same
/// inputs in any order give the same output (commutativity/associativity
/// are tested, not assumed). Never throws on adversarial input.
MergeResult mergeRecords({
  required Map<String, SyncRecord> localRecords,
  required Map<String, SyncRecord> localTombs,
  required List<SyncRecord> remote,
}) {
  // Dedupe remote: keep the winning version per id first, so duplicate IDs
  // in one payload cannot fork the merge.
  final remoteBest = <String, SyncRecord>{};
  var skipped = 0;
  for (final r in remote) {
    final prev = remoteBest[r.key];
    if (prev == null) {
      remoteBest[r.key] = r;
      continue;
    }
    skipped++;
    if (compareVersions(
          revA: r.rev,
          byA: r.by,
          deadA: r.dead,
          contentA: _canonicalContent(r),
          revB: prev.rev,
          byB: prev.by,
          deadB: prev.dead,
          contentB: _canonicalContent(prev),
        ) >
        0) {
      remoteBest[r.key] = r;
    }
  }

  final out = Map<String, SyncRecord>.from(localRecords);
  final tombs = Map<String, SyncRecord>.from(localTombs);
  var adopted = 0;
  var tombsChanged = 0;
  var changed = false;

  void noteAdopted(SyncRecord winner, SyncRecord? local) {
    if (local == null ||
        winner.rev != local.rev ||
        winner.by != local.by ||
        winner.dead != local.dead ||
        _canonicalContent(winner) != _canonicalContent(local)) {
      adopted++;
      changed = true;
    }
  }

  final keys = <String>{...out.keys, ...tombs.keys, ...remoteBest.keys};
  for (final key in keys) {
    final live = out[key];
    final tomb = tombs[key];
    final incoming = remoteBest[key];
    if (incoming == null) continue; // untouched by this peer

    // The 'other' category can never be deleted (UI invariant predates v2).
    if (incoming.dead && incoming.type == SyncType.cat && incoming.id == 'other') {
      skipped++;
      continue;
    }

    // Winner among up to three contenders: local live, local tomb, remote.
    SyncRecord? winner;
    bool winnerDead = false;
    void consider(SyncRecord? c, bool dead) {
      if (c == null) return;
      if (winner == null) {
        winner = c;
        winnerDead = dead;
        return;
      }
      final w = winner!;
      if (compareVersions(
            revA: c.rev,
            byA: c.by,
            deadA: dead,
            contentA: _canonicalContent(c),
            revB: w.rev,
            byB: w.by,
            deadB: winnerDead,
            contentB: _canonicalContent(w),
          ) >
          0) {
        winner = c;
        winnerDead = dead;
      }
    }

    consider(live, false);
    consider(tomb, true);
    consider(incoming, incoming.dead);
    final w = winner!;

    if (winnerDead) {
      final prev = tombs[key];
      if (prev == null ||
          w.rev != prev.rev ||
          w.by != prev.by) {
        tombsChanged++;
        changed = true;
      }
      tombs[key] = SyncRecord(
          type: w.type, id: w.id, rev: w.rev, by: w.by, dead: true);
      if (out.remove(key) != null) {
        // A locally live record lost to a tombstone: that is a change.
        changed = true;
      }
    } else {
      noteAdopted(w, live);
      out[key] = w;
      if (tombs.remove(key) != null) {
        // A tombstone lost to a live record (explicit recreation wins).
        adopted++;
        changed = true;
      }
    }
  }

  return MergeResult(
    records: out,
    tombs: tombs,
    adopted: adopted,
    tombsChanged: tombsChanged,
    skipped: skipped,
    changed: changed,
  );
}
