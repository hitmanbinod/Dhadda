import 'dart:convert';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/foundation.dart' hide Category;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'format.dart';
import 'data/domain_store.dart';
import 'data/drift_domain_store.dart';
import 'data/prefs_domain_store.dart';
import 'data/test_env.dart';
import 'sync/sync_v2.dart';

/// Local-first store. No backend, no account, no cost.
///
/// Domain data (transactions, categories, loans, projects) persists in SQLite
/// via Drift on Android/desktop and in SharedPreferences JSON on Web; small
/// settings stay in SharedPreferences everywhere (see docs/PERSISTENCE.md).
class ExpenseStore extends ChangeNotifier {
  static const _kCats = 'expense_cats_v1';
  static const _kTxns = 'expense_txns_v1';
  static const _kLoans = 'expense_loans_v1';
  static const _kProjects = 'expense_projects_v1';
  static const _kMeta = 'expense_meta_v1';
  static const _kBackups = 'expense_backups_v1';

  /// Set to 1 once the legacy prefs domain data has been verified inside
  /// SQLite. Absent/0 keeps the legacy keys authoritative. Never deleted.
  static const _kDbMigrated = 'expense_db_migrated_v1';

  /// Set to 1 once per-record sync revisions are initialized. Revisions
  /// default to 0, so initialization writes nothing but this marker.
  static const _kSyncV2 = 'expense_sync_v2_v1';
  static const _uuid = Uuid();

  DomainStore? _domain;
  bool _ownsDomain = false;

  /// Per-record sync revisions, keyed "type/id" (see sync_v2 types).
  /// Absent entries mean rev 0 (pre-v2 baseline).
  Map<String, RecordMeta> _revs = {};

  /// Deletion records, keyed "type/id". Never garbage-collected in Phase 4.
  Map<String, TombEntry> _tombs = {};

  bool _v2ready = false;

  /// True once revision metadata is initialized (always true after [load]).
  bool get v2ready => _v2ready;

  /// Test-only backend injection (unit tests have no native database).
  /// When set, [load] uses it instead of opening SQLite.
  final DomainStore? _domainOverride;

  ExpenseStore({this._domainOverride});

  List<Category> categories = [];
  List<Txn> transactions = [];
  List<Loan> loans = [];
  List<Project> projects = [];

  String deviceId = '';
  String deviceName = kIsWeb ? 'Browser' : 'Device';
  String relayOrigin = '';
  String currency = 'NPR';
  String themeMode = 'system'; // system | light | dark
  int accent = 0xFF009688;
  bool materialYou = false; // wallpaper colours (Android 12+)
  String userName = '';
  String smsMode = 'manual'; // manual | auto
  List<String> smsSenders = [];

  /// Wallpaper seed (ARGB) when Material You is on and available.
  int? dynamicSeedArgb;
  // Persistent link (pair once, stay synced). Empty id = not linked.
  String linkId = '';
  String linkPin = '';
  String linkPeer = '';

  /// High-entropy link secret for the live pairing (Phase 5 closure).
  /// Empty means a legacy PIN-only pairing. Persisted with the other link
  /// fields (app-private sandbox), cleared on unpair/erase.
  String linkSecret = '';
  bool get linked => linkId.isNotEmpty && linkPin.isNotEmpty;
  // Runtime only: human-readable link state for the UI.
  String linkStatus = '';

  static const currencySymbols = {
    'NPR': 'रू',
    'INR': '₹',
    'USD': '\$',
    'EUR': '€',
    'GBP': '£',
    'AUD': 'A\$',
    'CAD': 'C\$',
    'AED': 'AED',
    'JPY': '¥',
    'CNY': '¥',
  };
  static const currencyNames = {
    'NPR': 'Nepali Rupee',
    'INR': 'Indian Rupee',
    'USD': 'US Dollar',
    'EUR': 'Euro',
    'GBP': 'British Pound',
    'AUD': 'Australian Dollar',
    'CAD': 'Canadian Dollar',
    'AED': 'UAE Dirham',
    'JPY': 'Japanese Yen',
    'CNY': 'Chinese Yuan',
  };

  String get currencySymbol => currencySymbols[currency] ?? 'रू';
  String updatedAt = DateTime.fromMillisecondsSinceEpoch(
    0,
    isUtc: true,
  ).toIso8601String();
  String lastSynced = 'never';
  bool loaded = false;

  SharedPreferences? _prefs;

  Future<void> load() async {
    // Reopening (eraseAll, tests): close only backends we opened ourselves.
    // Injected test backends stay open across loads.
    if (_ownsDomain) {
      try {
        await _domain?.close();
      } catch (_) {}
    }
    _domain = null;
    _ownsDomain = false;
    _prefs ??= await SharedPreferences.getInstance();
    final p = _prefs!;
    _readMeta(p);
    dynamicSeedArgb = null;
    if (materialYou) {
      await _refreshDynamicSeed();
    }
    _domain = _domainOverride ?? await _openDomain(p);
    _ownsDomain = _domainOverride == null && _domain is DriftDomainStore;
    if (_domain is! PrefsDomainStore && p.getInt(_kDbMigrated) == 1) {
      await _loadDomainFromStore();
    } else {
      _readLegacyDomain(p);
      if (_domain is! PrefsDomainStore &&
          _legacyDomainReadable(p) &&
          _domainIdsUnique()) {
        await _migrateLegacyToDb(p);
      } else if (_domain is! PrefsDomainStore) {
        // Unreadable legacy bytes: refuse to authorize an empty database.
        // Legacy keys stay untouched so a later launch can retry; this
        // session runs on the same lenient legacy state as before Phase 2.
        debugPrint(
          'Dhadda: legacy domain unreadable or has duplicate '
          'IDs; migration deferred.',
        );
        _domain = PrefsDomainStore(p);
      }
    }
    await _loadSyncMeta();
    await _ensureV2Init(p);
    _sortTxns();
    loaded = true;
    notifyListeners();
  }

  /// Opens SQLite, falling back to the prefs backend when unavailable (unit
  /// tests, broken native lib). The fallback never sets the marker, so a
  /// later launch retries the real database. Unit/widget tests always use
  /// prefs: drift's async machinery does not complete inside testWidgets'
  /// fake-async zone, so attempting a real open there hangs forever.
  Future<DomainStore> _openDomain(SharedPreferences p) async {
    if (!kIsWeb && !isFlutterTest) {
      try {
        return await DriftDomainStore.open();
      } catch (e) {
        debugPrint(
          'Dhadda: SQLite unavailable (${e.runtimeType}); prefs backend for now.',
        );
      }
    }
    return PrefsDomainStore(p);
  }

  Future<void> _loadDomainFromStore() async {
    final d = await _domain!.loadDomain();
    categories = d.categories;
    transactions = d.transactions;
    loans = d.loans;
    projects = d.projects;
  }

  /// Loads revision + tombstone maps from the active backend. Missing
  /// entries mean rev 0 (pre-v2 baseline) — no backfill writes needed.
  Future<void> _loadSyncMeta() async {
    final d = _domain;
    if (d == null) {
      _revs = {};
      _tombs = {};
      _v2ready = false;
      return;
    }
    try {
      _revs = await d.loadRecordMeta();
      final tombs = await d.loadTombstones();
      _tombs = {for (final t in tombs) t.key: t};
    } catch (e) {
      debugPrint(
        'Dhadda: sync metadata unreadable (${e.runtimeType}); baseline.',
      );
      _revs = {};
      _tombs = {};
    }
    _v2ready = false;
  }

  /// One-time revision initialization: deterministic (rev 0 baseline for
  /// everything pre-v2) and stable (marker-gated, never regenerated).
  Future<void> _ensureV2Init(SharedPreferences p) async {
    if (p.getInt(_kSyncV2) == 1) {
      _v2ready = true;
      return;
    }
    try {
      await p.setInt(_kSyncV2, 1);
      _v2ready = true;
    } catch (e) {
      debugPrint('Dhadda: v2 marker unwritable (${e.runtimeType}).');
      _v2ready = false;
    }
  }

