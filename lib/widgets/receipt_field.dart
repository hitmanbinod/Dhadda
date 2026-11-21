import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;

import '../receipts.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'receipt_viewer.dart';

/// Optional receipt row used at the bottom of Add and Edit. Photos are kept
/// on this phone only. The form holds just paths: decoded pixels are never
/// kept here, and thumbnails are cached/downsampled by Flutter's image cache.
class ReceiptField extends StatefulWidget {
  final List<String> initial;
  final ValueChanged<List<String>> onChanged;
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

  Future<void> _capture({required bool camera}) async {
    setState(() => _busy = true);
    try {
      final picker = ImagePicker();
      final List<XFile> picked;
      // Ask the platform to downsample before the bytes reach Dart.
      if (camera) {
        final one = await picker.pickImage(
          source: ImageSource.camera,
          maxWidth: 1600,
          maxHeight: 1600,
          imageQuality: 80,
        );
        picked = one == null ? const [] : [one];
      } else {
        picked = await picker.pickMultiImage(
          maxWidth: 1600,
          maxHeight: 1600,
          imageQuality: 80,
        );
      }
      if (picked.isEmpty || !mounted) return;
      final store = _store2 ?? await ReceiptStore.create();
      final added = <String>[];
      for (final file in picked) {
        if (_paths.length + _captured.length + added.length >= 3) break;
        final bytes = await file.readAsBytes();
        added.add(
          await store.savePickedBytes(
            bytes,
            prefix: camera ? 'camera' : 'gallery',
          ),
        );
      }
      if (added.isEmpty || !mounted) return;
      setState(() {
        _captured.addAll(added);
        _paths = [..._paths, ...added];
      });
      widget.onCapturedChanged?.call(List.of(_captured));
      widget.onChanged(_storedPaths());
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not add the photo.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<String> _storedPaths() =>
      _paths.where((path) => !isCapturedReceiptPath(path)).toList();

  void _removeAt(int index) {
    final removed = _paths[index];
    setState(() {
      _paths = [..._paths]..removeAt(index);
      _captured.remove(removed);
    });
    widget.onCapturedChanged?.call(List.of(_captured));
    widget.onChanged(_storedPaths());
  }

  Future<void> _view(String path) async {
    final index = _paths.indexOf(path);
    await showReceiptViewer(
      context,
      _paths,
      store: _store2,
      initialIndex: index < 0 ? 0 : index,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            'Receipts (optional)',
            style: AppType.caption.copyWith(color: colors.textSecondary),
          ),
        ),
        const SizedBox(height: Spacing.sm),
        if (_paths.isEmpty)
          _emptyCard(colors)
        else
          _attachedCard(colors),
      ],
    );
  }

  /// Dashed, low-emphasis affordance before anything is attached.
  Widget _emptyCard(AppColors colors) {
    return CustomPaint(
      painter: _DashedRoundedBorder(
        color: colors.cardBorder,
        radius: Radii.card,
      ),
      child: Container(
        height: 60,
        padding: const EdgeInsets.fromLTRB(
          Spacing.lg,
          Spacing.sm,
          Spacing.sm,
          Spacing.sm,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Add receipt (optional)',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.body.copyWith(
                  fontSize: 14,
                  color: colors.textSecondary,
                ),
              ),
            ),
            const SizedBox(width: Spacing.xs),
            _miniAction(
              colors,
              key: const Key('receipt-gallery'),
              icon: Icons.photo_library_outlined,
              tooltip: 'Gallery',
              onPressed: _busy ? null : () => _capture(camera: false),
            ),
            const SizedBox(width: Spacing.xs),
            _miniAction(
              colors,
              key: const Key('receipt-camera'),
              icon: Icons.photo_camera_outlined,
              tooltip: 'Camera',
              onPressed: _busy ? null : () => _capture(camera: true),
            ),
            if (_busy) ...[
              const SizedBox(width: Spacing.xs),
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Solid card once photos exist: cached thumbnails, status, add/remove.
  Widget _attachedCard(AppColors colors) {
    return Container(
      height: 60,
      padding: const EdgeInsets.fromLTRB(
        Spacing.sm,
        Spacing.xs,
        Spacing.xs,
        Spacing.xs,
      ),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: Radii.cardRadius,
        border: Border.all(color: colors.cardBorder),
      ),
      child: Row(
        children: [
          for (var i = 0; i < _paths.length; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            _ReceiptThumb(
              path: _paths[i],
              store: _store2,
              onTap: () => _view(_paths[i]),
            ),
          ],
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Receipt attached',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.body.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Tap to view · ${_paths.length} '
                  '${_paths.length == 1 ? 'file' : 'files'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.caption.copyWith(
                    fontSize: 11.5,
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          _miniAction(
            colors,
            key: const Key('receipt-gallery'),
            icon: Icons.photo_library_outlined,
            tooltip: 'Add from gallery',
            onPressed: _busy ? null : () => _capture(camera: false),
          ),
          const SizedBox(width: 4),
          _miniAction(
            colors,
            key: const Key('receipt-camera'),
            icon: Icons.photo_camera_outlined,
            tooltip: 'Take photo',
            onPressed: _busy ? null : () => _capture(camera: true),
          ),
          const SizedBox(width: 4),
          _miniAction(
            colors,
            key: const Key('receipt-remove-last'),
            icon: Icons.close,
            tooltip: 'Remove last receipt',
            onPressed: _busy ? null : () => _removeAt(_paths.length - 1),
          ),
        ],
      ),
    );
  }

  Widget _miniAction(
    AppColors colors, {
    required Key key,
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: colors.surface2,
        borderRadius: Radii.iconRadius,
        child: InkWell(
          key: key,
          onTap: onPressed,
          borderRadius: Radii.iconRadius,
          child: SizedBox(
            width: 34,
            height: 34,
            child: Icon(icon, size: 18, color: colors.textSecondary),
          ),
        ),
      ),
    );
  }
}

/// One cached, isolated thumbnail. [cacheWidth]/[cacheHeight] cap decoded
/// pixels at ~128px so the form never holds a full-resolution bitmap.
class _ReceiptThumb extends StatelessWidget {
  final String path;
  final ReceiptStore? store;
  final VoidCallback onTap;

  const _ReceiptThumb({
    required this.path,
    required this.store,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final file = File(
      isCapturedReceiptPath(path)
          ? path
          : (store == null ? '' : p.join(store!.root.path, path)),
    );
    final exists = path.isNotEmpty && file.existsSync();
    return RepaintBoundary(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: colors.field,
            borderRadius: Radii.iconRadius,
            border: Border.all(color: colors.cardBorder),
          ),
          child: exists
              ? Image.file(
                  file,
                  cacheWidth: 128,
                  cacheHeight: 128,
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.low,
                )
              : Icon(Icons.image_outlined,
                  size: 20, color: colors.textSecondary),
        ),
      ),
    );
  }
}

/// Simple dashed rounded-rectangle outline for the empty receipt card.
class _DashedRoundedBorder extends CustomPainter {
  final Color color;
  final double radius;

  const _DashedRoundedBorder({required this.color, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          Radius.circular(radius),
        ),
      );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final metric = path.computeMetrics().first;
    const dash = 5.0;
    const gap = 4.0;
    for (double d = 0; d < metric.length; d += dash + gap) {
      canvas.drawPath(
        metric.extractPath(d, (d + dash).clamp(0.0, metric.length)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRoundedBorder old) =>
      old.color != color || old.radius != radius;
}
