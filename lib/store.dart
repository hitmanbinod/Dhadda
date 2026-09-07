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
  static const _uuid = Uuid();

  DomainStore? _domain;
  bool _ownsDomain = false;

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
      if (_domain is! PrefsDomainStore) {
        await _migrateLegacyToDb(p);
      }
    }
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
        debugPrint('Dhadda: SQLite unavailable ($e); prefs backend for now.');
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
      debugPrint('Dhadda: DB migration failed, staying on prefs ($e)');
      _domain = PrefsDomainStore(p);
    }
  }

  /// Write-through for domain mutations. Awaited by mutators; failures are
  /// logged, never thrown into the UI. In-memory state stays authoritative
  /// for the session (same exposure class as prefs writes before Phase 2).
  Future<void> _persistDomain(Future<void> Function(DomainStore) op) async {
    final d = _domain;
    if (d == null) return;
    try {
      await op(d);
    } catch (e) {
      debugPrint('Dhadda: domain persist failed ($e)');
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
  Future<void> setLink({
    required String id,
    required String pin,
    required String peer,
  }) async {
    linkId = id;
    linkPin = pin;
    linkPeer = peer;
    linkStatus = 'Linked with $peer.';
    _saveAll();
    notifyListeners();
  }

  /// Forgets a pairing (data stays, auto-sync stops).
  Future<void> clearLink([String why = '']) async {
    linkId = '';
    linkPin = '';
    linkPeer = '';
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
    linkId = '';
    linkPin = '';
    linkPeer = '';
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
    await _persistDomain((d) => d.upsertTransaction(txn));
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
    await _persistDomain((d) => d.upsertTransaction(updated));
    notifyListeners();
    return true;
  }

  Future<void> deleteTransaction(String id) async {
    transactions.removeWhere((t) => t.id == id);
    _touch();
    await _persistDomain((d) => d.deleteTransaction(id));
    notifyListeners();
  }

  /// Puts back a deleted entry (Undo). Keeps id/date so sync stays sane.
  Future<void> restoreTransaction(Txn txn) async {
    if (transactions.any((t) => t.id == txn.id)) return;
    transactions.add(txn);
    _sortTxns();
    _touch();
    await _persistDomain((d) => d.upsertTransaction(txn));
    notifyListeners();
  }

  // ---------- categories & budgets ----------

  Future<void> addCategory(String name, {double budget = 0}) async {
    categories.add(
      Category(
        id: _uuid.v4(),
        name: name,
        icon: 0xe148,
        color: 0xFF607D8B,
        budget: budget,
      ),
    );
    _touch();
    await _persistDomain((d) => d.saveCategories(categories));
    notifyListeners();
  }

  Future<void> setBudget(String id, double budget) async {
    final i = categories.indexWhere((c) => c.id == id);
    if (i < 0) return;
    final c = categories[i];
    categories[i] = Category(
      id: c.id,
      name: c.name,
      icon: c.icon,
      color: c.color,
      budget: budget,
    );
    _touch();
    await _persistDomain((d) => d.saveCategories(categories));
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
    categories[i] = Category(
      id: c.id,
      name: n.isEmpty ? c.name : n,
      icon: icon ?? c.icon,
      color: color ?? c.color,
      budget: budget ?? c.budget,
    );
    _touch();
    await _persistDomain((d) => d.saveCategories(categories));
    notifyListeners();
  }

  /// Deletes a category (never 'other'); its entries move to Other.
  Future<bool> deleteCategory(String id) async {
    if (id == 'other') return false;
    if (!categories.any((c) => c.id == id)) return false;
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
    await _persistDomain((d) => d.saveCategories(categories));
    await _persistDomain((d) => d.saveTransactions(transactions));
    notifyListeners();
    return true;
  }

  /// Moves a category up (delta -1) or down (+1) in the user order.
  Future<void> moveCategory(String id, int delta) async {
    final i = categories.indexWhere((c) => c.id == id);
    final j = i + delta;
    if (i < 0 || j < 0 || j >= categories.length) return;
    final c = categories.removeAt(i);
    categories.insert(j, c);
    _touch();
    await _persistDomain((d) => d.saveCategories(categories));
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
    final c = categories.removeAt(i);
    categories.insert(j, c);
    _touch();
    await _persistDomain((d) => d.saveCategories(categories));
    notifyListeners();
  }

  // ---------- lent-money ledger ----------

  Future<void> addLoan({
    required String person,
    required double amount,
    required DateTime date,
    String note = '',
    DateTime? due,
  }) async {
    loans.add(
      Loan(
        id: _uuid.v4(),
        person: person,
        lent: amount,
        dateLent: date.millisecondsSinceEpoch,
        dueDate: due?.millisecondsSinceEpoch,
        note: note,
        kind: 'lent',
      ),
    );
    _touch();
    await _persistDomain((d) => d.upsertLoan(loans.last));
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
    loans.add(
      Loan(
        id: _uuid.v4(),
        person: person,
        lent: amount,
        dateLent: date.millisecondsSinceEpoch,
        dueDate: due?.millisecondsSinceEpoch,
        note: note,
        kind: 'borrowed',
      ),
    );
    _touch();
    await _persistDomain((d) => d.upsertLoan(loans.last));
    notifyListeners();
    _loansChanged();
  }

  /// One-time reminder moment (null = off). Past moments fire nothing.
  Future<void> setReminderAt(String loanId, DateTime? when) async {
    final i = loans.indexWhere((l) => l.id == loanId);
    if (i < 0) return;
    final l = loans[i];
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
    await _persistDomain((d) => d.upsertLoan(loans[i]));
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
    final reps = List<Repayment>.from(l.repayments)
      ..add(
        Repayment(
          id: _uuid.v4(),
          amount: amount,
          date: date.millisecondsSinceEpoch,
          note: note,
        ),
      );
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
    await _persistDomain((d) => d.upsertLoan(loans[i]));
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
    final tops = List<Topup>.from(l.topups)
      ..add(
        Topup(
          id: _uuid.v4(),
          amount: amount,
          date: date.millisecondsSinceEpoch,
          note: note,
        ),
      );
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
    await _persistDomain((d) => d.upsertLoan(loans[i]));
    notifyListeners();
    _loansChanged();
  }

  Future<void> deleteLoan(String id) async {
    loans.removeWhere((l) => l.id == id);
    _touch();
    await _persistDomain((d) => d.deleteLoan(id));
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
    projects.add(
      Project(
        id: id,
        name: name,
        note: note,
        created: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    _touch();
    await _persistDomain((d) => d.upsertProject(projects.last));
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
    projects[i] = Project(
      id: p.id,
      name: n.isEmpty ? p.name : n,
      note: note ?? p.note,
      created: p.created,
      icon: icon ?? p.icon,
      color: color ?? p.color,
    );
    _touch();
    await _persistDomain((d) => d.upsertProject(projects[i]));
    notifyListeners();
  }

  Future<void> deleteProject(String id) async {
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
    await _persistDomain((d) => d.deleteProject(id));
    await _persistDomain((d) => d.saveTransactions(transactions));
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
  Future<String> importSnapshotString(String raw, {bool force = false}) async {
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
    categories = remote.categories.isEmpty
        ? defaultCategories()
        : remote.categories;
    transactions = remote.transactions;
    loans = remote.loans;
    projects = remote.projects;
    await _persistDomain(
      (d) => d.replaceAll(
        DomainData(
          categories: List.of(categories),
          transactions: List.of(transactions),
          loans: List.of(loans),
          projects: List.of(projects),
        ),
      ),
    );
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
}
