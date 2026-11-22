import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:provider/provider.dart';

import '../receipts.dart';
import '../security.dart';
import '../store.dart';
import '../sync/sms.dart';
import '../version.dart';
import '../format.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import '../widgets/app_card.dart';
import '../widgets/page.dart';
import '../widgets/profile_avatar.dart';
import '../widgets/settings_row.dart';
import '../widgets/backup_password.dart';
import '../sync/link_sync.dart';
import '../sync/backup_crypto.dart';
import '../sync/file_sync.dart';
import 'accounts_screen.dart';
import 'category_rules_screen.dart';
import 'edit_home_screen.dart';
import 'sync_screen.dart';
import 'web_access_screen.dart';

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
    BuildContext context,
    ExpenseStore store,
  ) async {
    final pw = await askBackupPassword(context, confirm: true);
    if (pw == null || !context.mounted) return;
    try {
      final enc = await BackupCrypto.encrypt(store.exportJson(), pw);
      if (!context.mounted) return;
      await FileSync.exportJson(
        context,
        enc,
        FileSync.fileNameFor(DateTime.now()).replaceFirst('.json', '.enc.json'),
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
    final colors = AppColors.of(context);

    return SwitchTheme(
      data: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? colors.onAccent
              : colors.textSecondary;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? colors.accent
              : colors.track;
        }),
        trackOutlineColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? Colors.transparent
              : colors.cardBorder;
        }),
      ),
      child: ListView(
        padding: pageInsets(context),
        children: [
          // ---------- account ----------
          AppCard(
            key: const Key('settings-account-card'),
            padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
            onTap: () => _accountDialog(context, store),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Spacing.lg,
                vertical: Spacing.sm,
              ),
              child: Row(
                children: [
                  ProfileAvatar(
                    name: store.userName,
                    style: store.avatarStyle,
                    size: 44,
                  ),
                  const SizedBox(width: Spacing.md),
                  Expanded(
                    child: Text(
                      store.userName.isEmpty ? 'Set your name' : store.userName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.title.copyWith(color: colors.textPrimary),
                    ),
                  ),
                  const SizedBox(width: Spacing.sm),
                  Icon(Icons.edit_outlined, size: 20, color: colors.accent),
                ],
              ),
            ),
          ),

          // ---------- appearance ----------
          const SettingsSectionTitle('Appearance'),
          SettingsCard(
            children: [
              SettingsRow(
                icon: Icons.brightness_6_outlined,
                title: 'Theme',
                subtitle: 'Light, Auto or Dark',
                content: PillSegments(
                  fullWidth: true,
                  labels: const ['Light', 'Auto', 'Dark'],
                  selected: const ['light', 'system', 'dark']
                      .indexOf(store.themeMode),
                  onChanged: (i) =>
                      store.setThemeMode(const ['light', 'system', 'dark'][i]),
                ),
              ),
            ],
          ),
          const SizedBox(height: Spacing.lg),
          SettingsCard(
            children: [
              SettingsRow(
                icon: Icons.palette_outlined,
                title: 'Accent colour',
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: Color(store.accent),
                        shape: BoxShape.circle,
                        border: Border.all(color: colors.cardBorder),
                      ),
                    ),
                    const SizedBox(width: Spacing.sm),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 104),
                      child: Text(
                        ExpenseStore.accentName(store.accent),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.caption.copyWith(
                          fontSize: 12,
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(width: Spacing.xs),
                    const SettingsChevron(),
                  ],
                ),
                onTap: () => _accentDialog(context, store),
              ),
              if (!kIsWeb &&
                  defaultTargetPlatform == TargetPlatform.android)
                SettingsSwitchRow(
                  icon: Icons.wallpaper_outlined,
                  title: 'Match wallpaper',
                  subtitle: 'Material You, Android 12+',
                  value: store.materialYou,
                  onChanged: (v) => store.setMaterialYou(v),
                ),
            ],
          ),

          // ---------- preferences ----------
          const SettingsSectionTitle('Preferences'),
          SettingsCard(
            children: [
              SettingsRow(
                icon: Icons.calendar_month_outlined,
                title: 'Calendar',
                subtitle: 'Date display and grouping',
                note: store.calendarSystem == 'bs'
                    ? 'Calendar data for 2084 onward is an estimate and may '
                        'be corrected in an update.'
                    : null,
                trailing: PillSegments(
                  compact: true,
                  labels: const ['AD', 'BS'],
                  keys: const [
                    Key('settings-calendar-ad'),
                    Key('settings-calendar-bs'),
                  ],
                  selected: store.calendarSystem == 'bs' ? 1 : 0,
                  onChanged: (i) =>
                      store.setCalendarSystem(i == 0 ? 'ad' : 'bs'),
                ),
              ),
            ],
          ),
          const SizedBox(height: Spacing.lg),
          SettingsCard(
            children: [
              SettingsSwitchRow(
                switchKey: const Key('settings-hide-balance'),
                icon: Icons.visibility_off_outlined,
                title: 'Hide balance on launch',
                subtitle: 'Mask amounts until tapped',
                value: store.hideBalance,
                onChanged: (v) => store.setHideBalance(v),
              ),
              SettingsSwitchRow(
                switchKey: const Key('settings-one-handed'),
                icon: Icons.front_hand_outlined,
                title: 'One-handed mode',
                subtitle: 'Tabs and toggles near the thumb',
                value: store.oneHanded,
                onChanged: (v) => store.setOneHanded(v),
              ),
              SettingsRow(
                key: const Key('settings-edit-home'),
                icon: Icons.dashboard_customize_outlined,
                title: 'Edit Home',
                subtitle: 'Choose sections and their order',
                trailing: const SettingsChevron(),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const EditHomeScreen()),
                ),
              ),
            ],
          ),

          // ---------- money ----------
          const SettingsSectionTitle('Money'),
          SettingsCard(
            children: [
              SettingsRow(
                icon: Icons.currency_exchange_outlined,
                title: 'Display currency',
                subtitle:
                    '${store.currency} - ${ExpenseStore.currencyNames[store.currency]}',
                trailing: const SettingsChevron(),
                onTap: () => _currencyDialog(context, store),
              ),
              SettingsRow(
                key: const Key('settings-accounts'),
                icon: Icons.account_balance_wallet_outlined,
                title: 'Accounts',
                subtitle: 'Name the ways you pay',
                trailing: const SettingsChevron(),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AccountsScreen()),
                ),
              ),
              SettingsRow(
                key: const Key('settings-auto-category'),
                icon: Icons.auto_awesome_outlined,
                title: 'Auto-category rules',
                subtitle: 'Suggest categories from note text',
                trailing: const SettingsChevron(),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const CategoryRulesScreen(),
                  ),
                ),
              ),
            ],
          ),

          // ---------- security ----------
          const SettingsSectionTitle('Security'),
          SettingsCard(
            children: [
              SettingsRow(
                icon: Icons.lock_outlined,
                title: vault == null
                    ? 'PIN lock'
                    : (vault.isEnabled ? 'PIN lock is on' : 'PIN lock is off'),
                subtitle: vault == null
                    ? 'Checking…'
                    : (vault.isEnabled
                        ? '4 digits'
                        : 'Protect the app on launch'),
                trailing: const SettingsChevron(),
                onTap: vault == null ? null : () => _pinDialog(context, vault),
              ),
              if (vault != null && vault.isEnabled && _bioSupported)
                SettingsSwitchRow(
                  icon: Icons.fingerprint,
                  title: 'Fingerprint',
                  subtitle: 'Unlock without typing the PIN',
                  value: vault.biometric,
                  onChanged: (v) => _toggleBio(vault, v),
                ),
            ],
          ),

          // ---------- data ----------
          const SettingsSectionTitle('Data'),
          SettingsCard(
            children: [
              FutureBuilder(
                future: ReceiptStore.create().then((s) => s.usage()),
                builder: (context, snapshot) {
                  final usage = snapshot.data;
                  return SettingsRow(
                    icon: Icons.receipt_long_outlined,
                    title: 'Receipts',
                    subtitle: usage == null
                        ? 'Photos stay on this phone'
                        : '${usage.count} photos · ${formatBytes(usage.bytes)}',
                    trailing: TextButton(
                      onPressed: usage == null || usage.count == 0
                          ? null
                          : () => _clearReceipts(context),
                      child: const Text('Clear all'),
                    ),
                  );
                },
              ),
              SettingsRow(
                icon: Icons.language_outlined,
                title: 'Web access',
                subtitle: 'Pair this phone with Dhadda on the web',
                trailing: const SettingsChevron(),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const WebAccessScreen()),
                ),
              ),
            ],
          ),
          const SizedBox(height: Spacing.lg),
          SettingsCard(
            children: [
              SettingsRow(
                icon: Icons.backup_outlined,
                title: 'Backup & transfer',
                subtitle: 'Export to share or archive, import on any device',
                content: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () => _exportBackup(context, store),
                            icon: const Icon(Icons.upload_outlined),
                            label: const Text('Export'),
                          ),
                        ),
                        const SizedBox(width: Spacing.md),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _importBackup(context, store),
                            icon: const Icon(Icons.download_outlined),
                            label: const Text('Import'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: Spacing.sm),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => _exportEncrypted(context, store),
                        icon: const Icon(Icons.lock_outline),
                        label: const Text('Encrypted backup…'),
                      ),
                    ),
                    const SizedBox(height: Spacing.xs),
                    Text(
                      'Encrypted backups need a passphrase, not the app PIN.',
                      style: AppType.caption.copyWith(
                        fontSize: 11.5,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // ---------- sync ----------
          const SettingsSectionTitle('Sync'),
          SettingsCard(
            children: [
              SettingsRow(
                icon: store.linked ? Icons.link : Icons.link_off,
                iconColor: store.linked ? colors.income : null,
                title: store.linked
                    ? 'Linked with ${store.linkPeer}'
                    : 'Not linked',
                subtitle: store.linked
                    ? (store.linkStatus.isEmpty
                        ? 'Auto-sync is on'
                        : store.linkStatus)
                    : 'Pair once, then auto-sync on the same WiFi',
                trailing: FilledButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SyncScreen(engine: widget.engine),
                    ),
                  ),
                  child: const Text('Open sync'),
                ),
              ),
            ],
          ),

          // ---------- SMS ----------
          if (!kIsWeb) ...[
            const SettingsSectionTitle('SMS'),
            SettingsCard(
              children: [
                SettingsRow(
                  icon: Icons.sms_outlined,
                  title: 'SMS import',
                  subtitle: 'Auto adds on open · Manual asks first',
                  trailing: PillSegments(
                    compact: true,
                    labels: const ['Manual', 'Auto'],
                    selected: store.smsMode == 'auto' ? 1 : 0,
                    onChanged: (i) =>
                        store.setSmsMode(i == 0 ? 'manual' : 'auto'),
                  ),
                ),
                SettingsRow(
                  icon: Icons.block_outlined,
                  title: 'Allowed senders',
                  subtitle: 'Only these senders are scanned',
                  content: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _smsSender,
                              textCapitalization:
                                  TextCapitalization.characters,
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
                        const SizedBox(height: Spacing.xs),
                        Wrap(
                          spacing: Spacing.sm,
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
                    ],
                  ),
                ),
                SettingsRow(
                  icon: Icons.download_outlined,
                  title: 'Scan SMS now',
                  subtitle: 'Import bank and wallet texts',
                  trailing: const SettingsChevron(),
                  onTap: () => _importSms(context, store),
                ),
              ],
            ),
          ],

          // ---------- about ----------
          const SettingsSectionTitle('About'),
          SettingsCard(
            children: [
              SettingsRow(
                icon: Icons.info_outlined,
                title: 'Dhadda Expense $kAppVersion',
                subtitle: 'Local-first · offline · free forever',
                note: 'Built $kBuildStamp',
              ),
              SettingsRow(
                icon: Icons.person_outline,
                title: 'Developer',
                subtitle: 'Binod Acharya',
                content: const SelectableText(
                  'binod.acharya@example.com',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),

          const SizedBox(height: Spacing.lg),
          SettingsCard(
            children: [
              SettingsRow(
                icon: Icons.delete_forever_outlined,
                destructive: true,
                title: 'Erase all data',
                subtitle: 'Wipes everything on THIS device only',
                trailing: const SettingsChevron(destructive: true),
                onTap: () => _erase(context, store),
              ),
            ],
          ),
          const SizedBox(height: Spacing.xl),
          Text(
            'Private by design: data lives on your devices. '
            'No account, no server fees, ever.',
            style: AppType.caption.copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }

  /// One sheet for the account name and avatar style. Tapping the account
  /// card, its avatar or the pencil all land here.
  Future<void> _accountDialog(BuildContext context, ExpenseStore store) async {
    final name = TextEditingController(text: store.userName);
    var style = store.avatarStyle;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Account & avatar'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: ProfileAvatar(name: name.text, style: style, size: 56),
                ),
                const SizedBox(height: Spacing.lg),
                TextField(
                  controller: name,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  onChanged: (_) => setD(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Your name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: Spacing.md),
                const Text('Avatar style'),
                const SizedBox(height: Spacing.xs),
                Wrap(
                  spacing: Spacing.sm,
                  children: [
                    ChoiceChip(
                      key: const Key('settings-avatar-minimal'),
                      label: const Text('Minimal'),
                      avatar: const Icon(Icons.text_fields, size: 18),
                      showCheckmark: false,
                      selected: style == 'minimal',
                      onSelected: (_) => setD(() => style = 'minimal'),
                    ),
                    ChoiceChip(
                      key: const Key('settings-avatar-classic'),
                      label: const Text('Classic'),
                      avatar: const Icon(Icons.person, size: 18),
                      showCheckmark: false,
                      selected: style == 'classic',
                      onSelected: (_) => setD(() => style = 'classic'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const Key('settings-account-save'),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (result != true || !context.mounted) return;
    await store.setUserName(name.text);
    await store.setAvatarStyle(style);
  }

  /// Accent swatches, moved out of the row into a picker sheet.
  Future<void> _accentDialog(BuildContext context, ExpenseStore store) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Accent colour'),
        content: Consumer<ExpenseStore>(
          builder: (ctx, s, _) => SingleChildScrollView(
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                if (!ExpenseStore.accentChoices.contains(s.accent))
                  _swatch(ctx, s, s.accent, true),
                for (final c in ExpenseStore.accentChoices)
                  _swatch(ctx, s, c, false),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
          OutlinedButton.icon(
            onPressed: () => _pickCustom(ctx, store),
            icon: const Icon(Icons.palette_outlined),
            label: const Text('Custom…'),
          ),
        ],
      ),
    );
  }

  /// Currency picker as a navigation row instead of an always-open dropdown.
  Future<void> _currencyDialog(BuildContext context, ExpenseStore store) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Display currency'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final c in ExpenseStore.currencySymbols.keys)
                ListTile(
                  dense: true,
                  title: Text('$c - ${ExpenseStore.currencyNames[c]}'),
                  trailing: store.currency == c
                      ? Icon(Icons.check, color: AppColors.of(ctx).accent)
                      : null,
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    if (!context.mounted) return;
                    await store.setCurrency(c);
                    _say('Currency set to $c.');
                  },
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  /// PIN status plus the existing Set / Change / Disable actions.
  Future<void> _pinDialog(BuildContext context, PinVault vault) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('PIN lock'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              vault.isEnabled ? 'On · 4 digits' : 'Off',
              style: AppType.body.copyWith(
                color: AppColors.of(ctx).textSecondary,
              ),
            ),
            const SizedBox(height: Spacing.md),
            if (!vault.isEnabled)
              FilledButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  _enablePin(vault);
                },
                child: const Text('Set PIN'),
              )
            else ...[
              TextButton.icon(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  _changePin(vault);
                },
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Change PIN'),
              ),
              TextButton.icon(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  _disablePin(vault);
                },
                icon: const Icon(Icons.lock_open_outlined),
                label: const Text('Disable PIN'),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _clearReceipts(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear all receipts?'),
        content: const Text(
          'This deletes every receipt photo on this phone. Entries and '
          'amounts are not affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Last chance'),
        content: const Text('There is no undo for deleted photos.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete photos'),
          ),
        ],
      ),
    );
    if (sure != true || !context.mounted) return;
    await (await ReceiptStore.create()).clearAll();
    if (!context.mounted) return;
    _say('All receipts cleared.');
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

  /// One fixed-size colour swatch: thin outline always, a primary ring,
  /// ripple feedback and a check mark when selected.
  Widget _swatch(
    BuildContext context,
    ExpenseStore store,
    int color,
    bool custom,
  ) {
    final selected = store.accent == color;
    return Tooltip(
      message: custom ? 'Custom colour' : ExpenseStore.accentName(color),
      child: Material(
        color: Colors.transparent,
        shape: CircleBorder(
          side: BorderSide(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outline.withValues(alpha: 0.6),
            width: 2,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Material(
            color: Color(color),
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () =>
                  custom ? _pickCustom(context, store) : store.setAccent(color),
              child: SizedBox(
                width: 38,
                height: 38,
                child: Icon(
                  Icons.check,
                  size: 20,
                  color: selected ? Colors.white : Colors.transparent,
                ),
              ),
            ),
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
            showColorCode: true,
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
        content: const Text(
          'There is no undo. This also removes the app lock (PIN/biometric) '
          'and all settings. Really erase?',
        ),
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
