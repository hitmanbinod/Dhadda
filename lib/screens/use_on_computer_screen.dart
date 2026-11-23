// Prompt 3 §6: one purpose, three numbered steps, plain words.
// Android leads; the matching web pairing page arrives in Phase 4 and the
// parity row is marked "web pending" until then.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../store.dart';
import '../sync/lan_host.dart';
import '../sync/lan_server.dart';
import '../sync/link_sync.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import '../widgets/app_card.dart';
import '../widgets/page.dart';
import 'scan_screen.dart';
import 'sync_screen.dart';

const _pairingSeconds = 120;

class UseOnComputerScreen extends StatefulWidget {
  final LanHostController host;
  final LinkEngine? engine;
  const UseOnComputerScreen({super.key, required this.host, this.engine});

  @override
  State<UseOnComputerScreen> createState() => _UseOnComputerScreenState();
}

class _UseOnComputerScreenState extends State<UseOnComputerScreen> {
  Timer? _tick;
  int _ticks = 0;
  final Set<String> _shownApprovals = {};

  @override
  void initState() {
    super.initState();
    // Populate the Wi-Fi / hotspot check so Start is enabled on entry.
    unawaited(widget.host.refreshNetwork());
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
      _maybeShowApproval();
      _ticks++;
      // If the interface list was empty when the server started, keep trying
      // so the shown address becomes the real Wi-Fi one.
      final url = widget.host.url;
      if (widget.host.running &&
          (url == null || url.contains('127.0.0.1')) &&
          _ticks % 5 == 0) {
        unawaited(widget.host.refreshNetwork());
      }
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    try {
      await widget.host.start(context.read<ExpenseStore>());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not start: ${e.runtimeType}')));
      }
    }
  }

  Future<void> _scanQr() async {
    final raw = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const ScanScreen(acceptAny: true)),
    );
    if (raw == null || !mounted) return;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      if (decoded['v'] != 1) throw const FormatException('version');
      final sid = '${decoded['sid'] ?? ''}';
      final epc = _hex('${decoded['epc'] ?? ''}');
      if (sid.isEmpty || epc.length != 32) throw const FormatException('qr');
      widget.host.approveQr(sid, epc);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Connecting to your computer…')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('That is not a Dhadda pairing code.')));
      }
    }
  }

  List<int> _hex(String s) {
    final out = <int>[];
    for (var i = 0; i + 1 < s.length; i += 2) {
      out.add(int.parse(s.substring(i, i + 2), radix: 16));
    }
    return out;
  }

  void _maybeShowApproval() {
    final host = widget.host;
    if (!host.running || !mounted) return;
    final pending = host.pendingApprovals;
    for (final p in pending) {
      final sid = '${p['sid']}';
      if (_shownApprovals.contains(sid)) continue;
      _shownApprovals.add(sid);
      unawaited(_showAllowSheet(sid, '${p['name']}'));
      break;
    }
  }

  Future<void> _showAllowSheet(String sid, String name) async {
    final colors = AppColors.of(context);
    final allow = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: colors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.sheet)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Spacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Allow this computer?', style: AppType.title),
              const SizedBox(height: Spacing.sm),
              Text('$name wants to see your expenses.',
                  style: AppType.body),
              const SizedBox(height: Spacing.xs),
              Text(widget.host.trusted.isEmpty
                  ? 'You can trust it for 30 days so it connects without a code.'
                  : 'This computer will be trusted for 30 days.',
                  style: AppType.caption),
              const SizedBox(height: Spacing.lg),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('Allow'),
                ),
              ),
              const SizedBox(height: Spacing.sm),
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('Deny'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (allow == true) {
      widget.host.approve(sid);
    } else {
      widget.host.deny(sid);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return AnimatedBuilder(
      animation: widget.host,
      builder: (context, _) {
        final host = widget.host;
        final running = host.running;
        return Scaffold(
          backgroundColor: colors.background,
          appBar: AppBar(title: const Text('Use on computer')),
          body: ListView(
            padding: pageInsets(context),
            children: [
              Text(
                'See and manage your expenses on a bigger screen. '
                'Your data stays on this phone.',
                style: AppType.body.copyWith(color: colors.textSecondary),
              ),
              const SizedBox(height: Spacing.lg),
              if (!running) ...[
                _offState(host),
              ] else ...[
                _statusChip(host, colors),
                const SizedBox(height: Spacing.lg),
                _addressCard(host, colors),
                const SizedBox(height: Spacing.md),
                _codeCard(host, colors),
                const SizedBox(height: Spacing.md),
                _scanCard(colors),
                const SizedBox(height: Spacing.lg),
                _computersCard(host, colors),
                const SizedBox(height: Spacing.md),
                OutlinedButton.icon(
                  onPressed: () => host.stop(),
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: const Text('Stop'),
                ),
              ],
              const SizedBox(height: Spacing.lg),
              const Text(
                'Use only a network you trust, never public or hotel Wi-Fi.',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: Spacing.md),
              ExpansionTile(
                title: const Text('More ways to sync'),
                subtitle: const Text('Phone to phone, or a backup file'),
                children: [
                  ListTile(
                    title: const Text('Open sync and backup'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => SyncScreen(engine: widget.engine),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _offState(LanHostController host) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: host.hasAddress && !host.starting ? _start : null,
          icon: const Icon(Icons.laptop_mac_outlined),
          label: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Text(host.starting ? 'Starting…' : 'Start',
                style: AppType.button),
          ),
        ),
        const SizedBox(height: Spacing.sm),
        Text(
          host.hasAddress
              ? 'Your phone and computer must be on the same Wi-Fi, '
                  'or the computer on this phone’s hotspot.'
              : 'Connect to Wi-Fi first',
          textAlign: TextAlign.center,
          style: AppType.caption,
        ),
      ],
    );
  }

  Widget _statusChip(LanHostController host, AppColors colors) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: Spacing.md, vertical: Spacing.xs),
        decoration: BoxDecoration(
          color: colors.income.withValues(alpha: 0.12),
          borderRadius: Radii.chipRadius,
        ),
        child: Text(
          'Ready · ${host.networkName.isEmpty ? 'Wi-Fi' : host.networkName}',
          style: AppType.caption.copyWith(color: colors.income),
        ),
      ),
    );
  }

  Widget _step(int number, String title) => Row(
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: colorsOf(context).accent,
            child: Text('$number',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: Spacing.sm),
          Text(title, style: AppType.title),
        ],
      );

  AppColors colorsOf(BuildContext context) => AppColors.of(context);

  Widget _addressCard(LanHostController host, AppColors colors) {
    final url = host.url ?? '';
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _step(1, 'On your computer, open'),
          const SizedBox(height: Spacing.md),
          SelectableText(url, style: AppType.statValue),
          const SizedBox(height: Spacing.md),
          Center(
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.all(Spacing.sm),
              child: QrImageView(data: url, size: 160),
            ),
          ),
          const SizedBox(height: Spacing.sm),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: url));
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Address copied')));
                  },
                  icon: const Icon(Icons.copy_all_outlined),
                  label: const Text('Copy'),
                ),
              ),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => SharePlus.instance
                      .share(ShareParams(text: url)),
                  icon: const Icon(Icons.ios_share_outlined),
                  label: const Text('Share'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _codeCard(LanHostController host, AppColors colors) {
    final code = host.code ?? '';
    final shown = code.length == 8
        ? '${code.substring(0, 4)}-${code.substring(4)}'
        : code;
    final elapsed = host.codeAt == null
        ? 0
        : DateTime.now().difference(host.codeAt!).inSeconds;
    final left = (_pairingSeconds - elapsed).clamp(0, _pairingSeconds);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _step(2, 'Enter this code'),
          const SizedBox(height: Spacing.md),
          Row(
            children: [
              SizedBox(
                width: 52,
                height: 52,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: left / _pairingSeconds,
                      backgroundColor: colors.cardBorder.withValues(alpha: 0.25),
                    ),
                    Text('$left', style: AppType.captionStrong),
                  ],
                ),
              ),
              const SizedBox(width: Spacing.md),
              Expanded(
                child: Text(shown, style: AppType.statValue),
              ),
            ],
          ),
          const SizedBox(height: Spacing.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => host.newCode(),
              icon: const Icon(Icons.refresh),
              label: const Text('New code'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _scanCard(AppColors colors) => AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _step(3, 'Or scan the QR on your computer'),
            const SizedBox(height: Spacing.md),
            OutlinedButton.icon(
              onPressed: _scanQr,
              icon: const Icon(Icons.qr_code_scanner_outlined),
              label: const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('Scan computer’s QR'),
              ),
            ),
          ],
        ),
      );

  Widget _computersCard(LanHostController host, AppColors colors) {
    final connected = host.sessions;
    final trusted = host.trusted;
    final rows = <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(
            Spacing.lg, Spacing.md, Spacing.lg, Spacing.xs),
        child: Text('Connected computers', style: AppType.sectionTitle),
      ),
    ];
    if (connected.isEmpty && trusted.isEmpty) {
      rows.add(Padding(
        padding: const EdgeInsets.fromLTRB(
            Spacing.lg, Spacing.xs, Spacing.lg, Spacing.md),
        child: Text('No computers yet.', style: AppType.caption),
      ));
    }
    for (final s in connected) {
      final device = trusted
          .where((d) => d.id == s.deviceId)
          .cast<LanTrustedDevice>()
          .toList();
      final name = device.isEmpty ? 'This computer' : device.first.name;
      rows.add(ListTile(
        leading: Icon(Icons.laptop_mac_outlined, color: colors.income),
        title: Text(name),
        subtitle: Text(device.isEmpty
            ? 'Connected now'
            : 'Connected now · Trusted until ${_date(device.first.expires)}'),
        trailing: TextButton(
          onPressed: () => host.disconnect(s.sid),
          child: const Text('Disconnect'),
        ),
      ));
    }
    for (final d in trusted) {
      if (connected.any((s) => s.deviceId == d.id)) continue;
      rows.add(ListTile(
        leading: const Icon(Icons.laptop_outlined),
        title: Text(d.name),
        subtitle: Text('Trusted until ${_date(d.expires)}'),
        trailing: TextButton(
          onPressed: () => host.forget(d.id),
          child: const Text('Forget'),
        ),
      ));
    }
    if (trusted.isNotEmpty) {
      rows.add(Padding(
        padding: const EdgeInsets.fromLTRB(
            Spacing.lg, Spacing.sm, Spacing.lg, Spacing.md),
        child: Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => host.forgetAll(),
            child: const Text('Forget all'),
          ),
        ),
      ));
    }
    return AppCard.group(children: rows);
  }

  String _date(DateTime value) =>
      '${value.day} ${_month(value.month)}';

  String _month(int m) => const [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ][m - 1];
}

