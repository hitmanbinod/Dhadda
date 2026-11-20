import 'dart:async';
import 'dart:convert';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/foundation.dart' hide Category;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'app_dates.dart';
import 'category_rules.dart';
import 'format.dart';
import 'analytics.dart';
import 'home_layout.dart';
import 'data/db_recovery.dart';
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

  /// Counts for privacy-safe diagnostics (no content exposed).
  int get tombstoneCount => _tombs.length;
  int get revisionCount => _revs.length;

  /// Test-only backend injection (unit tests have no native database).
  /// When set, [load] uses it instead of opening SQLite.
  final DomainStore? _domainOverride;

  ExpenseStore({this._domainOverride});

  List<Category> categories = [];
  List<Account> accounts = defaultAccounts();
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
  bool hideBalance = false;
  // One-handed layout is on by default (One UI style): the top tabs and
  // toggles sit just above the bottom navigation for thumb reach.
  bool oneHanded = true;
  /// Guards the one-time default migration: once the user has touched the
  /// toggle, their persisted choice wins on every later load.
  bool _oneHandedChosen = false;
  List<HomeSectionSetting> homeLayout = defaultHomeLayout();
  String calendarSystem = 'ad'; // ad | bs — display/grouping only
  List<CategoryRule> categoryRules = [];
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

  /// Non-empty when the database file would not open. The shell gates on this
  /// and offers recovery; [loaded] stays false so no empty state is rendered
  /// as if it were the user's real data. Cleared by
  /// [retryAfterDatabaseProblem].
  String databaseProblem = '';

  /// File name of the unreadable database the user chose to set aside, empty
  /// when nothing was moved. Surfaced by the recovery screen so the copy is
  /// not a mystery on the device.
  String lastQuarantinedDb = '';

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
      if (!await _loadDomainFromStore()) {
        // The database exists but will not open (corrupt file, unreadable
        // page). Do not fall through to an empty UI: quarantine the file and
        // park the user on a recoverable screen. See _recoverUnreadableDb.
        return;
      }
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

  /// Loads domain rows from the active backend. Returns false when the backend
  /// would not open, having already recorded the problem for the UI.
  Future<bool> _loadDomainFromStore() async {
    try {
      final d = await _domain!.loadDomain();
      categories = d.categories;
      accounts = d.accounts.isEmpty ? defaultAccounts() : d.accounts;
      transactions = d.transactions;
      loans = d.loans;
      projects = d.projects;
      return true;
    } catch (e) {
      await _recordDatabaseProblem(e);
      return false;
    }
  }

  /// Records that the backend would not open, so the shell can offer recovery
  /// instead of showing an empty expense tracker that is indistinguishable from
  /// deleted data. The file is deliberately left in place: retrying is the
  /// honest first try, and it is only moved aside if the user chooses to start
  /// empty.
  Future<void> _recordDatabaseProblem(Object error) async {
    debugPrint('Dhadda: database would not open (${error.runtimeType}).');
    try {
      await _domain?.close();
    } catch (_) {}
    _domain = null;
    _ownsDomain = false;
    // A failed load must never look like a successful empty load.
    loaded = false;
    databaseProblem =
        "Dhadda couldn't open the file holding your transactions.";
    notifyListeners();
  }

  /// Retries the load against the same file, for transient failures.
  Future<void> retryAfterDatabaseProblem() async {
    databaseProblem = '';
    await load();
  }

  /// Moves the unreadable file aside and starts fresh. The file is renamed,
  /// never deleted, so anything still recoverable stays on the device.
  Future<void> startEmptyAfterDatabaseProblem() async {
    databaseProblem = '';
    try {
      lastQuarantinedDb = await quarantineDatabaseFile();
    } catch (e) {
      debugPrint('Dhadda: quarantine failed (${e.runtimeType})');
    }
    await load();
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
      accounts: List.of(accounts),
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
    accounts = snap.accounts.isEmpty ? defaultAccounts() : snap.accounts;
    transactions = snap.transactions;
    loans = snap.loans;
    projects = snap.projects;
    updatedAt = prevUpdatedAt;
    _saveAll(); // re-save the restored stamp so prefs meta matches memory
  }

  /// Set when a merge replaces the in-memory lists from a wholesale apply,
  /// so the next write knows the copy it is looking at is not the one it was
  /// built against. Consumed by [_persistDomain].
  bool _mergeOverwroteMemory = false;

  /// Re-reads domain state after a merge raced a queued write. Best effort:
  /// the write itself already succeeded, so a failure here must not be
  /// reported as a failed save.
  Future<void> _rereadFromBackend(DomainStore d) async {
    try {
      final fresh = await d.loadDomain();
      categories = fresh.categories;
      transactions = fresh.transactions;
      loans = fresh.loans;
      projects = fresh.projects;
      _sortTxns();
      _revs = await d.loadRecordMeta();
      _tombs = {for (final t in await d.loadTombstones()) t.key: t};
      notifyListeners();
    } catch (e) {
      debugPrint('Dhadda: post-merge reread failed (${e.runtimeType})');
    }
  }

  /// Tail of the domain-write chain. Every write goes through [_serialized],
  /// so at most one writer touches the backend at a time.
  Future<void> _writeTail = Future<void>.value();

  /// Runs [op] with exclusive access to the domain backend.
  ///
  /// This exists because [_mergeAndApply] computes its merge from in-memory
  /// state and then replaces all seven tables wholesale. Dart yields at every
  /// await, so without a lock a mutator could commit a row after the merge
  /// computed but before it wrote -- and the wholesale replace, built from the
  /// older state, would delete a just-saved entry with no error anywhere.
  ///
  /// Memory mutations deliberately stay outside the lock: every mutator edits
  /// the in-memory lists *before* calling [_persistDomain], so a merge that
  /// reads memory after a write has completed also observes that mutation.
  /// Serializing compute-and-write is therefore sufficient.
  Future<T> _serialized<T>(Future<T> Function() op) async {
    final previous = _writeTail;
    final gate = Completer<void>();
    _writeTail = gate.future;
    await previous;
    try {
      return await op();
    } finally {
      gate.complete();
    }
  }

  /// Awaited write-through with revert. [before]/[prevUpdatedAt] must be
  /// captured by the caller BEFORE mutating memory. Revision/tombstone maps
  /// are snapshotted here (mutations bump them before calling). On database
  /// failure everything rolls back, the error is recorded, and listeners are
  /// notified — the UI never shows phantom-saved state. Failures are never
  /// thrown into the UI and never only logged. Returns false when the
  /// operation failed and was reverted, true on success (or when no
  /// database backend exists).
  Future<bool> _persistDomain(
    DomainData before,
    String prevUpdatedAt,
    Future<void> Function(DomainStore) op,
  ) async {
    final d = _domain;
    if (d == null) return true;
    final prevRevs = Map.of(_revs);
    final prevTombs = Map.of(_tombs);
    try {
      await _serialized(() async {
        await op(d);
        // A merge that applied while this mutator waited for the lock has
        // already replaced the in-memory lists with its own (older) copy.
        // This write is the later one, so re-read rather than trust it --
        // otherwise the entry just saved stays missing from the UI until the
        // next cold start.
        if (_mergeOverwroteMemory) {
          _mergeOverwroteMemory = false;
          await _rereadFromBackend(d);
        }
      });
      lastPersistError = null;
      return true;
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
      return false;
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
    hideBalance = meta['hideBalance'] == true;
    _oneHandedChosen = meta['one_handed_choice_v1'] == true;
    // Older installs stored false without an explicit choice (the setting
    // used to default off). Move them to the new default once; a real user
    // choice, recorded by setOneHanded, is never overwritten.
    oneHanded = _oneHandedChosen ? meta['one_handed_mode'] == true : true;
    calendarSystem = meta['calendarSystem'] == 'bs' ? 'bs' : 'ad';
    setAppCalendar(calendarSystem);
    categoryRules = decodeCategoryRules(
      meta['category_rules_v1'] is String
          ? meta['category_rules_v1'] as String
          : null,
    );
    homeLayout = decodeHomeLayout(
      meta['home_layout_v1'] is String
          ? meta['home_layout_v1'] as String
          : null,
    );
    // Events used to default off. Existing installs get one migration to the
    // new default so tagged events (all of them, not just one) show on Home;
    // after that, any explicit Edit Home choice is kept as stored.
    if (meta['home_events_v1'] != true) {
      homeLayout = [
        for (final s in homeLayout)
          s.section == HomeSection.events
              ? const HomeSectionSetting(
                  section: HomeSection.events,
                  visible: true,
                )
              : s,
      ];
    }
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
    final savedAccounts = p.getString('expense_accounts_v1');
    accounts = savedAccounts == null
        ? defaultAccounts()
        : _decodeList(savedAccounts, Account.fromJson);
    if (accounts.isEmpty) accounts = defaultAccounts();
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
        'hideBalance': hideBalance,
        'one_handed_mode': oneHanded,
        'one_handed_choice_v1': _oneHandedChosen,
        'calendarSystem': calendarSystem,
        'category_rules_v1': encodeCategoryRules(categoryRules),
        'home_layout_v1': encodeHomeLayout(homeLayout),
        'home_events_v1': true,
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

  /// Masks Home amounts. The eye on Home and the Settings switch call this;
  /// the pref is per-device and never enters snapshots.
  Future<void> setHideBalance(bool v) async {
    if (hideBalance == v) return;
    hideBalance = v;
    _saveAll();
    notifyListeners();
  }

  /// Per-device layout toggle: moves top controls toward the thumb.
  Future<void> setOneHanded(bool value) async {
    if (oneHanded == value) return;
    _oneHandedChosen = true;
    oneHanded = value;
    _saveAll();
    notifyListeners();
  }

  /// Switches the display/grouping calendar. Stored dates never change.
  Future<void> setCalendarSystem(String value) async {
    if (value != 'ad' && value != 'bs') return;
    if (calendarSystem == value) return;
    calendarSystem = value;
    setAppCalendar(value);
    _saveAll();
    notifyListeners();
  }

  void _commitRules(List<CategoryRule> rules) {
    categoryRules = rules;
    _saveAll();
    notifyListeners();
  }

  Future<void> addCategoryRule({
    required String text,
    required String categoryId,
    String type = 'any',
  }) async {
    final clean = normalizeRuleText(text);
    if (clean.length < 2) return;
    final ruleType = CategoryRuleType.values.firstWhere(
      (t) => t.name == type,
      orElse: () => CategoryRuleType.any,
    );
    if (categoryRules.any(
      (r) =>
          normalizeRuleText(r.text) == clean &&
          r.categoryId == categoryId &&
          r.type == ruleType,
    )) {
      return;
    }
    _commitRules([
      ...categoryRules,
      CategoryRule(
        id: const Uuid().v4(),
        text: clean,
        categoryId: categoryId,
        type: ruleType,
      ),
    ]);
  }

  Future<void> updateCategoryRule(String id, CategoryRule rule) async {
    _commitRules([
      for (final r in categoryRules) if (r.id == id) rule else r,
    ]);
  }

  Future<void> deleteCategoryRule(String id) async {
    _commitRules([for (final r in categoryRules) if (r.id != id) r]);
  }

  Future<void> reorderCategoryRule(int oldIndex, int newIndex) async {
    _commitRules(moveCategoryRule(categoryRules, oldIndex, newIndex));
  }

  /// First enabled matching rule, or null. Rules are per-device and never
  /// applied retroactively to stored entries.
  CategoryRule? categoryRuleFor(String note, String type) => matchCategoryRule(
        categoryRules,
        note: note,
        type: type,
        validCategoryIds: {
          for (final c in categories) c.id,
        },
      );

  /// Applies a Home section order/visibility list immediately. Balance stays
  /// pinned first and unknown sections are added hidden by [normalizeHomeLayout].
  Future<void> setHomeLayout(List<HomeSectionSetting> layout) async {
    final next = normalizeHomeLayout(layout);
    homeLayout = next;
    _saveAll();
    notifyListeners();
  }

  Future<void> resetHomeLayout() => setHomeLayout(defaultHomeLayout());

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
    // Before load() reseeds: prefs.clear() already dropped the migration
    // marker, so load() re-migrates into the same database. resetSyncMeta
    // clears the tombstones the wipe must forget and the revisions the
    // reseeded defaults would otherwise inherit, so this device stops
    // re-publishing pre-wipe deletions to peers and rejoins at rev 0.
    try {
      await _domain?.resetSyncMeta();
    } catch (e) {
      debugPrint(
        'Dhadda: erase-all could not reset sync meta: ${e.runtimeType}',
      );
    }
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

  /// Adds a transaction. Returns false when persisting failed and the
  /// in-memory state was reverted — callers must not claim success.
  Future<bool> addTransaction({
    required String type,
    required double amount,
    required String categoryId,
    required DateTime date,
    String note = '',
    String mode = 'cash',
    String accountId = '',
    String projectId = '',
    String? id,
  }) async {
    final before = _snapshotDomain();
    final prevUpdated = updatedAt;
    final txn = Txn(
      id: id ?? _uuid.v4(),
      type: type,
      amount: amount,
      categoryId: categoryId,
      date: date.millisecondsSinceEpoch,
      note: note,
      mode: mode,
      accountId: accountId,
      projectId: projectId,
    );
    transactions.add(txn);
    _sortTxns();
    _touch();
    final ok = await _persistDomain(before, prevUpdated, (d) {
      final rm = _bumpRev(SyncType.txn, txn.id);
      return d.upsertTransaction(txn, rev: rm.rev, by: rm.by);
    });
    notifyListeners();
    return ok;
  }

  /// Edits an entry in place. Only non-null fields change.
  /// Returns false when the id is unknown or persisting failed
  /// (state reverted) — callers must not claim success.
  Future<bool> updateTransaction(
    String id, {
    double? amount,
    String? note,
    String? categoryId,
    String? mode,
    String? accountId,
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
      accountId: accountId ?? t.accountId,
      projectId: projectId ?? t.projectId,
    );
    transactions[i] = updated;
    _sortTxns();
    _touch();
    final ok = await _persistDomain(before, prevUpdated, (d) {
      final rm = _bumpRev(SyncType.txn, id);
      return d.upsertTransaction(updated, rev: rm.rev, by: rm.by);
    });
    notifyListeners();
    return ok;
  }

  Future<void> deleteTransaction(String id) async {
    final before = _snapshotDomain();
    final prevUpdated = updatedAt;
    transactions.removeWhere((t) => t.id == id);
    _touch();
    await _persistDomain(before, prevUpdated, (d) async {
      final tomb = _makeTomb(SyncType.txn, id);
      // Tombstone BEFORE the row delete. If the process dies between the two,
      // the merge still converges to deleted (the tombstone wins on rev).
      // Delete-first would leave the row gone with no tombstone, and the next
      // merge re-adopts it from any peer still holding it -- the deletion
      // silently un-does itself.
      await d.saveTombstone(tomb);
      await d.deleteTransaction(id);
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

  // ---------- accounts (Round 3) ----------

  List<Account> get activeAccounts {
    final list = accounts.where((a) => !a.archived).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return list;
  }

  Account accountOf(String idOrMode) {
    for (final a in accounts) {
      if (a.id == idOrMode) return a;
    }
    final legacy = accountIdForMode(idOrMode);
    for (final a in accounts) {
      if (a.id == legacy) return a;
    }
    return accounts.isEmpty ? defaultAccounts().first : accounts.first;
  }

  String accountName(String idOrMode) => accountOf(idOrMode).name;

  /// SMS/legacy modes map to the first active account of the matching type,
  /// with a graceful fallback to the first active account.
  String accountIdForModeOrDefault(String mode) {
    final wanted = modeForAccountType(mode);
    for (final a in activeAccounts) {
      if (a.type == wanted) return a.id;
    }
    return activeAccounts.isEmpty ? defaultAccounts().first.id : activeAccounts.first.id;
  }

  Future<void> _writeAccounts(
    List<Account> next,
    Future<void> Function(DomainStore d) persist,
  ) async {
    final before = _snapshotDomain();
    final prevUpdated = updatedAt;
    accounts = next;
    _touch();
    await _persistDomain(before, prevUpdated, (d) async {
      await d.saveAccounts(next);
      await persist(d);
    });
    notifyListeners();
  }

  Future<String> addAccount(String name, String type, {int color = 0}) async {
    final clean = name.trim();
    if (clean.isEmpty) return '';
    final id = _uuid.v4();
    final next = [
      ...accounts,
      Account(
        id: id,
        name: clean,
        type: type,
        color: color,
        sortOrder: accounts.length,
      ),
    ];
    await _writeAccounts(next, (d) async {
      final rm = _bumpRev(SyncType.acct, id);
      // Re-write so the new row carries its own revision.
      await d.saveAccounts(next);
      await d.saveRecordMeta(SyncType.acct, id, rm.rev, rm.by);
    });
    return id;
  }

  Future<void> updateAccount(Account account) async {
    final next = [
      for (final a in accounts) if (a.id == account.id) account else a,
    ];
    await _writeAccounts(next, (d) async {
      final rm = _bumpRev(SyncType.acct, account.id);
      await d.saveRecordMeta(SyncType.acct, account.id, rm.rev, rm.by);
    });
  }

  Future<void> reorderAccounts(int oldIndex, int newIndex) async {
    final order = activeAccounts;
    if (oldIndex < 0 || oldIndex >= order.length) return;
    final moved = order.removeAt(oldIndex);
    order.insert(newIndex.clamp(0, order.length), moved);
    final byId = {for (final a in accounts) a.id: a};
    final next = [
      for (var i = 0; i < accounts.length; i++)
        (byId[accounts[i].id] ?? accounts[i]).copyWith(sortOrder: i),
    ];
    final reordered = <Account>[
      ...next.where((a) => !byId[a.id]!.archived),
      ...next.where((a) => byId[a.id]!.archived),
    ];
    await _writeAccounts(reordered, (d) async {});
  }

  Future<bool> archiveAccount(String id) async {
    final a = accountOf(id);
    if (a.archived || activeAccounts.length <= 1) return false;
    await updateAccount(a.copyWith(archived: true));
    return true;
  }

  Future<bool> deleteAccount(String id) async {
    final a = accountOf(id);
    if (a.archived == false && activeAccounts.length <= 1) return false;
    if (transactions.any((t) => t.effectiveAccountId == a.id)) return false;
    final next = [for (final acc in accounts) if (acc.id != a.id) acc];
    final before = _snapshotDomain();
    final prevUpdated = updatedAt;
    accounts = next;
    _touch();
    await _persistDomain(before, prevUpdated, (d) async {
      await d.saveTombstone(_makeTomb(SyncType.acct, a.id));
      await d.saveAccounts(next);
    });
    notifyListeners();
    return true;
  }

  /// Re-points entries to [targetId], archives the source account (keeping its
  /// history and tombstone semantics) and never loses a transaction.
  Future<void> mergeAccount(String sourceId, String targetId) async {
    if (sourceId == targetId) return;
    final target = accountOf(targetId);
    final before = _snapshotDomain();
    final prevUpdated = updatedAt;
    final mode = modeForAccountType(target.type);
    transactions = [
      for (final t in transactions)
        t.effectiveAccountId == sourceId
            ? Txn(
                id: t.id,
                type: t.type,
                amount: t.amount,
                categoryId: t.categoryId,
                date: t.date,
                note: t.note,
                mode: mode,
                accountId: target.id,
                projectId: t.projectId,
              )
            : t,
    ];
    accounts = [
      for (final a in accounts)
        if (a.id == sourceId)
          a.copyWith(archived: true)
        else
          a,
    ];
    _touch();
    await _persistDomain(before, prevUpdated, (d) async {
      await d.saveTombstone(_makeTomb(SyncType.acct, sourceId));
      await d.saveAccounts(accounts);
      await d.saveTransactions(transactions);
    });
    notifyListeners();
  }

  Future<void> setEntryAccount(String txnId, String accountId) async {
    final i = transactions.indexWhere((t) => t.id == txnId);
    if (i < 0) return;
    final a = accountOf(accountId);
    final t = transactions[i];
    final updated = Txn(
      id: t.id,
      type: t.type,
      amount: t.amount,
      categoryId: t.categoryId,
      date: t.date,
      note: t.note,
      mode: modeForAccountType(a.type),
      accountId: a.id,
      projectId: t.projectId,
    );
    transactions[i] = updated;
    _touch();
    final before = _snapshotDomain();
    final prevUpdated = updatedAt;
    await _persistDomain(before, prevUpdated, (d) async {
      final rm = _bumpRev(SyncType.txn, txnId);
      await d.upsertTransaction(updated, rev: rm.rev, by: rm.by);
    });
    notifyListeners();
  }

  // ---------- categories & budgets ----------

  Future<String> addCategory(String name, {double budget = 0}) async {
    final before = _snapshotDomain();
    final prevUpdated = updatedAt;
    final newId = _uuid.v4();
    // Fresh look for user-created categories: first palette entry not
    // taken by an existing category, cycling through the pool when the
    // palette is exhausted. Deterministic, so sync replays stay identical.
    final usedColors = categories.map((c) => c.color).toSet();
    final newColor = kColorChoices.firstWhere(
      (k) => !usedColors.contains(k),
      orElse: () => kColorChoices[categories.length % kColorChoices.length],
    );
    final usedIcons = categories.map((c) => c.icon).toSet();
    final newIcon = kIconChoices
        .firstWhere(
          (i) => !usedIcons.contains(i.codePoint),
          orElse: () => kIconChoices[categories.length % kIconChoices.length],
        )
        .codePoint;
    categories.add(
      Category(
        id: newId,
        name: name,
        icon: newIcon,
        color: newColor,
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
    return newId;
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
      // Tombstone first: saveCategories deletes the category row wholesale, so
      // a crash after it would otherwise leave the category gone with nothing
      // recording the deletion. See deleteTransaction.
      await d.saveTombstone(tomb);
      await d.saveCategories(categories);
      await d.saveTransactions(transactions);
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
      // Tombstone first, then the row -- see deleteTransaction.
      await d.saveTombstone(tomb);
      await d.deleteLoan(id);
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

  // Memoized monthly analytics (Phase 6): the dashboard calls all three
  // aggregates on every build, and the historical triple-scan rebuilt
  // DateTimes per transaction per call (~1.4s at 50k). Keyed on
  // updatedAt, which every data mutation touches, so settings-only
  // rebuilds (theme, navigation) reuse the cached summary for free.
  String _analyticsKey = '';
  MonthlyAnalytics? _analyticsCache;

  MonthlyAnalytics monthly(DateTime month) {
    final period = appCalendar.periodOf(month);
    final key = '$updatedAt|$calendarSystem|${period.index}';
    final hit = _analyticsCache;
    if (hit != null && _analyticsKey == key) return hit;
    final fresh = computeMonthlyAnalytics(
      transactions,
      month,
      periodStart: period.start,
      periodEnd: period.end,
    );
    _analyticsKey = key;
    _analyticsCache = fresh;
    return fresh;
  }

  List<Txn> monthTxns(DateTime month) {
    final period = appCalendar.periodOf(month);
    final start = period.start.millisecondsSinceEpoch;
    final end = period.end.millisecondsSinceEpoch;
    return transactions.where((t) => t.date >= start && t.date < end).toList();
  }

  double monthSpend(DateTime month) => monthly(month).spend;

  double monthIncome(DateTime month) => monthly(month).income;

  Map<String, double> spendByCategory(DateTime month) =>
      Map.of(monthly(month).byCategory);

  // Memoized Insights summaries. The key is the data revision (updatedAt)
  // plus the period; clearing the map on a revision change keeps every
  // period cached while settings-only rebuilds reuse the last result.
  // The day is part of the revision because the per-day average depends on
  // how much of the window has elapsed.
  String _insightsRevision = '';
  final Map<InsightPeriod, InsightsAnalytics> _insightsCache = {};

  InsightsAnalytics insights(InsightPeriod period) {
    final now = DateTime.now();
    final revision =
        '$updatedAt|$calendarSystem|${now.year}-${now.month}-${now.day}';
    if (_insightsRevision != revision) {
      _insightsRevision = revision;
      _insightsCache.clear();
    }
    return _insightsCache.putIfAbsent(
      period,
      () => computeInsights(
        transactions,
        now,
        period,
        asOf: now,
        calendar: appCalendar,
      ),
    );
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
      // Tombstone first: a crash after deleteProject would otherwise leave the
      // project gone with nothing recording the deletion. See deleteTransaction.
      await d.saveTombstone(tomb);
      await d.deleteProject(id);
      await d.saveTransactions(transactions);
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
    userName: userName,
    categories: List<Category>.from(categories),
    accounts: List<Account>.from(accounts),
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
  /// them all; [dropTombstonesForPresent] drops them for ids the snapshot
  /// contains. Restored-over
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
    // Old snapshots carry no accounts: seed the deterministic defaults so
    // every device derives the same ids from the same legacy modes.
    accounts = remote.accounts.isEmpty ? defaultAccounts() : remote.accounts;
    transactions = remote.transactions;
    loans = remote.loans;
    projects = remote.projects;
    final present = <String>{
      for (final c in categories) _mkey(SyncType.cat, c.id),
      for (final a in accounts) _mkey(SyncType.acct, a.id),
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
    // Backups carry the display name (optional field; older exports have
    // none) so a restore on another device greets the same person.
    if (remote.userName.isNotEmpty) {
      userName = remote.userName;
    }
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

  /// User-picked file import: v1 and v2 payloads both merge record-level,
  /// and records the file still contains come back even if this device had
  /// deleted them (file-restore UX). The old v1 path gated the whole file
  /// on `updatedAt`, so re-importing your own export (equal timestamps)
  /// reported "Already up to date" and imported nothing. A true
  /// point-in-time snapshot restore stays with Local backups -> Restore
  /// (force) or erase-all + import.
  Future<String> importFilePayload(String raw) async {
    final fmt = V2Snapshot.detectFormat(raw);
    if (fmt == 2) return _importV2File(raw);
    if (fmt == 1) return _importV1File(raw);
    return 'Could not read that file.';
  }

  /// Applies the merge result and, for v1 file imports, pulls the backup's
  /// display name (optional field; empty in older exports = no change).
  /// [preImportJson] (the explicit file-import path only) becomes a rolling
  /// backup when the import changes anything — same safety net the old
  /// whole-replace import had.
  Future<String> _importMerged(
    ({bool changed, int adopted, int tombs, String? error}) r, {
    String adoptedName = '',
    String preImportJson = '',
  }) async {
    if (r.error != null) {
      return 'Could not save the import. Nothing was changed.';
    }
    if (r.changed && preImportJson.isNotEmpty) {
      _pushBackup(preImportJson);
    }
    if (adoptedName.isNotEmpty && adoptedName != userName) {
      await setUserName(adoptedName);
    }
    if (!r.changed) {
      return 'Nothing new to import - this device already has '
          'everything in the file.';
    }
    final n = r.adopted + r.tombs;
    return 'Imported $n change${n == 1 ? '' : 's'} from the file.';
  }

  Future<String> _importV2File(String raw) async {
    final snap = V2Snapshot.tryDecode(raw);
    if (snap == null) return 'Could not read that sync data.';
    if (!_v2ready) await _ensureV2Init(_prefs!);
    final drop = <String>{
      for (final rec in snap.records)
        if (!rec.dead) rec.key,
    };
    final preJson = exportJson();
    return _importMerged(
      await _mergeAndApply(snap.records, dropTombstonesFor: drop),
      preImportJson: preJson,
    );
  }

  Future<String> _importV1File(String raw) async {
    final Snapshot remote;
    try {
      remote = Snapshot.decode(raw);
    } catch (_) {
      return 'Could not read that file.';
    }
    if (!_v2ready) await _ensureV2Init(_prefs!);
    final drop = <String>{
      for (final c in remote.categories) '${SyncType.cat}/${c.id}',
      for (final t in remote.transactions) '${SyncType.txn}/${t.id}',
      for (final p in remote.projects) '${SyncType.proj}/${p.id}',
      for (final l in remote.loans) ...[
        '${SyncType.loan}/${l.id}',
        for (final t in l.topups) '${SyncType.topup}/${t.id}',
        for (final r in l.repayments) '${SyncType.repay}/${r.id}',
      ],
    };
    final preJson = exportJson();
    return _importMerged(
      await _mergeAndApply(v1ToRev0Records(remote), dropTombstonesFor: drop),
      adoptedName: remote.userName,
      preImportJson: preJson,
    );
  }

  // ---------- Snapshot v2 (record-level sync) ----------

  static Map<String, dynamic> _catContent(Category c, int order) => {
    ...c.toJson(),
    'sortOrder': order,
  };

  static Map<String, dynamic> _acctContent(Account a, int order) => {
        ...a.toJson(),
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
    for (var i = 0; i < accounts.length; i++) {
      final a = accounts[i];
      final m = _metaFor(SyncType.acct, a.id);
      out.add(
        SyncRecord(
          type: SyncType.acct,
          id: a.id,
          rev: m.rev,
          by: m.by,
          data: _acctContent(a, i),
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
    for (var i = 0; i < snap.accounts.length; i++) {
      final a = snap.accounts[i];
      out.add(
        SyncRecord(
          type: SyncType.acct,
          id: a.id,
          rev: 0,
          by: '',
          data: _acctContent(a, i),
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

    // Accounts: deterministic defaults are added when a peer has none, so
    // two devices converging from old snapshots never create duplicates.
    final acctRecs = <SyncRecord>[
      for (final r in result.records.values)
        if (r.type == SyncType.acct && !r.dead) r,
    ];
    for (final d in defaultAccounts()) {
      if (!acctRecs.any((r) => r.id == d.id)) {
        acctRecs.add(
          SyncRecord(
            type: SyncType.acct,
            id: d.id,
            rev: 0,
            by: '',
            data: _acctContent(d, d.sortOrder),
          ),
        );
      }
    }
    acctRecs.sort((a, b) {
      final s = sortOf(a).compareTo(sortOf(b));
      return s != 0 ? s : a.id.compareTo(b.id);
    });
    var mergedAccounts = [
      for (final r in acctRecs)
        Account.fromJson(Map<String, dynamic>.from(r.data ?? {'id': r.id})),
    ];
    if (mergedAccounts.isEmpty ||
        mergedAccounts.every((a) => a.archived)) {
      mergedAccounts = [
        for (var i = 0; i < mergedAccounts.length; i++)
          i == 0
              ? mergedAccounts[i].copyWith(archived: false)
              : mergedAccounts[i],
      ];
      if (mergedAccounts.isEmpty) mergedAccounts = defaultAccounts();
    }

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

    final acctIds = {for (final a in mergedAccounts) a.id};
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
          accountId: acctIds.contains('${d['accountId'] ?? ''}')
              ? '${d['accountId']}'
              : '',
          projectId: projId,
        ),
      );
      meta[_mkey(r.type, r.id)] = RecordMeta(rev: r.rev, by: r.by);
    }
    for (final r in acctRecs) {
      meta[_mkey(SyncType.acct, r.id)] = RecordMeta(rev: r.rev, by: r.by);
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
        accounts: mergedAccounts,
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
  ///
  /// [dropTombstonesFor] removes local tombstones for those `type/id` keys
  /// before merging — used by file imports, where a record the file still
  /// contains should come back (file-restore UX). Safe: a dropped tombstone
  /// means the file holds a live record for the id, so the merge always
  /// adopts it and the result is applied (no memory/database divergence).
  ///
  /// Held under the write lock: the merge is computed from in-memory state
  /// and then written as a wholesale replace, so it must not interleave with
  /// another writer (see [_serialized]).
  Future<({bool changed, int adopted, int tombs, String? error})>
  _mergeAndApply(
    List<SyncRecord> remote, {
    Set<String> dropTombstonesFor = const {},
  }) => _serialized(() => _mergeAndApplyLocked(remote, dropTombstonesFor));

  Future<({bool changed, int adopted, int tombs, String? error})>
  _mergeAndApplyLocked(
    List<SyncRecord> remote,
    Set<String> dropTombstonesFor,
  ) async {
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
        if (!dropTombstonesFor.contains(t.key))
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
      accounts = mat.data.accounts.isEmpty ? defaultAccounts() : mat.data.accounts;
      transactions = mat.data.transactions;
      loans = mat.data.loans;
      projects = mat.data.projects;
      _revs = mat.meta;
      _tombs = {for (final t in mat.tombs) t.key: t};
      _sortTxns();
      // Tell the next write that the copy it built its edit against is stale.
      _mergeOverwroteMemory = true;
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
