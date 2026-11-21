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
///
/// The widget owns the visible path list. Newly captured files stay as
/// absolute paths in `incoming` until the owner saves the entry; the owner
/// must attach them on save and delete them if the form is cancelled.
class ReceiptField extends StatefulWidget {
  /// Stored paths (relative to the receipts root) already attached to the
  /// entry. Empty in Add; the entry's current receipts in Edit.
  final List<String> initial;

  /// Stored relative paths after edits (removals applied; captures pending).
  final ValueChanged<List<String>> onChanged;

  /// Newly captured absolute paths still waiting to be attached.
  final ValueChanged<List<String>>? onCapturedChanged;

  const ReceiptField({
    super.key,
    required this.initial,
    required this.onChanged,
    this.onCapturedChanged,
  });

  @override
  State<ReceiptField> createState() => _ReceiptFieldState();
}

class _ReceiptFieldState extends State<ReceiptField> {
  ReceiptStore? _store2;
  late List<String> _paths;
  final List<String> _captured = [];
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
        for (final path in raw) {
          if (_paths.length + _captured.length + added.length >= 3) break;
          added.add(path);
        }
        setState(() {
          _captured.addAll(added);
          _paths = [..._paths, ...added];
        });
        widget.onCapturedChanged?.call(List.of(_captured));
        widget.onChanged(_storedPaths());
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

  /// Stored paths only; captures are managed separately by the owner.
  List<String> _storedPaths() =>
      _paths.where((path) => !isCapturedReceiptPath(path)).toList();

  /// Returns the relative path of the removed item, if it was stored.
  String? _removeAt(int index) {
    final removed = _paths[index];
    setState(() {
      _paths = [..._paths]..removeAt(index);
      _captured.remove(removed);
    });
    widget.onCapturedChanged?.call(List.of(_captured));
    widget.onChanged(_storedPaths());
    return isCapturedReceiptPath(removed) ? null : removed;
  }

  void _view(String path) {
    final store = _store2;
    if (store == null) return;
    final file = File(
      isCapturedReceiptPath(path)
          ? path
          : p.join(store.root.path, path),
    );
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
                    final index = _paths.indexOf(path);
                    final removedStored = index >= 0 ? _removeAt(index) : null;
                    // A removal is only final once the entry is saved; on
                    // cancel the owner reuses `initial` so the file survives.
                    if (removedStored != null) {
                      widget.onChanged(_storedPaths());
                    }
                    Navigator.of(ctx).pop();
                  },
                  child: const Text('Remove'),
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
            'Receipts (optional)',
            style: AppType.caption.copyWith(color: colors.textSecondary),
          ),
        ),
        const SizedBox(height: Spacing.sm),
        Wrap(
          spacing: Spacing.sm,
          runSpacing: Spacing.sm,
          children: [
            for (var i = 0; i < _paths.length; i++)
              GestureDetector(
                key: Key('receipt-thumb-$i'),
                onTap: () => _view(_paths[i]),
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    borderRadius: Radii.iconRadius,
                    color: colors.field,
                  ),
                  child: ClipRRect(
                    borderRadius: Radii.iconRadius,
                    child: _thumb(_paths[i]),
                  ),
                ),
              ),
            if (_paths.length < 3)
              OutlinedButton.icon(
                key: const Key('receipt-gallery'),
                onPressed: _busy ? null : () => _capture('pickImages'),
                icon: const Icon(Icons.photo_library_outlined, size: 18),
                label: const Text('Gallery'),
              ),
            if (_busy)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
      ],
    );
  }

  Widget _thumb(String path) {
    final store = _store2;
    final file = File(
      isCapturedReceiptPath(path)
          ? path
          : (store == null ? '' : p.join(store.root.path, path)),
    );
    if (path.isEmpty || !file.existsSync()) {
      return const Icon(Icons.image_outlined);
    }
    return Image.file(file, fit: BoxFit.cover);
  }
}