  static String _mkey(String type, String id) => '$type/$id';

  RecordMeta _metaFor(String type, String id) =>
      _revs[_mkey(type, id)] ?? const RecordMeta(rev: 0, by: '');

  /// Bumps a record's revision for a local edit. Returns the value to
  /// persist alongside the row (same-statement atomicity on native).
  RecordMeta _bumpRev(String type, String id) {
    final cur = _metaFor(type, id);
    final next = RecordMeta(rev: cur.rev + 1, by: deviceId);
    _revs[_mkey(type, id)] = next;
    return next;
  }

  /// Records a deletion. The tombstone (not the row) is what converges.
  TombEntry _makeTomb(String type, String id) {
    final cur = _metaFor(type, id);
    final tomb = TombEntry(type: type, id: id, rev: cur.rev + 1, by: deviceId);
    _tombs[tomb.key] = tomb;
    _revs.remove(_mkey(type, id));
    return tomb;
  }

  /// Revision for a recreated id (undo-delete): outranks its tombstone,
  /// which is dropped. Falls back to a normal bump when no tombstone exists.
  RecordMeta _reviveRev(String type, String id) {
    final tomb = _tombs.remove(_mkey(type, id));
    final cur = _metaFor(type, id);
    final base = cur.rev > (tomb?.rev ?? -1) ? cur.rev : (tomb?.rev ?? -1);
    final next = RecordMeta(rev: base + 1, by: deviceId);
    _revs[_mkey(type, id)] = next;
    return next;
  }

  /// True when a legacy domain key is absent/empty (clean empty) or holds a
  /// JSON list (decodable; item-level leniency is the parser's own contract).
  /// Malformed JSON or a wrong top-level type is NOT safely migratable.
  bool _legacyKeyReadable(String? raw) {
    if (raw == null || raw.isEmpty) return true;
    try {
      return jsonDecode(raw) is List;
    } catch (_) {
      return false;
    }
  }

  bool _legacyDomainReadable(SharedPreferences p) =>
      _legacyKeyReadable(p.getString(_kCats)) &&
      _legacyKeyReadable(p.getString(_kTxns)) &&
      _legacyKeyReadable(p.getString(_kLoans)) &&
      _legacyKeyReadable(p.getString(_kProjects));

  /// Duplicate IDs decode into lists without complaint, but PRIMARY KEYs
  /// cannot store them without silently dropping records — so they refuse
  /// migration exactly like corrupt input. (UUID collisions are
  /// practically impossible; duplicates imply a hand-edited file.)
  bool _domainIdsUnique() {
    bool uniqueIds(Iterable<String> ids) {
      final seen = <String>{};
      for (final id in ids) {
        if (!seen.add(id)) return false;
      }
      return true;
    }

    if (!uniqueIds([for (final c in categories) c.id])) return false;
    if (!uniqueIds([for (final t in transactions) t.id])) return false;
    if (!uniqueIds([for (final l in loans) l.id])) return false;
    if (!uniqueIds([for (final p in projects) p.id])) return false;
    final topupIds = <String>[];
    final repaymentIds = <String>[];
    for (final l in loans) {
      topupIds.addAll([for (final t in l.topups) t.id]);
      repaymentIds.addAll([for (final r in l.repayments) r.id]);
    }
    return uniqueIds(topupIds) && uniqueIds(repaymentIds);
  }

  /// One-time legacy -> SQLite migration. The source is the in-memory state
  /// built by [_readLegacyDomain] (first-run seeds and the fuel upgrade
  /// included), written in a single transaction and verified by summary
  /// before the marker is set. Legacy prefs keys are never deleted here. Any
  /// failure keeps this launch on the prefs backend; the intact legacy keys
  /// make the next launch retry safely.
  Future<void> _migrateLegacyToDb(SharedPreferences p) async {
    final source = DomainData(
      categories: List.of(categories),
      transactions: List.of(transactions),
      loans: List.of(loans),
      projects: List.of(projects),
    );
    try {
      await _domain!.replaceAll(source);
      final wrote = await _domain!.loadDomain();
      if (!source.summarize().matches(wrote.summarize())) {
        throw StateError('migration verification mismatch');
      }
      await p.setInt(_kDbMigrated, 1);
    } catch (e) {
      debugPrint(
        'Dhadda: DB migration failed, staying on prefs (${e.runtimeType})',
      );
      _domain = PrefsDomainStore(p);
    }
  }

  /// Last domain-write failure, if any (null when the last write
  /// succeeded or none was attempted). Surfaced for tests/diagnostics; the
  /// import path additionally reports through its message string.
  String? lastPersistError;

  DomainData _snapshotDomain() => DomainData(
    categories: List.of(categories),
    transactions: List.of(transactions),
    loans: List.of(loans),
    projects: List.of(projects),
  );

  void _restoreDomain(DomainData snap, String prevUpdatedAt) {
    categories = snap.categories;
    transactions = snap.transactions;
    loans = snap.loans;
    projects = snap.projects;
    updatedAt = prevUpdatedAt;
    _saveAll(); // re-save the restored stamp so prefs meta matches memory
  }

  /// Awaited write-through with revert. [before]/[prevUpdatedAt] must be
  /// captured by the caller BEFORE mutating memory. Revision/tombstone maps
  /// are snapshotted here (mutations bump them before calling). On database
  /// failure everything rolls back, the error is recorded, and listeners are
  /// notified — the UI never shows phantom-saved state. Failures are never
  /// thrown into the UI and never only logged.
  Future<void> _persistDomain(
    DomainData before,
    String prevUpdatedAt,
    Future<void> Function(DomainStore) op,
  ) async {
    final d = _domain;
    if (d == null) return;
    final prevRevs = Map.of(_revs);
    final prevTombs = Map.of(_tombs);
    try {
      await op(d);
      lastPersistError = null;
    } catch (e) {
      _restoreDomain(before, prevUpdatedAt);
      _revs
        ..clear()
        ..addAll(prevRevs);
      _tombs
        ..clear()
        ..addAll(prevTombs);
      lastPersistError = '$e';
      debugPrint('Dhadda: domain persist failed, reverted (${e.runtimeType})');
      notifyListeners();
    }
  }

  void _readMeta(SharedPreferences p) {
    final meta = _decodeMap(p.getString(_kMeta));
    deviceId = '${meta['deviceId'] ?? ''}';
    if (deviceId.isEmpty) deviceId = _uuid.v4();
    final savedName = '${meta['deviceName'] ?? ''}';
    if (savedName.isNotEmpty) deviceName = savedName;
    relayOrigin = '${meta['relayOrigin'] ?? ''}';
    linkId = '${meta['linkId'] ?? ''}';
    linkPin = '${meta['linkPin'] ?? ''}';
    linkPeer = '${meta['linkPeer'] ?? ''}';
    linkSecret = '${meta['linkSecret'] ?? ''}';
    final cur = '${meta['currency'] ?? 'NPR'}';
    currency = currencySymbols.containsKey(cur) ? cur : 'NPR';
    setDisplaySymbol(currencySymbol);
    final tm = '${meta['themeMode'] ?? 'system'}';
    themeMode = (tm == 'light' || tm == 'dark') ? tm : 'system';
    final ac = meta['accent'];
    accent = ac is int ? ac : 0xFF009688;
    materialYou = meta['materialYou'] == true;
    userName = '${meta['userName'] ?? ''}';
    smsMode = '${meta['smsMode'] ?? 'manual'}' == 'auto' ? 'auto' : 'manual';
    final senders = meta['smsSenders'];
    smsSenders = senders is List
        ? senders
              .whereType<String>()
              .map((s) => s.trim())
              .where((s) => s.length >= 2)
              .toSet()
              .toList()
        : [];
    final savedUpdated = '${meta['updatedAt'] ?? ''}';
    if (savedUpdated.isNotEmpty) updatedAt = savedUpdated;
    lastSynced = '${meta['lastSynced'] ?? 'never'}';
  }

