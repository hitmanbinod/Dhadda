// SharedPreferences backend: the exact Phase 0/1 JSON behavior, kept for
// Flutter Web (which never opens SQLite) and as the degraded fallback when
// the native database cannot be opened. One prefs key per collection, same
// keys and shapes the app has always used.
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';
import 'domain_store.dart';

class PrefsDomainStore implements DomainStore {
  static const kCats = 'expense_cats_v1';
  static const kTxns = 'expense_txns_v1';
  static const kLoans = 'expense_loans_v1';
  static const kProjects = 'expense_projects_v1';

  /// Phase 4 sync metadata (web + fallback backends). Native stores the
  /// same information in row columns / the tombstones table.
  static const kRevs = 'expense_sync_revs_v1';
  static const kTombs = 'expense_sync_tombs_v1';

  final SharedPreferences prefs;
  PrefsDomainStore(this.prefs);

  @override
  Future<DomainData> loadDomain() async => decodeLegacyDomain(
    cats: prefs.getString(kCats),
    txns: prefs.getString(kTxns),
    loans: prefs.getString(kLoans),
    projects: prefs.getString(kProjects),
  );

  @override
  Future<void> replaceAll(DomainData data) async {
    await prefs.setString(
      kCats,
      jsonEncode([for (final c in data.categories) c.toJson()]),
    );
    await prefs.setString(
      kTxns,
      jsonEncode([for (final t in data.transactions) t.toJson()]),
    );
    await prefs.setString(
      kLoans,
      jsonEncode([for (final l in data.loans) l.toJson()]),
    );
    await prefs.setString(
      kProjects,
      jsonEncode([for (final p in data.projects) p.toJson()]),
    );
  }

  @override
  Future<void> saveCategories(List<Category> categories) async {
    await prefs.setString(
      kCats,
      jsonEncode([for (final c in categories) c.toJson()]),
    );
  }

  @override
  Future<void> saveTransactions(List<Txn> transactions) async {
    await prefs.setString(
      kTxns,
      jsonEncode([for (final t in transactions) t.toJson()]),
    );
  }

  @override
  Future<void> upsertTransaction(Txn txn, {int? rev, String? by}) async {
    final current = (await loadDomain()).transactions;
    final i = current.indexWhere((t) => t.id == txn.id);
    if (i < 0) {
      current.add(txn);
    } else {
      current[i] = txn;
    }
    await saveTransactions(current);
    if (rev != null) {
      await saveRecordMeta('txn', txn.id, rev, by ?? '');
    }
  }

  @override
  Future<void> deleteTransaction(String id) async {
    final current = (await loadDomain()).transactions;
    current.removeWhere((t) => t.id == id);
    await saveTransactions(current);
  }

  @override
  Future<void> upsertLoan(Loan loan, {int? rev, String? by}) async {
    final current = (await loadDomain()).loans;
    final i = current.indexWhere((l) => l.id == loan.id);
    if (i < 0) {
      current.add(loan);
    } else {
      current[i] = loan;
    }
    await prefs.setString(
      kLoans,
      jsonEncode([for (final l in current) l.toJson()]),
    );
    if (rev != null) {
      await saveRecordMeta('loan', loan.id, rev, by ?? '');
    }
  }

  @override
  Future<void> deleteLoan(String id) async {
    final current = (await loadDomain()).loans;
    current.removeWhere((l) => l.id == id);
    await prefs.setString(
      kLoans,
      jsonEncode([for (final l in current) l.toJson()]),
    );
  }

  @override
  Future<void> upsertProject(Project project, {int? rev, String? by}) async {
    final current = (await loadDomain()).projects;
    final i = current.indexWhere((p) => p.id == project.id);
    if (i < 0) {
      current.add(project);
    } else {
      current[i] = project;
    }
    await prefs.setString(
      kProjects,
      jsonEncode([for (final p in current) p.toJson()]),
    );
    if (rev != null) {
      await saveRecordMeta('proj', project.id, rev, by ?? '');
    }
  }

  @override
  Future<void> deleteProject(String id) async {
    final current = (await loadDomain()).projects;
    current.removeWhere((p) => p.id == id);
    await prefs.setString(
      kProjects,
      jsonEncode([for (final p in current) p.toJson()]),
    );
  }

  @override
  Future<Map<String, int>> counts() async {
    final d = await loadDomain();
    return {
      'categories': d.categories.length,
      'transactions': d.transactions.length,
      'loans': d.loans.length,
      'projects': d.projects.length,
    };
  }

  @override
  Future<void> close() async {}

  Map<String, RecordMeta> _readRevs() {
    try {
      final raw = prefs.getString(kRevs);
      if (raw == null || raw.isEmpty) return {};
      final m = jsonDecode(raw);
      if (m is! Map<String, dynamic>) return {};
      final out = <String, RecordMeta>{};
      m.forEach((k, v) {
        if (v is Map<String, dynamic>) {
          try {
            out[k] = RecordMeta.fromJson(v);
          } catch (_) {}
        }
      });
      return out;
    } catch (_) {
      return {};
    }
  }

  @override
  Future<Map<String, RecordMeta>> loadRecordMeta() async => _readRevs();

  @override
  Future<void> saveRecordMeta(
    String type,
    String id,
    int rev,
    String by,
  ) async {
    final map = _readRevs();
    map['$type/$id'] = RecordMeta(rev: rev, by: by);
    await prefs.setString(
      kRevs,
      jsonEncode(map.map((k, v) => MapEntry(k, v.toJson()))),
    );
  }

  @override
  Future<List<TombEntry>> loadTombstones() async {
    try {
      final raw = prefs.getString(kTombs);
      if (raw == null || raw.isEmpty) return [];
      final v = jsonDecode(raw);
      if (v is! List) return [];
      return [
        for (final e in v)
          if (TombEntry.tryParse(e) != null) TombEntry.tryParse(e)!,
      ];
    } catch (_) {
      return [];
    }
  }

  @override
  Future<void> saveTombstone(TombEntry tomb) async {
    final current = await loadTombstones();
    final i = current.indexWhere((t) => t.type == tomb.type && t.id == tomb.id);
    if (i < 0) {
      current.add(tomb);
    } else {
      current[i] = tomb;
    }
    await prefs.setString(
      kTombs,
      jsonEncode([for (final t in current) t.toJson()]),
    );
  }

  @override
  Future<void> deleteTombstone(String type, String id) async {
    final current = await loadTombstones();
    current.removeWhere((t) => t.type == type && t.id == id);
    await prefs.setString(
      kTombs,
      jsonEncode([for (final t in current) t.toJson()]),
    );
  }

  @override
  Future<void> resetSyncMeta() async {
    await prefs.remove(kRevs);
    await prefs.remove(kTombs);
  }

  @override
  Future<void> applyV2({
    required DomainData data,
    required Map<String, RecordMeta> meta,
    required List<TombEntry> tombs,
  }) async {
    await replaceAll(data);
    await prefs.setString(
      kRevs,
      jsonEncode(meta.map((k, v) => MapEntry(k, v.toJson()))),
    );
    await prefs.setString(
      kTombs,
      jsonEncode([for (final t in tombs) t.toJson()]),
    );
  }
}
