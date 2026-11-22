import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../store.dart';
import '../sync/cloud_sync.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import '../widgets/app_card.dart';
import '../widgets/page.dart';

/// Settings → Web access. One-time pairing plus sync controls.
/// No QR encoder: the pairing link can be copied or shared with the platform
/// share sheet. The link is also the recovery key.
class WebAccessScreen extends StatefulWidget {
  const WebAccessScreen({super.key});

  @override
  State<WebAccessScreen> createState() => _WebAccessScreenState();
}

class _WebAccessScreenState extends State<WebAccessScreen> {
  late final CloudSync _sync;
  String? _link;
  String _status = 'Loading…';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _sync = CloudSync(context.read<ExpenseStore>());
    _init();
  }

  Future<void> _init() async {
    await _sync.load();
    if (!mounted) return;
    setState(() => _status = _sync.isPaired ? 'Connected' : 'Not connected');
  }

  Future<void> _act(Future<void> Function() fn, [String? message]) async {
    setState(() => _busy = true);
    try {
      await fn();
      if (!mounted) return;
      setState(() => _status = message ?? (_sync.isPaired ? 'Connected' : 'Not connected'));
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'Sync error (tap for details)');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Web access')),
      backgroundColor: colors.background,
      body: ListView(
        padding: pageInsets(context),
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Status', style: AppType.caption.copyWith(color: colors.textSecondary)),
                const SizedBox(height: Spacing.xs),
                Text(_status, style: AppType.title),
                const SizedBox(height: Spacing.sm),
                if (_sync.isPaired)
                  Wrap(
                    spacing: Spacing.sm,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _busy ? null : () => _act(() async { await _sync.pushAll(); await _sync.push(); }, 'Synced just now'),
                        icon: const Icon(Icons.sync),
                        label: const Text('Sync now'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _busy ? null : () => _act(() async { await _sync.pull(); }, 'Synced just now'),
                        icon: const Icon(Icons.download_outlined),
                        label: const Text('Pull now'),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: Spacing.lg),
          if (_sync.isPaired)
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Pairing link', style: AppType.caption.copyWith(color: colors.textSecondary)),
                  const SizedBox(height: Spacing.xs),
                  const Text('Anyone with this link can read your data. Do not post it. '
                      'The link is also your recovery key.', style: TextStyle(fontSize: 12)),
                  const SizedBox(height: Spacing.md),
                  FilledButton.icon(
                    onPressed: _busy ? null : () => _act(() async {
                      final link = await _sync.createLink();
                      if (!mounted) return;
                      setState(() => _link = link);
                      await Clipboard.setData(ClipboardData(text: link));
                    }, 'New link created'),
                    icon: const Icon(Icons.link),
                    label: const Text('Create new link'),
                  ),
                  if (_link != null) ...[
                    const SizedBox(height: Spacing.sm),
                    SelectableText(_link!, style: const TextStyle(fontSize: 12)),
                  ],
                ],
              ),
            )
          else
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Create a link once, then open it in your browser. '
                      'Your browser stays signed in via the link.'),
                  const SizedBox(height: Spacing.md),
                  FilledButton.icon(
                    onPressed: _busy ? null : () => _act(() async {
                      final link = await _sync.createLink();
                      if (!mounted) return;
                      setState(() => _link = link);
                      await Clipboard.setData(ClipboardData(text: link));
                    }, 'Link created and copied'),
                    icon: const Icon(Icons.link),
                    label: const Text('Create link'),
                  ),
                  if (_link != null) ...[
                    const SizedBox(height: Spacing.sm),
                    SelectableText(_link!, style: const TextStyle(fontSize: 12)),
                  ],
                ],
              ),
            ),
          const SizedBox(height: Spacing.lg),
          if (_sync.isPaired)
            AppCard(
              child: Column(
                children: [
                  ListTile(
                    title: const Text('Disconnect web'),
                    subtitle: const Text('Rotates the token; old links stop working.'),
                    onTap: _busy ? null : () => _act(() async { await _sync.rotate(); setState(() => _link = null); }, 'Disconnected'),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    title: const Text('Delete cloud copy', style: TextStyle(color: Colors.red)),
                    subtitle: const Text('Keeps both devices\' local data.'),
                    onTap: _busy ? null : () => _act(_sync.deleteCloudCopy, 'Cloud copy deleted'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