  /// Today's effective legacy state: the four domain keys decoded leniently,
  /// plus first-run seeding and the fuel upgrade. Unchanged Phase 0/1
  /// behavior; doubles as migration input on native platforms.
  void _readLegacyDomain(SharedPreferences p) {
    categories = _decodeList(p.getString(_kCats), Category.fromJson);
    transactions = _decodeList(p.getString(_kTxns), Txn.fromJson);
    loans = _decodeList(p.getString(_kLoans), Loan.fromJson);
    projects = _decodeList(p.getString(_kProjects), Project.fromJson);
    if (p.getString(_kCats) == null) {
      // First run: seed defaults.
      categories = defaultCategories();
      _touch();
    }
    if (categories.isNotEmpty && categories.every((c) => c.id != 'fuel')) {
      // One-time upgrade: Fuel did not exist in earlier versions.
      // It goes before Other so Other stays last.
      final at = categories.indexWhere((c) => c.id == 'other');
      if (at < 0) {
        categories.add(fuelDefault());
      } else {
        categories.insert(at, fuelDefault());
      }
      _touch();
    }
  }

  // ---------- persistence ----------

  List<T> _decodeList<T>(
    String? raw,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    if (raw == null || raw.isEmpty) return <T>[];
    try {
      final v = jsonDecode(raw);
      if (v is! List) return <T>[];
      return v.whereType<Map<String, dynamic>>().map(fromJson).toList();
    } catch (_) {
      return <T>[];
    }
  }

  Map<String, dynamic> _decodeMap(String? raw) {
    if (raw == null || raw.isEmpty) return {};
    try {
      final v = jsonDecode(raw);
      return v is Map<String, dynamic> ? v : {};
    } catch (_) {
      return {};
    }
  }

  void _touch() {
    updatedAt = DateTime.now().toUtc().toIso8601String();
    _saveAll();
  }

  /// Saves prefs-side state only (device/link/settings/sync stamps).
  /// Domain collections persist through [_domain]; backups stay separate.
  void _saveAll() {
    final p = _prefs;
    if (p == null) return;
    p.setString(
      _kMeta,
      jsonEncode({
        'deviceId': deviceId,
        'deviceName': deviceName,
        'updatedAt': updatedAt,
        'lastSynced': lastSynced,
        'relayOrigin': relayOrigin,
        'currency': currency,
        'themeMode': themeMode,
        'accent': accent,
        'materialYou': materialYou,
        'userName': userName,
        'smsMode': smsMode,
        'smsSenders': smsSenders,
        'linkId': linkId,
        'linkPin': linkPin,
        'linkPeer': linkPeer,
        'linkSecret': linkSecret,
      }),
    );
  }

  void _pushBackup(String snapshotJson) {
    final p = _prefs;
    if (p == null) return;
    final list = List<String>.from(p.getStringList(_kBackups) ?? []);
    list.insert(0, snapshotJson);
    while (list.length > 5) {
      list.removeLast();
    }
    p.setStringList(_kBackups, list);
  }

  List<String> get backups =>
      List<String>.from(_prefs?.getStringList(_kBackups) ?? []);

  void noteSynced() {
    lastSynced = DateTime.now().toUtc().toIso8601String();
    _saveAll();
    notifyListeners();
  }

  /// Remembers where the LAN relay lives (learned from a scanned code),
  /// so this device can offer codes too.
  Future<void> setRelayOrigin(String v) async {
    relayOrigin = v;
    _saveAll();
    notifyListeners();
  }

  /// Saves a pairing. From now on the engine keeps this device synced.
  /// [secret] is the high-entropy link credential (empty for legacy
  /// PIN-only pairings); it is stored with the pairing and cleared with it.
  Future<void> setLink({
    required String id,
    required String pin,
    required String peer,
    String secret = '',
  }) async {
    linkId = id;
    linkPin = pin;
    linkPeer = peer;
    linkSecret = secret;
    linkStatus = 'Linked with $peer.';
    _saveAll();
    notifyListeners();
  }

  /// Forgets a pairing (data stays, auto-sync stops). The link secret is
  /// revoked here: a stopped pairing's credential never lingers.
  Future<void> clearLink([String why = '']) async {
    linkId = '';
    linkPin = '';
    linkPeer = '';
    linkSecret = '';
    linkStatus = why;
    _saveAll();
    notifyListeners();
  }

  void setLinkStatus(String s) {
    linkStatus = s;
    notifyListeners();
  }

  /// Switches display currency everywhere (amounts are stored raw).
  Future<void> setCurrency(String v) async {
    if (!currencySymbols.containsKey(v)) return;
    currency = v;
    setDisplaySymbol(currencySymbol);
    _saveAll();
    notifyListeners();
  }

  static const accentChoices = [
    0xFF009688, // teal
    0xFF1565C0, // blue
    0xFF2E7D32, // green
    0xFFEF6C00, // orange
    0xFF6A1B9A, // purple
    0xFFC2185B, // pink
    0xFFC62828, // red
    0xFF455A64, // slate
    0xFFFFA000, // amber
    0xFF795548, // brown
    0xFF827717, // lime
    0xFF3949AB, // indigo
  ];

  static const accentNames = {
    0xFF009688: 'Teal',
    0xFF1565C0: 'Blue',
    0xFF2E7D32: 'Green',
    0xFFEF6C00: 'Orange',
    0xFF6A1B9A: 'Purple',
    0xFFC2185B: 'Pink',
    0xFFC62828: 'Red',
    0xFF455A64: 'Slate',
    0xFFFFA000: 'Amber',
    0xFF795548: 'Brown',
    0xFF827717: 'Lime',
    0xFF3949AB: 'Indigo',
  };

  static String accentName(int v) => accentNames[v] ?? 'Custom';

  Future<void> setThemeMode(String v) async {
    if (v != 'light' && v != 'dark') v = 'system';
    themeMode = v;
    _saveAll();
    notifyListeners();
  }

  Future<void> setAccent(int v) async {
    accent = v;
    _saveAll();
    notifyListeners();
  }

  Future<void> setMaterialYou(bool v) async {
    materialYou = v;
    dynamicSeedArgb = null;
    if (v) await _refreshDynamicSeed();
    _saveAll();
    notifyListeners();
  }

  Future<void> setUserName(String v) async {
    userName = v.trim();
    _saveAll();
    notifyListeners();
  }

  Future<void> setSmsMode(String v) async {
    smsMode = v == 'auto' ? 'auto' : 'manual';
    _saveAll();
    notifyListeners();
  }

  /// Replaces the sender allowlist (trimmed, deduped, min 2 chars).
  Future<void> setSmsSenders(List<String> v) async {
    final clean = <String>[];
    for (final s in v) {
      final t = s.trim();
      if (t.length >= 2 &&
          !clean.any((e) => e.toLowerCase() == t.toLowerCase())) {
        clean.add(t);
      }
    }
    smsSenders = clean;
    _saveAll();
    notifyListeners();
  }

  Future<void> _refreshDynamicSeed() async {
    try {
      final palette = await DynamicColorPlugin.getCorePalette();
      final tone = palette?.primary.get(40);
      if (tone != null) dynamicSeedArgb = tone;
    } catch (_) {
      // No dynamic color here (older Android, desktop, tests).
    }
  }

  /// Wipes everything on this device (UI double-confirms first).
  Future<void> eraseAll() async {
    final p = _prefs;
    if (p == null) return;
    await p.clear();
    categories = [];
    transactions = [];
    loans = [];
    projects = [];
    _revs = {};
    _tombs = {};
    _v2ready = false;
    linkId = '';
    linkPin = '';
    linkPeer = '';
    linkSecret = '';
    linkStatus = '';
    currency = 'NPR';
    themeMode = 'system';
    accent = 0xFF009688;
    relayOrigin = '';
    setDisplaySymbol('रू');
    await load(); // re-seeds defaults + notifies
  }

  // ---------- lookups ----------

  Category categoryOf(String id) {
    for (final c in categories) {
      if (c.id == id) return c;
    }
    return categories.isNotEmpty
        ? categories.last
        : Category(id: 'other', name: 'Other', icon: 0xe148, color: 0xFF607D8B);
  }

