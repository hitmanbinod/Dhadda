// Privacy-safe local diagnostics (Phase 7).
//
// A machine-readable + human-readable snapshot of APP HEALTH for debugging,
// with a hard privacy contract: counts, versions, markers, and statuses
// only. Never amounts, notes, names, identifiers, secrets, or contents.
// No analytics, no telemetry, no upload. Builder only: no UI surface yet
// (exposing it would need broader UI work — documented in docs/TESTING.md).
import 'package:flutter/foundation.dart';

import '../store.dart';
import '../version.dart';

/// Keys that may ever appear in a diagnostics report. Anything else is a
/// privacy bug by construction (see diagnostics_test.dart).
const kDiagnosticsKeys = {
  'appVersion',
  'buildStamp',
  'platform',
  'dbSchemaVersion',
  'migrated',
  'syncV2',
  'transactions',
  'categories',
  'loans',
  'projects',
  'tombstones',
  'revisions',
  'lanServing',
  'generatedAt',
};

class DiagnosticsReport {
  /// Builds the report. All inputs are counts/flags/versions; passing
  /// financial content is impossible by signature (only ints/bools/strings
  /// of version constants flow in).
  static Map<String, Object> collect({
    required ExpenseStore store,
    required int dbSchemaVersion,
    required bool migrated,
    required bool syncV2,
    bool lanServing = false,
  }) {
    return {
      'appVersion': kAppVersion,
      'buildStamp': kBuildStamp,
      'platform': kIsWeb ? 'web' : 'native',
      'dbSchemaVersion': dbSchemaVersion,
      'migrated': migrated,
      'syncV2': syncV2,
      'transactions': store.transactions.length,
      'categories': store.categories.length,
      'loans': store.loans.length,
      'projects': store.projects.length,
      'tombstones': store.tombstoneCount,
      'revisions': store.revisionCount,
      'lanServing': lanServing,
      'generatedAt': DateTime.now().toUtc().toIso8601String(),
    };
  }

  /// Human-readable lines. Refuses unknown keys (fail-closed privacy).
  static String format(Map<String, Object> report) {
    final unknown = report.keys
        .where((k) => !kDiagnosticsKeys.contains(k))
        .toList();
    if (unknown.isNotEmpty) {
      throw ArgumentError('non-reportable keys: $unknown');
    }
    final buf = StringBuffer('Dhadda diagnostics\n');
    for (final k in kDiagnosticsKeys) {
      if (report.containsKey(k)) buf.writeln('$k: ${report[k]}');
    }
    return buf.toString();
  }
}
