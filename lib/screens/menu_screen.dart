import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:provider/provider.dart';

import '../security.dart';
import '../store.dart';
import '../sync/sms.dart';
import '../version.dart';
import '../format.dart';
import '../widgets/page.dart';
import '../widgets/backup_password.dart';
import '../sync/link_sync.dart';
import '../sync/backup_crypto.dart';
import '../sync/file_sync.dart';
import 'sync_screen.dart';

/// Menu tab: sync entry, appearance, security, currency, data, about.
class MenuScreen extends StatefulWidget {
  final LinkEngine engine;
  const MenuScreen({super.key, required this.engine});

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  PinVault? _vault;
  bool _bioSupported = false;
  final _smsSender = TextEditingController();

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _smsSender.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final v = await PinVault.open();
    var bio = false;
    if (!kIsWeb) {
      try {
        bio = await LocalAuthentication().isDeviceSupported();
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _vault = v;
        _bioSupported = bio;
      });
    }
  }

  void _say(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// Top-level backup actions (same calls as the Sync screen copy).
  Future<void> _exportBackup(BuildContext context, ExpenseStore store) async {
    await FileSync.exportJson(
      context,
      store.exportJson(),
      FileSync.fileNameFor(DateTime.now()),
    );
  }

  Future<void> _importBackup(BuildContext context, ExpenseStore store) async {
    final raw = await FileSync.importJson();
    if (raw == null) return; // cancelled
    if (!context.mounted) return;
    final payload = await _maybeDecrypt(context, raw);
    if (payload == null) return; // cancelled or wrong password (told)
    final msg = await store.importFilePayload(payload);
    store.noteSynced();
    _say(msg);
  }

  /// Password-gated encrypted export (additive; plaintext Export untouched).
  Future<void> _exportEncrypted(
      BuildContext context, ExpenseStore store) async {
    final pw = await askBackupPassword(context, confirm: true);
    if (pw == null || !context.mounted) return;
    try {
      final enc = await BackupCrypto.encrypt(store.exportJson(), pw);
      await FileSync.exportJson(
        context,
        enc,
        FileSync.fileNameFor(DateTime.now())
            .replaceFirst('.json', '.enc.json'),
      );
    } catch (_) {
      _say('Could not encrypt the backup.');
    }
  }

  /// Returns cleartext for the picked file: decrypts encrypted envelopes
  /// (asking for the passphrase) and passes everything else through.
  /// Returns null when the user cancels or decryption fails (already told).
  Future<String?> _maybeDecrypt(BuildContext context, String raw) async {
    if (!BackupCrypto.isEncrypted(raw)) return raw;
    final pw = await askBackupPassword(context, confirm: false);
    if (pw == null || !context.mounted) return null;
    try {
      return await BackupCrypto.decrypt(raw, pw);
    } catch (e) {
      _say(e is FormatException ? e.message : 'Could not decrypt.');
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ExpenseStore>();
    final vault = _vault;
    return ListView(
      padding: pageInsets(context),
      children: [
        Card(
          child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.person)),
            title: Text(
              store.userName.isEmpty ? 'Set your name' : store.userName,
            ),
            trailing: IconButton(
              tooltip: 'Edit name',
              icon: const Icon(Icons.edit),
              onPressed: () => _nameDialog(context, store),
            ),
          ),
        ),
        const SizedBox(height: 16),
        // ---------- sync ----------
        Card(
          child: ListTile(
            leading: Icon(
              store.linked ? Icons.link : Icons.link_off,
              color: store.linked ? Colors.green : null,
            ),
            title: Text(
              store.linked ? 'Linked with ${store.linkPeer}' : 'Not linked',
            ),
            subtitle: Text(
              store.linked
                  ? (store.linkStatus.isEmpty
                        ? 'Auto-sync is on'
                        : store.linkStatus)
                  : 'Pair once - then auto-sync on same WiFi',
            ),
            trailing: FilledButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SyncScreen(engine: widget.engine),
                ),
              ),
              child: const Text('Open sync'),
            ),
          ),
        ),
        const SizedBox(height: 16),
        // ---------- backup (top-level copy; Sync keeps its own) ----------
        Text('Backup', style: Theme.of(context).textTheme.titleMedium),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Your data, your file. Export to share or archive it, import it back on any device.',
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => _exportBackup(context, store),
                        icon: const Icon(Icons.upload),
                        label: const Text('Export'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _importBackup(context, store),
                        icon: const Icon(Icons.download),
                        label: const Text('Import'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _exportEncrypted(context, store),
                    icon: const Icon(Icons.lock_outline),
                    label: const Text('Encrypted backup…'),
                  ),
                ),
                const Text(
                  'Encrypted backups need a passphrase (not the app PIN) to open. Import detects them automatically.',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        // ---------- appearance ----------
        Text('Appearance', style: Theme.of(context).textTheme.titleMedium),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final (v, label, icon) in const [
                      ('light', 'Light', Icons.light_mode),
                      ('system', 'Auto', Icons.settings_suggest),
                      ('dark', 'Dark', Icons.dark_mode),
                    ])
                      ChoiceChip(
                        label: Text(label),
                        avatar: Icon(icon, size: 18),
                        showCheckmark: false,
                        selected: store.themeMode == v,
                        onSelected: (_) => store.setThemeMode(v),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  leading: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: Color(store.accent),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  ),
                  title: const Text('Accent colour'),
                  subtitle: Text(ExpenseStore.accentName(store.accent)),
                  children: [
                    GridView.count(
                      crossAxisCount: 3,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      children: [
                        if (!ExpenseStore.accentChoices.contains(store.accent))
                          _swatch(context, store, store.accent, true),
                        for (final c in ExpenseStore.accentChoices)
                          _swatch(context, store, c, false),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: () => _pickCustom(context, store),
                        icon: const Icon(Icons.palette),
                        label: const Text('Custom colour…'),
                      ),
                    ),
                    if (!kIsWeb &&
                        defaultTargetPlatform == TargetPlatform.android)
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: const Text('Match wallpaper'),
                        subtitle: const Text('Material You, Android 12+'),
                        value: store.materialYou,
                        onChanged: (v) => store.setMaterialYou(v),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        // ---------- security ----------
        Text('Security', style: Theme.of(context).textTheme.titleMedium),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(Icons.lock),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        vault == null
                            ? 'Checking...'
                            : (vault.isEnabled
                                  ? 'PIN lock is ON (4 digits)'
                                  : 'PIN lock is off'),
                      ),
                    ),
                  ],
                ),
                if (vault != null && !vault.isEnabled)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton(
                        onPressed: () => _enablePin(vault),
                        child: const Text('Set PIN'),
                      ),
                    ),
                  ),
                if (vault != null && vault.isEnabled) ...[
                  OverflowBar(
                    children: [
                      TextButton(
                        onPressed: () => _changePin(vault),
                        child: const Text('Change'),
                      ),
                      TextButton(
                        onPressed: () => _disablePin(vault),
                        child: const Text('Disable'),
                      ),
                    ],
                  ),
                  if (_bioSupported)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      secondary: const Icon(Icons.fingerprint),
                      title: const Text('Fingerprint'),
                      subtitle: const Text('Unlock without typing the PIN'),
                      value: vault.biometric,
                      onChanged: (v) => _toggleBio(vault, v),
                    ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        // ---------- currency ----------
        Text('Currency', style: Theme.of(context).textTheme.titleMedium),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: store.currency,
              decoration: const InputDecoration(
                labelText: 'Display currency',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final c in ExpenseStore.currencySymbols.keys)
                  DropdownMenuItem(
                    value: c,
                    child: Text('$c - ${ExpenseStore.currencyNames[c]}'),
                  ),
              ],
              onChanged: (v) async {
                if (v == null) return;
                await store.setCurrency(v);
                _say('Currency set to $v.');
              },
            ),
          ),
        ),
        const SizedBox(height: 16),
        // ---------- data ----------
        Text('Data', style: Theme.of(context).textTheme.titleMedium),
        if (!kIsWeb)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.sms_outlined),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'SMS import',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            Text(
                              'Auto adds on open · Manual asks first',
                              style: TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      SegmentedButton<String>(
                        showSelectedIcon: false,
                        style: SegmentedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                        segments: const [
                          ButtonSegment(value: 'manual', label: Text('Manual')),
                          ButtonSegment(value: 'auto', label: Text('Auto')),
                        ],
                        selected: {store.smsMode},
                        onSelectionChanged: (s) => store.setSmsMode(s.first),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Only these senders are scanned - everything else is ignored as junk.',
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _smsSender,
                          textCapitalization: TextCapitalization.characters,
                          decoration: const InputDecoration(
                            labelText: 'Sender (eSewa, Nabil…)',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          onSubmitted: (_) => _addSmsSender(store),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Add sender',
                        icon: const Icon(Icons.add),
                        onPressed: () => _addSmsSender(store),
                      ),
                    ],
                  ),
                  if (store.smsSenders.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 0,
                      children: [
                        for (final s in store.smsSenders)
                          Chip(
                            label: Text(s),
                            deleteIcon: const Icon(Icons.close, size: 18),
                            onDeleted: () => store.setSmsSenders([
                              for (final e in store.smsSenders)
                                if (e != s) e,
                            ]),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: () => _importSms(context, store),
                    icon: const Icon(Icons.download),
                    label: const Text('Scan SMS now'),
                  ),
                ],
              ),
            ),
          ),
        if (!kIsWeb) const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: const Icon(Icons.delete_forever, color: Colors.red),
            title: const Text('Erase all data'),
            subtitle: const Text('Wipes everything on THIS device only'),
            trailing: TextButton(
              onPressed: () => _erase(context, store),
              child: const Text('Erase', style: TextStyle(color: Colors.red)),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text('About', style: Theme.of(context).textTheme.titleMedium),
        const Card(
          child: ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('Expense $kAppVersion ($kBuildStamp)'),
            subtitle: Text('Local-first • offline • free forever'),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Private by design: data lives on your devices. No account, no server fees, ever.',
        ),
      ],
    );
  }

  Future<void> _nameDialog(BuildContext context, ExpenseStore store) async {
    final ctrl = TextEditingController(text: store.userName);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Your name'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Shown in the home greeting',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await store.setUserName(ctrl.text);
    }
  }

  // ---------- PIN (4 digits) ----------

  Future<String?> _askPin(String title) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          obscureText: true,
          maxLength: 4,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '4-digit PIN',
            border: OutlineInputBorder(),
            counterText: '',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    final pin = ctrl.text.trim();
    if (ok != true) return null;
    if (pin.length != 4 || int.tryParse(pin) == null) {
      _say('PIN must be exactly 4 digits.');
      return null;
    }
    return pin;
  }

  Future<void> _enablePin(PinVault vault) async {
    final first = await _askPin('Set a 4-digit PIN');
    if (first == null || !mounted) return;
    final second = await _askPin('Repeat the PIN');
    if (second == null || !mounted) return;
    if (first != second) {
      _say('PINs do not match.');
      return;
    }
    await vault.setPin(first);
    setState(() {});
    _say('PIN lock enabled.');
  }

  Future<void> _changePin(PinVault vault) async {
    final cur = await _askPin('Current PIN');
    if (cur == null || !mounted) return;
    final throttle = PinThrottle(vault.prefs);
    if (throttle.delayRemaining() > Duration.zero) {
      _say('Too many attempts - try again shortly.');
      return;
    }
    if (!vault.verify(cur)) {
      await throttle.recordFailure();
      _say('Wrong PIN.');
      return;
    }
    final first = await _askPin('New 4-digit PIN');
    if (first == null || !mounted) return;
    final second = await _askPin('Repeat the new PIN');
    if (second == null || !mounted) return;
    if (first != second) {
      _say('PINs do not match.');
      return;
    }
    await vault.setPin(first);
    setState(() {});
    _say('PIN changed.');
  }

  Future<void> _disablePin(PinVault vault) async {
    final cur = await _askPin('Current PIN to disable lock');
    if (cur == null || !mounted) return;
    final throttle = PinThrottle(vault.prefs);
    if (throttle.delayRemaining() > Duration.zero) {
      _say('Too many attempts - try again shortly.');
      return;
    }
    if (!vault.verify(cur)) {
      await throttle.recordFailure();
      _say('Wrong PIN.');
      return;
    }
    await vault.clear();
    await vault.setBiometric(false);
    setState(() {});
    _say('PIN lock disabled.');
  }

  Future<void> _toggleBio(PinVault vault, bool on) async {
    if (on) {
      try {
        final ok = await LocalAuthentication().authenticate(
          localizedReason: 'Enable fingerprint unlock',
          biometricOnly: true,
        );
        if (!ok) return;
      } catch (_) {
        _say('Fingerprint unavailable - enroll one first.');
        return;
      }
    }
    await vault.setBiometric(on);
    setState(() {});
    _say(on ? 'Fingerprint unlock on.' : 'Fingerprint unlock off.');
  }

  Widget _swatch(
    BuildContext context,
    ExpenseStore store,
    int color,
    bool custom,
  ) {
    final selected = store.accent == color;
    return GestureDetector(
      onTap: () =>
          custom ? _pickCustom(context, store) : store.setAccent(color),
      child: Container(
        decoration: BoxDecoration(
          color: Color(color),
          shape: BoxShape.circle,
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.onSurface
                : Colors.transparent,
            width: 3,
          ),
        ),
      ),
    );
  }

  Future<void> _pickCustom(BuildContext context, ExpenseStore store) async {
    var picked = Color(store.accent);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pick an accent'),
        content: SingleChildScrollView(
          child: ColorPicker(
            color: picked,
            onColorChanged: (c) => picked = c,
            pickersEnabled: const <ColorPickerType, bool>{
              ColorPickerType.both: false,
              ColorPickerType.primary: false,
              ColorPickerType.accent: false,
              ColorPickerType.bw: false,
              ColorPickerType.custom: false,
              ColorPickerType.customSecondary: false,
              ColorPickerType.wheel: true,
            },
            enableShadesSelection: true,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Use'),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await store.setAccent(picked.toARGB32());
    }
  }

  Future<void> _addSmsSender(ExpenseStore store) async {
    final v = _smsSender.text;
    if (v.trim().length < 2) return;
    _smsSender.clear();
    await store.setSmsSenders([...store.smsSenders, v]);
  }

  /// Opt-in SMS import: reads bank/wallet texts, parses candidates,
  /// user ticks what to keep. Nothing is saved without confirmation.
  Future<void> _importSms(BuildContext context, ExpenseStore store) async {
    final messenger = ScaffoldMessenger.of(context);
    final allowed = await SmsReader.ensurePermission();
    if (!mounted) return;
    if (!allowed) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('SMS permission needed - enable it to scan texts.'),
        ),
      );
      return;
    }
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Reading SMS…'),
        duration: Duration(seconds: 1),
      ),
    );
    final rows = await SmsReader.readInbox(limit: 100);
    if (!mounted) return;
    final seen = await SmsReader.importedIds();
    final found = <SmsCandidate>[];
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
      if (c != null) found.add(c);
    }
    if (found.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('No new bank/wallet SMS found.')),
      );
      return;
    }
    if (!context.mounted) return;
    final picked = await _pickSmsDialog(context, found);
    if (picked == null || picked.isEmpty || !mounted) return;
    for (final c in picked) {
      await store.addTransaction(
        type: c.isIncome ? 'income' : 'expense',
        amount: c.amount,
        categoryId: categorizeSms(
          merchant: c.merchant,
          body: c.body,
          candidates: store.categories,
        ),
        date: c.date,
        note: c.merchant.isEmpty ? c.sender : c.merchant,
        mode: c.mode,
      );
    }
    await SmsReader.markImported(picked.map((c) => c.id));
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Added ${picked.length} entr${picked.length == 1 ? 'y' : 'ies'} from SMS.',
        ),
      ),
    );
  }

  Future<List<SmsCandidate>?> _pickSmsDialog(
    BuildContext context,
    List<SmsCandidate> found,
  ) {
    final picked = {for (final c in found) c.id};
    return showDialog<List<SmsCandidate>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text('Add ${picked.length} from SMS?'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: found.length,
              itemBuilder: (ctx, i) {
                final c = found[i];
                return CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: picked.contains(c.id),
                  onChanged: (v) => setD(() {
                    if (v == true) {
                      picked.add(c.id);
                    } else {
                      picked.remove(c.id);
                    }
                  }),
                  title: Text(
                    '${c.isIncome ? '+' : '-'}${money(c.amount)} ${c.merchant.isEmpty ? c.sender : c.merchant}',
                  ),
                  subtitle: Text('${c.sender} · ${dayStr(c.date)}'),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(ctx)
                      .pop(found.where((c) => picked.contains(c.id)).toList()),
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _erase(BuildContext context, ExpenseStore store) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Erase everything?'),
        content: const Text(
          'All expenses, loans, events and settings on THIS device will be deleted. The other device keeps its copy.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Erase'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Last chance'),
        content: const Text('There is no undo. Really erase?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Erase everything'),
          ),
        ],
      ),
    );
    if (sure != true || !context.mounted) return;
    await store.eraseAll();
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('All data erased.')));
    }
  }
}