  void _sortTxns() {
    transactions.sort((a, b) => b.date.compareTo(a.date));
  }

  // ---------- transactions ----------

  Future<void> addTransaction({
    required String type,
    required double amount,
    required String categoryId,
    required DateTime date,
    String note = '',
    String mode = 'cash',
    String projectId = '',
  }) async {
    final before = _snapshotDomain();
    final prevUpdated = updatedAt;
    final txn = Txn(
      id: _uuid.v4(),
      type: type,
      amount: amount,
      categoryId: categoryId,
      date: date.millisecondsSinceEpoch,
      note: note,
      mode: mode,
      projectId: projectId,
    );
    transactions.add(txn);
    _sortTxns();
    _touch();
    await _persistDomain(before, prevUpdated, (d) {
      final rm = _bumpRev(SyncType.txn, txn.id);
      return d.upsertTransaction(txn, rev: rm.rev, by: rm.by);
    });
    notifyListeners();
  }

  /// Edits an entry in place. Only non-null fields change.
  /// Returns false when the id is unknown.
  Future<bool> updateTransaction(
    String id, {
    double? amount,
    String? note,
    String? categoryId,
    String? mode,
    DateTime? date,
    String? projectId,
  }) async {
    final i = transactions.indexWhere((t) => t.id == id);
    if (i < 0) return false;
    final t = transactions[i];
    final before = _snapshotDomain();
    final prevUpdated = updatedAt;
    final updated = Txn(
      id: t.id,
      type: t.type,
      amount: amount ?? t.amount,
      categoryId: categoryId ?? t.categoryId,
      date: date?.millisecondsSinceEpoch ?? t.date,
      note: note ?? t.note,
      mode: mode ?? t.mode,
      projectId: projectId ?? t.projectId,
    );
    transactions[i] = updated;
    _sortTxns();
    _touch();
    await _persistDomain(before, prevUpdated, (d) {
      final rm = _bumpRev(SyncType.txn, id);
      return d.upsertTransaction(updated, rev: rm.rev, by: rm.by);
    });
    notifyListeners();
    return true;
  }

  Future<void> deleteTransaction(String id) async {
    final before = _snapshotDomain();
    final prevUpdated = updatedAt;
    transactions.removeWhere((t) => t.id == id);
    _touch();
    await _persistDomain(before, prevUpdated, (d) async {
      final tomb = _makeTomb(SyncType.txn, id);
      await d.deleteTransaction(id);
      await d.saveTombstone(tomb);
    });
    notifyListeners();
  }

  /// Puts back a deleted entry (Undo). Keeps id/date so sync stays sane.
  Future<void> restoreTransaction(Txn txn) async {
    if (transactions.any((t) => t.id == txn.id)) return;
    final before = _snapshotDomain();
    final prevUpdated = updatedAt;
    transactions.add(txn);
    _sortTxns();
    _touch();
    await _persistDomain(before, prevUpdated, (d) async {
      final rm = _reviveRev(SyncType.txn, txn.id);
      await d.upsertTransaction(txn, rev: rm.rev, by: rm.by);
      await d.deleteTombstone(SyncType.txn, txn.id);
    });
    notifyListeners();
  }

  // ---------- categories & budgets ----------

  Future<void> addCategory(String name, {double budget = 0}) async {
    final before = _snapshotDomain();
    final prevUpdated = updatedAt;
    final newId = _uuid.v4();
    categories.add(
      Category(
        id: newId,
        name: name,
        icon: 0xe148,
        color: 0xFF607D8B,
        budget: budget,
      ),
    );
    _touch();
    await _persistDomain(before, prevUpdated, (d) async {
      final rm = _bumpRev(SyncType.cat, newId);
      await d.saveCategories(categories);
      await d.saveRecordMeta(SyncType.cat, newId, rm.rev, rm.by);
    });
    notifyListeners();
  }

  Future<void> setBudget(String id, double budget) async {
    final i = categories.indexWhere((c) => c.id == id);
    if (i < 0) return;
    final c = categories[i];
    final before = _snapshotDomain();
    final prevUpdated = updatedAt;
    categories[i] = Category(
      id: c.id,
      name: c.name,
      icon: c.icon,
      color: c.color,
      budget: budget,
    );
    _touch();
    await _persistDomain(before, prevUpdated, (d) async {
      final rm = _bumpRev(SyncType.cat, id);
      await d.saveCategories(categories);
      await d.saveRecordMeta(SyncType.cat, id, rm.rev, rm.by);
    });
    notifyListeners();
  }

  /// Renames / re-icons / re-colors a category (budget optional).
  Future<void> updateCategory(
    String id, {
    String? name,
    int? icon,
    int? color,
    double? budget,
  }) async {
    final i = categories.indexWhere((c) => c.id == id);
    if (i < 0) return;
    final c = categories[i];
    final n = (name ?? c.name).trim();
    final before = _snapshotDomain();
    final prevUpdated = updatedAt;
    categories[i] = Category(
      id: c.id,
      name: n.isEmpty ? c.name : n,
      icon: icon ?? c.icon,
      color: color ?? c.color,
      budget: budget ?? c.budget,
    );
    _touch();
    await _persistDomain(before, prevUpdated, (d) async {
      final rm = _bumpRev(SyncType.cat, id);
      await d.saveCategories(categories);
      await d.saveRecordMeta(SyncType.cat, id, rm.rev, rm.by);
    });
    notifyListeners();
  }

  /// Deletes a category (never 'other'); its entries move to Other.
  Future<bool> deleteCategory(String id) async {
    if (id == 'other') return false;
    if (!categories.any((c) => c.id == id)) return false;
    final before = _snapshotDomain();
    final prevUpdated = updatedAt;
    categories.removeWhere((c) => c.id == id);
    final fixed = <Txn>[];
    for (final t in transactions) {
      if (t.categoryId == id) {
        fixed.add(
          Txn(
            id: t.id,
            type: t.type,
            amount: t.amount,
            categoryId: 'other',
            date: t.date,
            note: t.note,
            mode: t.mode,
            projectId: t.projectId,
          ),
        );
      } else {
        fixed.add(t);
      }
    }
    transactions = fixed;
    _sortTxns();
    _touch();
    await _persistDomain(before, prevUpdated, (d) async {
      final tomb = _makeTomb(SyncType.cat, id);
      // Reassigned entries changed category: bump each moved one.
      final oldCat = {for (final t in before.transactions) t.id: t.categoryId};
      final moved = <String>[
        for (final t in transactions)
          if (t.categoryId == 'other' && oldCat[t.id] != 'other') t.id,
      ];
      await d.saveCategories(categories);
      await d.saveTransactions(transactions);
      await d.saveTombstone(tomb);
      for (final tid in moved) {
        final rm = _bumpRev(SyncType.txn, tid);
        await d.saveRecordMeta(SyncType.txn, tid, rm.rev, rm.by);
      }
    });
    notifyListeners();
    return true;
  }

  /// Moves a category up (delta -1) or down (+1) in the user order.
  Future<void> moveCategory(String id, int delta) async {
    final i = categories.indexWhere((c) => c.id == id);
    final j = i + delta;
    if (i < 0 || j < 0 || j >= categories.length) return;
    final before = _snapshotDomain();
    final prevUpdated = updatedAt;
    final c = categories.removeAt(i);
    categories.insert(j, c);
    _touch();
    await _persistDomain(before, prevUpdated, (d) async {
      await d.saveCategories(categories);
      await _saveMovedCategoryRevs(d, before);
    });
    notifyListeners();
  }

  /// Moves a category to an exact position (drag & drop, menu edges).
  /// Out-of-range positions clamp to the ends.
  Future<void> moveCategoryTo(String id, int index) async {
    final i = categories.indexWhere((c) => c.id == id);
    if (i < 0) return;
    var j = index;
    if (j < 0) j = 0;
    if (j >= categories.length) j = categories.length - 1;
    if (i == j) return;
    final before = _snapshotDomain();
    final prevUpdated = updatedAt;
    final c = categories.removeAt(i);
    categories.insert(j, c);
    _touch();
    await _persistDomain(before, prevUpdated, (d) async {
      await d.saveCategories(categories);
      await _saveMovedCategoryRevs(d, before);
    });
    notifyListeners();
  }

