import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show LogicalKeyboardKey, SystemUiOverlayStyle;
import 'package:local_auth/local_auth.dart';
import 'package:provider/provider.dart';

import 'screens/add_screen.dart';
import 'screens/database_problem_screen.dart';
import 'screens/history_screen.dart';
import 'screens/home_screen.dart';
import 'screens/insights_screen.dart';
import 'screens/lent_screen.dart';
import 'screens/lock_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/sync_screen.dart';
import 'receipts.dart';
import 'security.dart';
import 'store.dart';
import 'sync/link_sync.dart';
import 'sync/reminders.dart';
import 'sync/sms.dart';
import 'theme/app_theme.dart';
import 'theme/palette.dart';
import 'theme/tokens.dart';
import 'theme/typography.dart';
import 'widgets/profile_avatar.dart';
import 'widget_bridge.dart';

void main() {
  runApp(const ExpenseApp());
}

/// Navigator key for the app's root navigator.
///
/// The lock gate replaces `home`, but screens like SyncScreen and AddScreen
/// are pushed onto this navigator, where they sit *above* the locked home and
/// stay mounted, visible and interactive. Holding the key lets the shell pop
/// those routes away when it re-locks, so a backgrounded app can never come
/// back to a live pairing screen showing the PIN and link secret.
final GlobalKey<NavigatorState> kRootNavigatorKey = GlobalKey<NavigatorState>();

class ExpenseApp extends StatelessWidget {
  const ExpenseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ExpenseStore()..load(),
      child: Consumer<ExpenseStore>(
        builder: (_, store, _) {
          final seed = (store.materialYou && store.dynamicSeedArgb != null)
              ? Color(store.dynamicSeedArgb!)
              : Color(store.accent);
          final mode = switch (store.themeMode) {
            'light' => ThemeMode.light,
            'dark' => ThemeMode.dark,
            _ => ThemeMode.system,
          };
          return MaterialApp(
            title: 'Dhadda',
            debugShowCheckedModeBanner: false,
            navigatorKey: kRootNavigatorKey,
            theme: AppTheme.build(seed, Brightness.light),
            darkTheme: AppTheme.build(seed, Brightness.dark),
            themeMode: mode,
            home: const RootShell(),
          );
        },
      ),
    );
  }
}

class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> with WidgetsBindingObserver {
  int _index = 0;
  String? _quickAction;
  late final LinkEngine _link;
  final HistoryDayRequest _historyDay = HistoryDayRequest();
  final HistorySearchRequest _historySearch = HistorySearchRequest();
  final HomeMonthRequest _homeMonth = HomeMonthRequest();
  final TextEditingController _topSearch = TextEditingController();
  bool _smsBootDone = false;
  bool _smsBusy = false;
  bool _lockChecked = false;
  bool _locked = false;
  PinVault? _vault;

  static const _destinations = [
    NavigationDestination(
      icon: Icon(Icons.home_outlined),
      selectedIcon: Icon(Icons.home),
      label: 'Home',
    ),
    NavigationDestination(
      icon: Icon(Icons.receipt_long_outlined),
      selectedIcon: Icon(Icons.receipt_long),
      label: 'History',
    ),
    NavigationDestination(
      icon: Icon(Icons.bar_chart_outlined),
      selectedIcon: Icon(Icons.bar_chart),
      label: 'Insights',
    ),
    NavigationDestination(
      icon: Icon(Icons.handshake_outlined),
      selectedIcon: Icon(Icons.handshake),
      label: 'Lent',
    ),
  ];

  @override
  void initState() {
    super.initState();
    final store = context.read<ExpenseStore>();
    _link = LinkEngine(store);
    _link.start();
    store.onLoansChanged = () => Reminders.refresh(store);
    Reminders.refresh(store);
    store.addListener(_maybeAutoSms);
    _cleanReceipts(store);
    WidgetsBinding.instance.addObserver(this);
    _initWidgets();
    _checkLock();
  }

  void _initWidgets() {
    WidgetBridge.listen(_onQuickAction);
    WidgetBridge.takeQuickAction().then(_onQuickAction);
  }

  void _onQuickAction(String? action) {
    if (action == null || !mounted) return;
    setState(() => _quickAction = action);
    WidgetsBinding.instance.addPostFrameCallback((_) => _applyQuickAction());
  }

