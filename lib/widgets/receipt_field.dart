import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../receipts.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

const _channel = MethodChannel('expense/media');

/// Optional receipt row used at the bottom of Add and Edit. Photos are
/// captured by the native intent bridge and kept on this phone only.
class ReceiptField extends StatefulWidget {
  final List<String> initial;
  final ValueChanged<List<String>> onChanged;

  const ReceiptField({
    super.key,
    required this.initial,
    required this.onChanged,
  });

  @override
  State<ReceiptField> createState() => _ReceiptFieldState();
}

class _ReceiptFieldState extends State<ReceiptField> {
  ReceiptStore? _store2;
  late List<String> _paths;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _paths = [...widget.initial];
    _init();
  }

  Future<void> _init() async {
    final store = await ReceiptStore.create();
    if (!mounted) return;
    setState(() => _store2 = store);
  }

  Future<void> _capture(String method) async {
    setState(() => _busy = true);
    try {
      final raw = await _channel.invokeListMethod<String>(method);
      if (raw != null && raw.isNotEmpty && mounted) {
        final added = <String>[];
        for (final path in raw.take(3 - _paths.length)) {
          added.add(path);
        }
        setState(() => _paths = [..._paths, ...added]);
        widget.onChanged(_paths);
      }
    } on PlatformException catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not add the photo.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _sheet() {
    final colors = AppColors.of(context);
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.photo_camera_outlined, color: colors.accent),
              title: const Text('Take photo'),
              onTap: () {
                Navigator.of(ctx).pop();
                _capture('takePhoto');
              },
            ),
            ListTile(
              leading: Icon(Icons.photo_library_outlined, color: colors.accent),
              title: const Text('Choose from gallery'),
              onTap: () {
                Navigator.of(ctx).pop();
                _capture('pickImages');
              },
            ),
          ],
        ),
      ),
    );
  }

  void _view(String relative) {
    final store = _store2;
    if (store == null) return;
    final file = File(p.join(store.root.path, relative));
    if (!file.existsSync()) return;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: MediaQuery.sizeOf(ctx).height * 0.7,
              child: InteractiveViewer(
                child: Image.file(file, fit: BoxFit.contain),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Close'),
                ),
                TextButton(
                  onPressed: () {
                    setState(
                      () => _paths = _paths.where((x) => x != relative).toList(),
                    );
                    widget.onChanged(_paths);
                    Navigator.of(ctx).pop();
                  },
                  child: const Text('Delete'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(
            'Receipts (optional, on this phone only)',
            style: AppType.caption.copyWith(color: colors.textSecondary),
          ),
        ),
        const SizedBox(height: Spacing.sm),
        Wrap(
          spacing: Spacing.sm,
          runSpacing: Spacing.sm,
          children: [
            for (final relative in _paths)
              GestureDetector(
                onTap: () => _view(relative),
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    borderRadius: Radii.iconRadius,
                    color: colors.field,
                  ),
                  child: ClipRRect(
                    borderRadius: Radii.iconRadius,
                    child: _thumb(relative),
                  ),
                ),
              ),
            if (_paths.length < 3)
              SizedBox(
                width: 56,
                height: 56,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(56, 56),
                  ),
                  onPressed: _busy ? null : _sheet,
                  child: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add_photo_alternate_outlined),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _thumb(String relative) {
    final store = _store2;
    if (store == null) return const Icon(Icons.image_outlined);
    final file = File(p.join(store.root.path, relative));
    if (!file.existsSync()) return const Icon(Icons.image_outlined);
    return Image.file(file, fit: BoxFit.cover);
  }
}
