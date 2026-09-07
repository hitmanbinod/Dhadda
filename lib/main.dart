import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:provider/provider.dart';

import 'format.dart';

import 'screens/add_screen.dart';
import 'screens/history_screen.dart';
import 'screens/menu_screen.dart';
import 'screens/home_screen.dart';
import 'screens/lent_screen.dart';
import 'screens/lock_screen.dart';
import 'screens/sync_screen.dart';
import 'security.dart';
import 'store.dart';
import 'sync/link_sync.dart';
import 'sync/reminders.dart';
import 'sync/sms.dart';

void main() {
  runApp(const ExpenseApp());
}

class ExpenseApp extends StatelessWidget {
  const ExpenseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ExpenseStore()..load(),
      child: Consumer<ExpenseStore>(
        builder: (_, store, _) {
          final seed = (store.materialYou &&
                  store.dynamicSeedArgb != null)
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
            theme: ThemeData(
              colorScheme: ColorScheme.fromSeed(seedColor: seed),
              useMaterial3: true,
            ),
            darkTheme: ThemeData(
              colorScheme: ColorScheme.fromSeed(
                  seedColor: seed, brightness: Brightness.dark),
              useMaterial3: true,
            ),
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

class _RootShellState extends State<RootShell>
    with WidgetsBindingObserver {
  int _index = 0;
  late final LinkEngine _link;
  bool _smsBootDone = false;
  bool _lockChecked = false;
  bool _locked = false;
  PinVault? _vault;

  static const _titles = ['Home', 'History', 'Lent', 'Menu'];

  static const _destinations = [
    NavigationDestination(
        icon: Icon(Icons.home_outlined),
        selectedIcon: Icon(Icons.home),
        label: 'Home'),
    NavigationDestination(
        icon: Icon(Icons.receipt_long_outlined),
        selectedIcon: Icon(Icons.receipt_long),
        label: 'History'),
    NavigationDestination(
        icon: Icon(Icons.handshake_outlined),
        selectedIcon: Icon(Icons.handshake),
        label: 'Lent'),
    NavigationDestination(
        icon: Icon(Icons.menu_outlined),
        selectedIcon: Icon(Icons.menu),
        label: 'Menu'),
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
    WidgetsBinding.instance.addObserver(this);
    _checkLock();
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
  Future<void> _autoSms(ExpenseStore store) async {
    if (store.smsMode != 'auto') return;
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
          categoryId: categorizeSms(
              merchant: c.merchant,
              body: c.body,
              candidates: store.categories),
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'Added $added entr${added == 1 ? 'y' : 'ies'} from SMS automatically.')));
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _link.stop();
    try {
      context.read<ExpenseStore>().removeListener(_maybeAutoSms);
    } catch (_) {}
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _link.syncNow();
      final store = context.read<ExpenseStore>();
      Reminders.refresh(store);
      _autoSms(store);
    }
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
        if (mounted) setState(() => _locked = false);
      }
    } catch (_) {
      // No biometrics enrolled - the PIN pad stays.
    }
  }

  void _go(int i) => setState(() => _index = i);

  void _openAdd() {
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => AddScreen(
            onSaved: () => Navigator.of(context).pop())));
  }

  @override
  Widget build(BuildContext context) {
    if (!_lockChecked) {
      return const Scaffold(
          body: Center(child: CircularProgressIndicator()));
    }
    final vault = _vault;
    if (_locked && vault != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Dhadda - Locked')),
        body: LockScreen(
            vault: vault,
            onUnlock: () => setState(() => _locked = false)),
      );
    }

    final pages = [
      HomeScreen(
        onAdd: _openAdd,
        onSync: () => _link.syncNow(),
      ),
      const HistoryScreen(),
      const LentScreen(),
      MenuScreen(engine: _link),
    ];
    final wide = MediaQuery.widthOf(context) > 900;
    final store = context.watch<ExpenseStore>();

    return Scaffold(
      appBar: AppBar(
        title: _index == 0
            ? Text(
                homeGreeting(store.userName, DateTime.now()),
                overflow: TextOverflow.ellipsis,
              )
            : Text(_titles[_index]),
        actions: [
          IconButton(
            tooltip: 'Sync',
            icon: const Icon(Icons.sync),
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => SyncScreen(engine: _link)));
            },
          ),
        ],
      ),
      body: Row(
        children: [
          if (wide)
            NavigationRail(
              selectedIndex: _index,
              onDestinationSelected: _go,
              labelType: NavigationRailLabelType.all,
              destinations: [
                for (final d in _destinations)
                  NavigationRailDestination(
                      icon: d.icon,
                      selectedIcon: d.selectedIcon,
                      label: Text(d.label)),
              ],
            ),
          Expanded(
            child: IndexedStack(index: _index, children: pages),
          ),
        ],
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: _go,
              destinations: _destinations,
            ),
    );
  }
}