  /// Bumps revisions for categories whose list position changed (order is
  /// merged sync state, so reorder is an edit).
  Future<void> _saveMovedCategoryRevs(DomainStore d, DomainData before) async {
    final oldPos = <String, int>{};
    for (var k = 0; k < before.categories.length; k++) {
      oldPos[before.categories[k].id] = k;
    }
    for (var k = 0; k < categories.length; k++) {
      final id = categories[k].id;
      if (oldPos[id] != k) {
        final rm = _bumpRev(SyncType.cat, id);
        await d.saveRecordMeta(SyncType.cat, id, rm.rev, rm.by);
      }
    }
  }

  // ---------- lent-money ledger ----------

  Future<void> addLoan({
    required String person,
    required double amount,
    required DateTime date,
    String note = '',
    DateTime? due,
  }) async {
    final before = _snapshotDomain();
    final prevUpdated = updatedAt;
    final newId = _uuid.v4();
    loans.add(
      Loan(
        id: newId,
        person: person,
        lent: amount,
        dateLent: date.millisecondsSinceEpoch,
        dueDate: due?.millisecondsSinceEpoch,
        note: note,
        kind: 'lent',
      ),
    );
    _touch();
    await _persistDomain(before, prevUpdated, (d) {
      final rm = _bumpRev(SyncType.loan, newId);
      return d.upsertLoan(loans.last, rev: rm.rev, by: rm.by);
    });
    notifyListeners();
    _loansChanged();
  }

  /// Money you took from someone. Same ledger math, opposite direction.
  Future<void> addBorrow({
    required String person,
    required double amount,
    required DateTime date,
    String note = '',
    DateTime? due,
  }) async {
    final before = _snapshotDomain();
    final prevUpdated = updatedAt;
    final newId = _uuid.v4();
    loans.add(
      Loan(
        id: newId,
        person: person,
        lent: amount,
        dateLent: date.millisecondsSinceEpoch,
        dueDate: due?.millisecondsSinceEpoch,
        note: note,
        kind: 'borrowed',
      ),
    );
    _touch();
    await _persistDomain(before, prevUpdated, (d) {
      final rm = _bumpRev(SyncType.loan, newId);
      return d.upsertLoan(loans.last, rev: rm.rev, by: rm.by);
    });
    notifyListeners();
    _loansChanged();
  }

  /// One-time reminder moment (null = off). Past moments fire nothing.
  Future<void> setReminderAt(String loanId, DateTime? when) async {
    final i = loans.indexWhere((l) => l.id == loanId);
    if (i < 0) return;
    final l = loans[i];
    final before = _snapshotDomain();
    final prevUpdated = updatedAt;
    loans[i] = Loan(
      id: l.id,
      person: l.person,
      lent: l.lent,
      dateLent: l.dateLent,
      dueDate: l.dueDate,
      note: l.note,
      repayments: l.repayments,
      topups: l.topups,
      kind: l.kind,
      remindAt: when?.millisecondsSinceEpoch ?? 0,
    );
    _touch();
    await _persistDomain(before, prevUpdated, (d) {
      final rm = _bumpRev(SyncType.loan, loanId);
      return d.upsertLoan(loans[i], rev: rm.rev, by: rm.by);
    });
    notifyListeners();
    _loansChanged();
  }

  Future<void> addRepayment(
    String loanId,
    double amount,
    DateTime date,
    String note,
  ) async {
    final i = loans.indexWhere((l) => l.id == loanId);
    if (i < 0) return;
    final l = loans[i];
    final reps = List<Repayment>.from(l.repayments);
    final newRepId = _uuid.v4();
    reps.add(
      Repayment(
        id: newRepId,
        amount: amount,
        date: date.millisecondsSinceEpoch,
        note: note,
      ),
    );
    final before = _snapshotDomain();
    final prevUpdated = updatedAt;
    loans[i] = Loan(
      id: l.id,
      person: l.person,
      lent: l.lent,
      dateLent: l.dateLent,
      dueDate: l.dueDate,
      note: l.note,
      repayments: reps,
      topups: l.topups,
      kind: l.kind,
      remindAt: l.remindAt,
    );
    _touch();
    await _persistDomain(before, prevUpdated, (d) async {
      final rm = _bumpRev(SyncType.loan, loanId);
      await d.upsertLoan(loans[i], rev: rm.rev, by: rm.by);
      final cm = _bumpRev(SyncType.repay, newRepId);
      await d.saveRecordMeta(SyncType.repay, newRepId, cm.rev, cm.by);
    });
    notifyListeners();
    _loansChanged();
  }

  /// Lend more money to the same person (top-up). Mirrors repayments:
  /// raises pending instead of lowering it.
  Future<void> lendMore(
    String loanId,
    double amount,
    DateTime date,
    String note,
  ) async {
    final i = loans.indexWhere((l) => l.id == loanId);
    if (i < 0) return;
    final l = loans[i];
    final tops = List<Topup>.from(l.topups);
    final newTopId = _uuid.v4();
    tops.add(
      Topup(
        id: newTopId,
        amount: amount,
        date: date.millisecondsSinceEpoch,
        note: note,
      ),
    );
    final before = _snapshotDomain();
    final prevUpdated = updatedAt;
    loans[i] = Loan(
      id: l.id,
      person: l.person,
      lent: l.lent,
      dateLent: l.dateLent,
      dueDate: l.dueDate,
      note: l.note,
      repayments: l.repayments,
      topups: tops,
      kind: l.kind,
      remindAt: l.remindAt,
    );
    _touch();
    await _persistDomain(before, prevUpdated, (d) async {
      final rm = _bumpRev(SyncType.loan, loanId);
      await d.upsertLoan(loans[i], rev: rm.rev, by: rm.by);
      final cm = _bumpRev(SyncType.topup, newTopId);
      await d.saveRecordMeta(SyncType.topup, newTopId, cm.rev, cm.by);
    });
    notifyListeners();
    _loansChanged();
  }

  Future<void> deleteLoan(String id) async {
    final before = _snapshotDomain();
    final prevUpdated = updatedAt;
    loans.removeWhere((l) => l.id == id);
    _touch();
    await _persistDomain(before, prevUpdated, (d) async {
      final tomb = _makeTomb(SyncType.loan, id);
      await d.deleteLoan(id);
      await d.saveTombstone(tomb);
    });
    notifyListeners();
    _loansChanged();
  }

  /// Fired after any loan mutation so the UI can refresh OS reminders.
  /// Null in tests. Never awaited - reminders are best-effort.
  void Function()? onLoansChanged;

  void _loansChanged() {
    final f = onLoansChanged;
    if (f != null) f();
  }

  /// Lent out, still to receive.
  double get pendingLoansTotal {
    var sum = 0.0;
    for (final l in loans) {
      if (!l.settled && !l.isBorrowed) sum += l.pending;
    }
    return sum;
  }

  /// Borrowed, still to return.
  double get pendingBorrowedTotal {
    var sum = 0.0;
    for (final l in loans) {
      if (!l.settled && l.isBorrowed) sum += l.pending;
    }
    return sum;
  }

  // ---------- aggregates ----------

  List<Txn> monthTxns(DateTime month) => transactions.where((t) {
    final d = t.dateTime;
    return d.year == month.year && d.month == month.month;
  }).toList();

  double monthSpend(DateTime month) {
    var sum = 0.0;
    for (final t in monthTxns(month)) {
      if (t.isExpense) sum += t.amount;
    }
    return sum;
  }

  double monthIncome(DateTime month) {
    var sum = 0.0;
    for (final t in monthTxns(month)) {
      if (!t.isExpense) sum += t.amount;
    }
    return sum;
  }

  Map<String, double> spendByCategory(DateTime month) {
    final map = <String, double>{};
    for (final t in monthTxns(month)) {
      if (!t.isExpense) continue;
      map[t.categoryId] = (map[t.categoryId] ?? 0) + t.amount;
    }
    return map;
  }