  /// A widget tap never bypasses the PIN gate: it waits until unlock.
  void _applyQuickAction() {
    final action = _quickAction;
    if (action == null || !mounted || _locked) return;
    _quickAction = null;
    if (action == 'lent') {
      setState(() => _index = 3);
      return;
    }
    kRootNavigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => AddScreen(
          initialIsExpense: action != 'income',
          onSaved: () => kRootNavigatorKey.currentState?.pop(),
        ),
      ),
    );
  }

  Future<void> _cleanReceipts(ExpenseStore store) async {
    try {
      final receipts = await ReceiptStore.create();
      await receipts.cleanOrphans({
        for (final t in store.transactions) t.id,
      });
    } catch (_) {}
  }

  /// First store load done: run one SMS auto-import if enabled.
  void _maybeAutoSms() {
    if (_smsBootDone) return;
    final store = context.read<ExpenseStore>();
    if (!store.loaded) return;
    _smsBootDone = true;
    _autoSms(store);
  }

  /// Auto mode: silently add new allow-listed SMS (already-imported
  /// ids never repeat). Needs no UI; manual mode never calls this.
  /// Single-flight: boot and resume can both fire this; overlapping runs
  /// would parse the same inbox rows before either marks them imported
  /// and double-import. Later calls while one is in flight are dropped
  /// (the next lifecycle event retries).
  Future<void> _autoSms(ExpenseStore store) async {
    if (store.smsMode != 'auto') return;
    if (_smsBusy) return;
    _smsBusy = true;
    try {
      await _runAutoSms(store);
    } finally {
      _smsBusy = false;
    }
  }

  Future<void> _runAutoSms(ExpenseStore store) async {
    try {
      final rows = await SmsReader.readInbox(limit: 60);
      if (!mounted) return;
      final seen = await SmsReader.importedIds();
      final fresh = <String>[];
      var added = 0;
      for (final r in rows) {
        final id = '${r['id'] ?? ''}';
        if (id.isEmpty || seen.contains(id)) continue;
        final c = parseSms(
          id: id,
          sender: '${r['sender'] ?? ''}',
          body: '${r['body'] ?? ''}',
          dateMs: r['date'] is int
              ? r['date'] as int
              : DateTime.now().millisecondsSinceEpoch,
          allowedSenders: store.smsSenders,
        );
        if (c == null) continue;
        await store.addTransaction(
          type: c.isIncome ? 'income' : 'expense',
          amount: c.amount,
          accountId: store.accountIdForModeOrDefault(c.mode),
          categoryId: store.categoryRuleFor(
                c.merchant.isEmpty ? c.body : c.merchant,
                c.isIncome ? 'income' : 'expense',
              )?.categoryId ??
              categorizeSms(
                merchant: c.merchant,
                body: c.body,
                candidates: store.categories,
              ),
          date: c.date,
          note: c.merchant.isEmpty ? c.sender : c.merchant,
          mode: c.mode,
        );
        fresh.add(id);
        added++;
      }
      if (fresh.isNotEmpty) {
        await SmsReader.markImported(fresh);
      }
      if (added > 0 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Added $added entr${added == 1 ? 'y' : 'ies'} from SMS automatically.',
            ),
          ),
        );
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _link.stop();
    _historyDay.dispose();
    _historySearch.dispose();
    _homeMonth.dispose();
    _topSearch.dispose();
    try {
      context.read<ExpenseStore>().removeListener(_maybeAutoSms);
    } catch (_) {}
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      WidgetBridge.refresh();
      _link.syncNow();
      final store = context.read<ExpenseStore>();
      Reminders.refresh(store);
      _autoSms(store);
    } else if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      // Re-lock when the app leaves the foreground. Without this, the
      // lock only guarded process death: background -> recents -> return
      // skipped the PIN/biometric entirely. Any lock screen showing a
      // moment later (e.g. lock-only-on-boot behavior in tests) is the
      // same contract: lock state re-derives from the vault.
      final vault = _vault;
      if (vault != null && vault.isEnabled) {
        // Drop every pushed route before locking. The lock gate only replaces
        // `home`; anything pushed onto the root navigator (SyncScreen with its
        // pairing PIN and link secret, AddScreen) would otherwise stay mounted
        // and interactive above it, so returning from the background would
        // show the pairing screen instead of the PIN pad.
        _popToRoot();
        setState(() => _locked = true);
      }
    }
  }

  /// Pops every route above the first one. Safe to call when nothing is pushed
  /// and when the navigator is not mounted yet.
  void _popToRoot() {
    final nav = kRootNavigatorKey.currentState;
    if (nav == null) return;
    nav.popUntil((route) => route.isFirst);
  }

  Future<void> _checkLock() async {
    final v = await PinVault.open();
    if (!mounted) return;
    setState(() {
      _vault = v;
      _locked = v.isEnabled;
      _lockChecked = true;
    });
    // Biometric fast-path: fingerprint/face instead of typing the PIN.
    if (v.isEnabled && v.biometric && !kIsWeb) {
      await _tryBiometric();
    }
  }

  Future<void> _tryBiometric() async {
    try {
      final ok = await LocalAuthentication().authenticate(
        localizedReason: 'Unlock Expense',
        biometricOnly: true,
      );
      // Biometric success proves the user: reset PIN-failure delays too.
      if (ok && mounted) {
        final v = _vault;
        if (v != null) await PinThrottle(v.prefs).recordSuccess();
        if (mounted) {
          setState(() => _locked = false);
          WidgetsBinding.instance
              .addPostFrameCallback((_) => _applyQuickAction());
        }
      }
    } catch (_) {
      // No biometrics enrolled - the PIN pad stays.
    }
  }

  void _go(int i) => setState(() => _index = i);

  /// Home's rhythm strip: filter History to that day, then switch tabs.
  void _openHistoryDay(DateTime day) {
    _historyDay.open(day);
    setState(() => _index = 1);
  }

  /// Insights "How you pay": filter History to that account, then switch.
  void _openHistoryAccount(String accountId) {
    _historyDay.openAccount(accountId);
    setState(() => _index = 1);
  }

  void _openAdd() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AddScreen(onSaved: () => Navigator.of(context).pop()),
      ),
    );
  }

  void _openSync() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => SyncScreen(engine: _link)));
  }

  void _openSettings() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => SettingsScreen(engine: _link)));
  }

  /// Desktop sidebar brand block: logo + name + quiet tagline.
  Widget _sidebarBrand(BuildContext context) {
    final colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Spacing.sm,
        Spacing.sm,
        Spacing.sm,
        Spacing.lg,
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: colors.accent,
              borderRadius: BorderRadius.circular(Radii.card),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(Radii.icon),
              child: Image.asset(
                'assets/icon/app_icon.png',
                width: 32,
                height: 32,
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(width: Spacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Dhadda',
                  style: AppType.title.copyWith(color: colors.textPrimary),
                ),
                Text(
                  'a quiet ledger',
                  style: AppType.caption.copyWith(color: colors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sidebarFooter(BuildContext context) {
    final colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.sm),
      child: Text(
        'Dhadda 1.5 · offline',
        textAlign: TextAlign.center,
        style: AppType.caption.copyWith(color: colors.textSecondary),
      ),
    );
  }

  /// Desktop top bar: page title, search, theme toggle, Add, avatar.
  Widget _topBar(BuildContext context, ExpenseStore store, AppColors colors) {
    final titles = ['Home', 'History', 'Insights', 'Lent'];
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: Spacing.xl),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.hairline)),
      ),
      child: Row(
        children: [
          Text(
            titles[_index],
            style: AppType.title.copyWith(color: colors.textPrimary),
          ),
          const Spacer(),
          SizedBox(
            width: 220,
            child: TextField(
              key: const Key('web-topbar-search'),
              controller: _topSearch,
              onChanged: (value) {
                _historySearch.setQuery(value);
                _go(1);
              },
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search, size: 18),
                hintText: 'Search entries',
                filled: true,
                fillColor: colors.surface2,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(Radii.input),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: Spacing.sm),
          IconButton(
            key: const Key('web-theme-toggle'),
            tooltip: 'Toggle theme',
            icon: const Icon(Icons.brightness_6_outlined, size: 20),
            onPressed: () => store.setThemeMode(
              store.themeMode == 'light'
                  ? 'dark'
                  : store.themeMode == 'dark'
                  ? 'system'
                  : 'light',
            ),
          ),
          const SizedBox(width: Spacing.xs),
          FilledButton.icon(
            key: const Key('web-topbar-add'),
            onPressed: _openAdd,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add'),
          ),
          const SizedBox(width: Spacing.sm),
          SettingsAvatarButton(
            name: store.userName,
            style: store.avatarStyle,
            onTap: _openSettings,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ExpenseStore>();
    final colors = AppColors.of(context);
    // Never fall through to the app when the database would not open: an
    // empty tracker is indistinguishable from deleted data.
    if (store.databaseProblem.isNotEmpty) {
      return DatabaseProblemScreen(
        message: store.lastQuarantinedDb.isEmpty
            ? store.databaseProblem
            : '$store.databaseProblem A copy was kept as '
                  '${store.lastQuarantinedDb}.',
        onRetry: () => store.retryAfterDatabaseProblem(),
        onStartEmpty: () => store.startEmptyAfterDatabaseProblem(),
      );
    }
    if (!_lockChecked) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final vault = _vault;
    if (_locked && vault != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Dhadda - Locked')),
        body: LockScreen(
          vault: vault,
          onUnlock: () {
            setState(() => _locked = false);
            WidgetsBinding.instance
                .addPostFrameCallback((_) => _applyQuickAction());
          },
        ),
      );
    }

    final pages = [
      HomeScreen(
        onAdd: _openAdd,
        onSync: () => _link.syncNow(),
        onOpenSync: _openSync,
        onOpenSettings: _openSettings,
        onSeeAll: () => _go(1),
        onOpenDay: _openHistoryDay,
        monthRequest: _homeMonth,
      ),
      HistoryScreen(
        onOpenSync: _openSync,
        onOpenSettings: _openSettings,
        dayRequest: _historyDay,
        searchRequest: _historySearch,
      ),
      InsightsScreen(
        onOpenSettings: _openSettings,
        onOpenAccount: _openHistoryAccount,
      ),
      LentScreen(onOpenSettings: _openSettings),
    ];
    final wide = MediaQuery.widthOf(context) > 900;
    // Every tab draws its own large title now (Settings is a pushed route),
    // so the shell only owns the navigation chrome.

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        SingleActivator(LogicalKeyboardKey.keyN): () => _shortcut(() {
          _openAdd();
        }),
        SingleActivator(LogicalKeyboardKey.slash): () => _shortcut(() {
          _go(1);
          _historySearch.focus();
        }),
        SingleActivator(LogicalKeyboardKey.bracketLeft): () => _shortcut(() {
          _go(0);
          _homeMonth.page(-1);
        }),
        SingleActivator(LogicalKeyboardKey.bracketRight): () => _shortcut(() {
          _go(0);
          _homeMonth.page(1);
        }),
        SingleActivator(LogicalKeyboardKey.digit1): () => _shortcut(() => _go(0)),
        SingleActivator(LogicalKeyboardKey.digit2): () => _shortcut(() => _go(1)),
        SingleActivator(LogicalKeyboardKey.digit3): () => _shortcut(() => _go(2)),
        SingleActivator(LogicalKeyboardKey.digit4): () => _shortcut(() => _go(3)),
        SingleActivator(LogicalKeyboardKey.escape): () {
          final nav = kRootNavigatorKey.currentState;
          if (nav != null && nav.canPop()) nav.pop();
        },
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value:
            (Theme.of(context).brightness == Brightness.dark
                    ? SystemUiOverlayStyle.light
                    : SystemUiOverlayStyle.dark)
                .copyWith(statusBarColor: Colors.transparent),
        child: SafeArea(
          top: true,
          bottom: false,
          child: Row(
            children: [
              if (wide)
                SizedBox(
                  width: 224,
                  child: NavigationRail(
                    extended: true,
                    selectedIndex: _index,
                    onDestinationSelected: _go,
                    leading: _sidebarBrand(context),
                    trailing: _sidebarFooter(context),
                    destinations: [
                      for (final d in _destinations)
                        NavigationRailDestination(
                          icon: d.icon,
                          selectedIcon: d.selectedIcon,
                          label: Text(d.label),
                        ),
                    ],
                  ),
                ),
              Expanded(
                child: Column(
                  children: [
                    if (wide) _topBar(context, store, colors),
                    Expanded(
                      child: IndexedStack(index: _index, children: pages),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: _go,
              destinations: _destinations,
            ),
        ),
      ),
    );
  }

  /// Keyboard shortcuts must not fire while the user is typing in a field.
  void _shortcut(VoidCallback action) {
    final focus = FocusManager.instance.primaryFocus;
    if (focus?.context?.widget is EditableText) return;
    action();
  }
}