  // ---------- event projects ----------

  Project projectOf(String id) {
    for (final e in projects) {
      if (e.id == id) return e;
    }
    return Project(id: '', name: 'No event', created: 0);
  }

  /// Creates an event project and returns its id (for inline creation).
  Future<String> addProject(String name, String note) async {
    final id = _uuid.v4();
    final before = _snapshotDomain();
    final prevUpdated = updatedAt;
    projects.add(
      Project(
        id: id,
        name: name,
        note: note,
        created: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    _touch();
    await _persistDomain(before, prevUpdated, (d) {
      final rm = _bumpRev(SyncType.proj, id);
      return d.upsertProject(projects.last, rev: rm.rev, by: rm.by);
    });
    notifyListeners();
    return id;
  }

  /// Renames / re-icons / re-colors an event.
  Future<void> updateProject(
    String id, {
    String? name,
    String? note,
    int? icon,
    int? color,
  }) async {
    final i = projects.indexWhere((e) => e.id == id);
    if (i < 0) return;
    final p = projects[i];
    final n = (name ?? p.name).trim();
    final before = _snapshotDomain();
    final prevUpdated = updatedAt;
    projects[i] = Project(
      id: p.id,
      name: n.isEmpty ? p.name : n,
      note: note ?? p.note,
      created: p.created,
      icon: icon ?? p.icon,
      color: color ?? p.color,
    );
    _touch();
    await _persistDomain(before, prevUpdated, (d) {
      final rm = _bumpRev(SyncType.proj, id);
      return d.upsertProject(projects[i], rev: rm.rev, by: rm.by);
    });
    notifyListeners();
  }

  Future<void> deleteProject(String id) async {
    final before = _snapshotDomain();
    final prevUpdated = updatedAt;
    projects.removeWhere((e) => e.id == id);
    final fixed = <Txn>[];
    for (final t in transactions) {
      if (t.projectId == id) {
        fixed.add(
          Txn(
            id: t.id,
            type: t.type,
            amount: t.amount,
            categoryId: t.categoryId,
            date: t.date,
            note: t.note,
            mode: t.mode,
          ),
        );
      } else {
        fixed.add(t);
      }
    }
    transactions = fixed;
    _sortTxns();
    _touch();
    await _persistDomain(before, prevUpdated, (d) async {
      final tomb = _makeTomb(SyncType.proj, id);
      // Untagged entries changed project: bump each moved one.
      final oldProj = {for (final t in before.transactions) t.id: t.projectId};
      final moved = <String>[
        for (final t in transactions)
          if (t.projectId.isEmpty && oldProj[t.id] == id) t.id,
      ];
      await d.deleteProject(id);
      await d.saveTransactions(transactions);
      await d.saveTombstone(tomb);
      for (final tid in moved) {
        final rm = _bumpRev(SyncType.txn, tid);
        await d.saveRecordMeta(SyncType.txn, tid, rm.rev, rm.by);
      }
    });
    notifyListeners();
  }

  List<Txn> projectTxns(String id) =>
      transactions.where((t) => t.projectId == id).toList();

  double projectSpend(String id) {
    var sum = 0.0;
    for (final t in transactions) {
      if (t.projectId == id && t.isExpense) sum += t.amount;
    }
    return sum;
  }

  // ---------- snapshot / sync ----------

  Snapshot toSnapshot() => Snapshot(
    version: kSnapshotVersion,
    updatedAt: updatedAt,
    deviceId: deviceId,
    deviceName: deviceName,
    categories: List<Category>.from(categories),
    transactions: List<Txn>.from(transactions),
    loans: List<Loan>.from(loans),
    projects: List<Project>.from(projects),
  );

  String exportJson() => toSnapshot().encode();

  /// Applies [raw] snapshot JSON if it is newer than local data.
  /// Returns a short human-readable message for the UI.
  ///
  /// Sync metadata is re-keyed, never reset: existing revisions survive per
  /// id, new ids baseline at 0. Tombstones: [force] (explicit restore) drops
  /// them all; [dropTombstonesForPresent] (user-picked file) drops them for
  /// imported ids; ambient sync keeps them so deletions stand. Restored-over
  /// tombstone ids outrank the deletion they undo.
  Future<String> importSnapshotString(
    String raw, {
    bool force = false,
    bool dropTombstonesForPresent = false,
  }) async {
    late Snapshot remote;
    try {
      remote = Snapshot.decode(raw);
    } catch (_) {
      return 'Could not read that file.';
    }
    final r = remote.updatedAtTime;
    final l =
        DateTime.tryParse(updatedAt) ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    if (!force && !r.isAfter(l)) {
      return 'Already up to date (this device is newer).';
    }
    _pushBackup(exportJson());
    final before = _snapshotDomain();
    final prevUpdated = updatedAt;
    final prevRevs = Map.of(_revs);
    final prevTombs = Map.of(_tombs);
    categories = remote.categories.isEmpty
        ? defaultCategories()
        : remote.categories;
    transactions = remote.transactions;
    loans = remote.loans;
    projects = remote.projects;
    final present = <String>{
      for (final c in categories) _mkey(SyncType.cat, c.id),
      for (final t in transactions) _mkey(SyncType.txn, t.id),
      for (final p in projects) _mkey(SyncType.proj, p.id),
      for (final l in loans) ...[
        _mkey(SyncType.loan, l.id),
        for (final t in l.topups) _mkey(SyncType.topup, t.id),
        for (final r in l.repayments) _mkey(SyncType.repay, r.id),
      ],
    };
    final dropped = <String, TombEntry>{};
    if (force) {
      dropped.addAll(_tombs);
      _tombs.clear();
    } else if (dropTombstonesForPresent) {
      for (final k in _tombs.keys.toList()) {
        if (present.contains(k)) dropped[k] = _tombs.remove(k)!;
      }
    }
    for (final k in present) {
      _revs.putIfAbsent(k, () => const RecordMeta(rev: 0, by: ''));
    }
    for (final e in dropped.entries) {
      final cur = _revs[e.key];
      final want = e.value.rev + 1;
      if (cur == null || cur.rev < want) {
        _revs[e.key] = RecordMeta(rev: want, by: deviceId);
      }
    }
    if (!force) {
      // Ambient/file imports keep tombstones for absent ids: those records
      // must not reappear in the lists (suppressed until explicitly
      // restored). Force-restore cleared every tombstone above.
      bool tombed(String t, String id) => _tombs.containsKey(_mkey(t, id));
      transactions = [
        for (final t in transactions)
          if (!tombed(SyncType.txn, t.id)) t,
      ];
      categories = [
        for (final c in categories)
          if (!tombed(SyncType.cat, c.id)) c,
      ];
      projects = [
        for (final p in projects)
          if (!tombed(SyncType.proj, p.id)) p,
      ];
      loans = [
        for (final l in loans)
          if (!tombed(SyncType.loan, l.id))
            Loan(
              id: l.id,
              person: l.person,
              kind: l.kind,
              lent: l.lent,
              dateLent: l.dateLent,
              dueDate: l.dueDate,
              note: l.note,
              remindAt: l.remindAt,
              topups: [
                for (final t in l.topups)
                  if (!tombed(SyncType.topup, t.id)) t,
              ],
              repayments: [
                for (final r in l.repayments)
                  if (!tombed(SyncType.repay, r.id)) r,
              ],
            ),
      ];
    }
    final d = _domain;
    if (d != null) {
      try {
        await d.replaceAll(
          DomainData(
            categories: List.of(categories),
            transactions: List.of(transactions),
            loans: List.of(loans),
            projects: List.of(projects),
          ),
        );
        for (final e in dropped.entries) {
          final m = _revs[e.key]!;
          final sep = e.key.indexOf('/');
          await d.saveRecordMeta(
            e.key.substring(0, sep),
            e.key.substring(sep + 1),
            m.rev,
            m.by,
          );
          await d.deleteTombstone(
            e.key.substring(0, sep),
            e.key.substring(sep + 1),
          );
        }
        lastPersistError = null;
      } catch (e) {
        // The import must not claim success while the database rejected it:
        // restore everything and say so through the message channel.
        _restoreDomain(before, prevUpdated);
        _revs
          ..clear()
          ..addAll(prevRevs);
        _tombs
          ..clear()
          ..addAll(prevTombs);
        lastPersistError = '$e';
        debugPrint(
          'Dhadda: import persist failed, reverted (${e.runtimeType})',
        );
        return 'Could not save the import. Nothing was changed.';
      }
    }
    _sortTxns();
    updatedAt = remote.updatedAt;
    lastSynced = DateTime.now().toUtc().toIso8601String();
    _saveAll();
    notifyListeners();
    _loansChanged();
    return 'Synced from ${remote.deviceName}.';
  }

  Future<String> restoreBackup(int index) async {
    final list = backups;
    if (index < 0 || index >= list.length) return 'Backup not found.';
    return importSnapshotString(list[index], force: true);
  }

  /// User-picked file import: v2 payloads merge by revision; v1 payloads
  /// whole-replace with tombstones dropped for imported ids (preserves the
  /// file-restore UX: file content appears after import).
  Future<String> importFilePayload(String raw) {
    if (V2Snapshot.detectFormat(raw) == 2) return importSnapshotV2(raw);
    return importSnapshotString(raw, dropTombstonesForPresent: true);
  }

  // ---------- Snapshot v2 (record-level sync) ----------

  static Map<String, dynamic> _catContent(Category c, int order) => {
    ...c.toJson(),
    'sortOrder': order,
  };

  static Map<String, dynamic> _loanContent(Loan l) => {
    'id': l.id,
    'person': l.person,
    'kind': l.kind,
    'lent': l.lent,
    'dateLent': l.dateLent,
    'dueDate': l.dueDate,
    'note': l.note,
    'remindAt': l.remindAt,
  };

  /// This device's full state as v2 records (live + tombstones outsourced
  /// to the caller for message counts).
  List<SyncRecord> _localV2Records() {
    final out = <SyncRecord>[];
    for (var i = 0; i < categories.length; i++) {
      final c = categories[i];
      final m = _metaFor(SyncType.cat, c.id);
      out.add(
        SyncRecord(
          type: SyncType.cat,
          id: c.id,
          rev: m.rev,
          by: m.by,
          data: _catContent(c, i),
        ),
      );
    }
    for (final t in transactions) {
      final m = _metaFor(SyncType.txn, t.id);
      out.add(
        SyncRecord(
          type: SyncType.txn,
          id: t.id,
          rev: m.rev,
          by: m.by,
          data: t.toJson(),
        ),
      );
    }
    for (final p in projects) {
      final m = _metaFor(SyncType.proj, p.id);
      out.add(
        SyncRecord(
          type: SyncType.proj,
          id: p.id,
          rev: m.rev,
          by: m.by,
          data: p.toJson(),
        ),
      );
    }
    for (final l in loans) {
      final m = _metaFor(SyncType.loan, l.id);
      out.add(
        SyncRecord(
          type: SyncType.loan,
          id: l.id,
          rev: m.rev,
          by: m.by,
          data: _loanContent(l),
        ),
      );
      for (final t in l.topups) {
        final cm = _metaFor(SyncType.topup, t.id);
        out.add(
          SyncRecord(
            type: SyncType.topup,
            id: t.id,
            rev: cm.rev,
            by: cm.by,
            parent: l.id,
            data: t.toJson(),
          ),
        );
      }
      for (final r in l.repayments) {
        final cm = _metaFor(SyncType.repay, r.id);
        out.add(
          SyncRecord(
            type: SyncType.repay,
            id: r.id,
            rev: cm.rev,
            by: cm.by,
            parent: l.id,
            data: r.toJson(),
          ),
        );
      }
    }
    return out;
  }

  String exportSnapshotV2() {
    final records = _localV2Records();
    for (final t in _tombs.values) {
      records.add(
        SyncRecord(type: t.type, id: t.id, rev: t.rev, by: t.by, dead: true),
      );
    }
    return V2Snapshot(
      deviceId: deviceId,
      deviceName: deviceName,
      exportedAt: DateTime.now().toUtc().toIso8601String(),
      records: records,
    ).encode();
  }

  /// Converts v1 content to baseline rev-0 records for compat merging.
  /// Unknown history loses nothing: union by id, current revs win conflicts.
  static List<SyncRecord> v1ToRev0Records(Snapshot snap) {
    final out = <SyncRecord>[];
    for (var i = 0; i < snap.categories.length; i++) {
      final c = snap.categories[i];
      out.add(
        SyncRecord(
          type: SyncType.cat,
          id: c.id,
          rev: 0,
          by: '',
          data: _catContent(c, i),
        ),
      );
    }
    for (final t in snap.transactions) {
      out.add(
        SyncRecord(
          type: SyncType.txn,
          id: t.id,
          rev: 0,
          by: '',
          data: t.toJson(),
        ),
      );
    }
    for (final p in snap.projects) {
      out.add(
        SyncRecord(
          type: SyncType.proj,
          id: p.id,
          rev: 0,
          by: '',
          data: p.toJson(),
        ),
      );
    }
    for (final l in snap.loans) {
      out.add(
        SyncRecord(
          type: SyncType.loan,
          id: l.id,
          rev: 0,
          by: '',
          data: _loanContent(l),
        ),
      );
      for (final t in l.topups) {
        out.add(
          SyncRecord(
            type: SyncType.topup,
            id: t.id,
            rev: 0,
            by: '',
            parent: l.id,
            data: t.toJson(),
          ),
        );
      }
      for (final r in l.repayments) {
        out.add(
          SyncRecord(
            type: SyncType.repay,
            id: r.id,
            rev: 0,
            by: '',
            parent: l.id,
            data: r.toJson(),
          ),
        );
      }
    }
    return out;
  }

  /// Materializes a merge result into domain state with the invariant pass:
  /// deterministic category order (`other` forced last, re-seeded if
  /// missing), dangling category refs fall back to `other` (current display
  /// behavior), dangling project refs are untagged (current delete behavior),
  /// orphan loan children are dropped (counted, never crash).
  ({DomainData data, Map<String, RecordMeta> meta, List<TombEntry> tombs})
  _materializeMerge(MergeResult result) {
    var skippedOrphans = 0;
    final catRecs = <SyncRecord>[];
    for (final r in result.records.values) {
      if (r.type == SyncType.cat && !r.dead) catRecs.add(r);
    }
    int sortOf(SyncRecord r) {
      final v = r.data?['sortOrder'];
      return v is int ? v : 1 << 30;
    }

    catRecs.sort((a, b) {
      final s = sortOf(a).compareTo(sortOf(b));
      return s != 0 ? s : a.id.compareTo(b.id);
    });
    final otherIdx = catRecs.indexWhere((r) => r.id == 'other');
    SyncRecord? other;
    if (otherIdx >= 0) {
      other = catRecs.removeAt(otherIdx);
    } else {
      // The app invariant needs an Other: re-seed it rather than run broken.
      other = const SyncRecord(
        type: SyncType.cat,
        id: 'other',
        rev: 0,
        by: '',
        data: {
          'id': 'other',
          'name': 'Other',
          'icon': 0xe148,
          'color': 0xFF607D8B,
          'budget': 0,
        },
      );
    }
    catRecs.add(other);
    final catIds = {for (final r in catRecs) r.id};

    final categories = <Category>[];
    final meta = <String, RecordMeta>{};
    for (final r in catRecs) {
      categories.add(
        Category.fromJson(Map<String, dynamic>.from(r.data ?? {'id': r.id})),
      );
      meta[_mkey(r.type, r.id)] = RecordMeta(rev: r.rev, by: r.by);
    }

    final projects = <Project>[];
    for (final r in result.records.values) {
      if (r.type != SyncType.proj || r.dead) continue;
      projects.add(
        Project.fromJson(Map<String, dynamic>.from(r.data ?? {'id': r.id})),
      );
      meta[_mkey(r.type, r.id)] = RecordMeta(rev: r.rev, by: r.by);
    }
    final projIds = {for (final p in projects) p.id};

    final loans = <Loan>[];
    final topupsByLoan = <String, List<Topup>>{};
    final repaysByLoan = <String, List<Repayment>>{};
    for (final r in result.records.values) {
      if (r.type == SyncType.topup && !r.dead) {
        if (!result.records.containsKey('loan/${r.parent}')) {
          skippedOrphans++;
          continue;
        }
        final t = Topup.fromJson(Map<String, dynamic>.from(r.data ?? {}));
        (topupsByLoan[r.parent] ??= []).add(
          Topup(id: r.id, amount: t.amount, date: t.date, note: t.note),
        );
        meta[_mkey(r.type, r.id)] = RecordMeta(rev: r.rev, by: r.by);
      } else if (r.type == SyncType.repay && !r.dead) {
        if (!result.records.containsKey('loan/${r.parent}')) {
          skippedOrphans++;
          continue;
        }
        final x = Repayment.fromJson(Map<String, dynamic>.from(r.data ?? {}));
        (repaysByLoan[r.parent] ??= []).add(
          Repayment(id: r.id, amount: x.amount, date: x.date, note: x.note),
        );
        meta[_mkey(r.type, r.id)] = RecordMeta(rev: r.rev, by: r.by);
      }
    }
    // Loan rows whose parent lost (deleted) are dropped with the children.
    for (final r in result.records.values) {
      if (r.type != SyncType.loan || r.dead) continue;
      final d = Map<String, dynamic>.from(r.data ?? {'id': r.id});
      loans.add(
        Loan(
          id: r.id,
          person: '${d['person'] ?? ''}',
          kind: d['kind'] == 'borrowed' ? 'borrowed' : 'lent',
          lent: d['lent'] is num ? (d['lent'] as num).toDouble() : 0,
          dateLent: d['dateLent'] is int
              ? d['dateLent'] as int
              : DateTime.now().millisecondsSinceEpoch,
          dueDate: d['dueDate'] is int ? d['dueDate'] as int : null,
          note: '${d['note'] ?? ''}',
          remindAt: d['remindAt'] is int ? d['remindAt'] as int : 0,
          topups: topupsByLoan[r.id] ?? const [],
          repayments: repaysByLoan[r.id] ?? const [],
        ),
      );
      meta[_mkey(r.type, r.id)] = RecordMeta(rev: r.rev, by: r.by);
    }

    final transactions = <Txn>[];
    for (final r in result.records.values) {
      if (r.type != SyncType.txn || r.dead) continue;
      final d = Map<String, dynamic>.from(r.data ?? {'id': r.id});
      final catId = catIds.contains('${d['categoryId'] ?? ''}')
          ? '${d['categoryId']}'
          : 'other';
      final projId = projIds.contains('${d['projectId'] ?? ''}')
          ? '${d['projectId']}'
          : '';
      transactions.add(
        Txn(
          id: r.id,
          type: d['type'] == 'income' ? 'income' : 'expense',
          amount: d['amount'] is num ? (d['amount'] as num).toDouble() : 0,
          categoryId: catId,
          date: d['date'] is int
              ? d['date'] as int
              : DateTime.now().millisecondsSinceEpoch,
          note: '${d['note'] ?? ''}',
          mode: '${d['mode'] ?? 'cash'}',
          projectId: projId,
        ),
      );
      meta[_mkey(r.type, r.id)] = RecordMeta(rev: r.rev, by: r.by);
    }

    final tombs = <TombEntry>[];
    for (final t in result.tombs.values) {
      tombs.add(TombEntry(type: t.type, id: t.id, rev: t.rev, by: t.by));
    }
    if (skippedOrphans > 0) {
      debugPrint('Dhadda: merge dropped $skippedOrphans orphan children.');
    }
    return (
      data: DomainData(
        categories: categories,
        transactions: transactions,
        loans: loans,
        projects: projects,
      ),
      meta: meta,
      tombs: tombs,
    );
  }

  /// Merges peer records and applies the result atomically (Phase 2 revert
  /// discipline extended to rev/tomb maps). Never throws: failures restore
  /// everything and surface through the returned error.
  Future<({bool changed, int adopted, int tombs, String? error})>
  _mergeAndApply(List<SyncRecord> remote) async {
    final d = _domain;
    if (d == null) {
      return (changed: false, adopted: 0, tombs: 0, error: 'not ready');
    }
    final local = <String, SyncRecord>{};
    for (final r in _localV2Records()) {
      local[r.key] = r;
    }
    final localTombs = <String, SyncRecord>{
      for (final t in _tombs.values)
        t.key: SyncRecord(
          type: t.type,
          id: t.id,
          rev: t.rev,
          by: t.by,
          dead: true,
        ),
    };
    final result = mergeRecords(
      localRecords: local,
      localTombs: localTombs,
      remote: remote,
    );
    if (!result.changed) {
      return (changed: false, adopted: 0, tombs: 0, error: null);
    }
    final mat = _materializeMerge(result);
    final before = _snapshotDomain();
    final prevUpdated = updatedAt;
    final prevRevs = Map.of(_revs);
    final prevTombs = Map.of(_tombs);
    try {
      await d.applyV2(data: mat.data, meta: mat.meta, tombs: mat.tombs);
      categories = mat.data.categories;
      transactions = mat.data.transactions;
      loans = mat.data.loans;
      projects = mat.data.projects;
      _revs = mat.meta;
      _tombs = {for (final t in mat.tombs) t.key: t};
      _sortTxns();
      updatedAt = DateTime.now().toUtc().toIso8601String();
      _saveAll();
      lastPersistError = null;
      notifyListeners();
      _loansChanged();
      return (
        changed: true,
        adopted: result.adopted,
        tombs: result.tombsChanged,
        error: null,
      );
    } catch (e) {
      _restoreDomain(before, prevUpdated);
      _revs
        ..clear()
        ..addAll(prevRevs);
      _tombs
        ..clear()
        ..addAll(prevTombs);
      lastPersistError = '$e';
      debugPrint('Dhadda: merge apply failed, reverted (${e.runtimeType})');
      notifyListeners();
      return (changed: false, adopted: 0, tombs: 0, error: '$e');
    }
  }

  /// Applies a v2 peer snapshot with record-level merge. Human message for
  /// snackbars; never throws into the UI.
  Future<String> importSnapshotV2(String raw) async {
    final snap = V2Snapshot.tryDecode(raw);
    if (snap == null) return 'Could not read that sync data.';
    if (!_v2ready) await _ensureV2Init(_prefs!);
    final r = await _mergeAndApply(snap.records);
    if (r.error != null) {
      return 'Could not save the sync merge. Nothing was changed.';
    }
    if (!r.changed) return 'Already in sync.';
    final n = r.adopted + r.tombs;
    return 'Synced $n change${n == 1 ? '' : 's'} from ${snap.deviceName}.';
  }

  /// Uniform network ingest for every sync transport: v2 payloads merge by
  /// revision; v1 payloads convert to baseline rev-0 records and merge the
  /// same way (never whole-replace). Malformed payloads throw for the
  /// existing friendly-error UX.
  Future<String> ingestPeerSnapshot(
    String raw, {
    String peerName = 'device',
  }) async {
    final fmt = V2Snapshot.detectFormat(raw);
    if (fmt == 2) return importSnapshotV2(raw);
    if (fmt == 1) {
      final Snapshot remote;
      try {
        remote = Snapshot.decode(raw);
      } catch (_) {
        throw FormatException('Could not read that snapshot.');
      }
      if (!_v2ready) await _ensureV2Init(_prefs!);
      final r = await _mergeAndApply(v1ToRev0Records(remote));
      if (r.error != null) {
        return 'Could not save the sync merge. Nothing was changed.';
      }
      if (!r.changed) return 'Already in sync.';
      final n = r.adopted + r.tombs;
      return 'Synced $n change${n == 1 ? '' : 's'} from $peerName.';
    }
    throw FormatException('Could not read that snapshot.');
  }
}
