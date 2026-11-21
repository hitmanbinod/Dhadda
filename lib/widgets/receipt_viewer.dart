import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../receipts.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

/// Full-screen-ish viewer for one entry's receipt photos. Accepts both stored
/// relative paths and freshly captured absolute paths, so it works before and
/// after the entry is saved.
Future<void> showReceiptViewer(
  BuildContext context,
  List<String> paths, {
  ReceiptStore? store,
  int initialIndex = 0,
}) async {
  final resolved = paths.where((path) => path.isNotEmpty).toList();
  if (resolved.isEmpty) return;
  final files = await _resolveFiles(resolved, store);
  if (files.isEmpty || !context.mounted) return;

  await showDialog<void>(
    context: context,
    builder: (ctx) => _ReceiptViewerDialog(files: files, start: initialIndex),
  );
}

Future<List<File>> _resolveFiles(
  List<String> paths,
  ReceiptStore? store,
) async {
  final receipts = store ?? await ReceiptStore.create();
  final files = <File>[];
  for (final path in paths) {
    final file = File(
      isCapturedReceiptPath(path) ? path : p.join(receipts.root.path, path),
    );
    if (file.existsSync()) files.add(file);
  }
  return files;
}

class _ReceiptViewerDialog extends StatefulWidget {
  final List<File> files;
  final int start;

  const _ReceiptViewerDialog({required this.files, required this.start});

  @override
  State<_ReceiptViewerDialog> createState() => _ReceiptViewerDialogState();
}

class _ReceiptViewerDialogState extends State<_ReceiptViewerDialog> {
  late final PageController _controller;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.start.clamp(0, widget.files.length - 1);
    _controller = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Dialog(
      backgroundColor: colors.card,
      shape: const RoundedRectangleBorder(borderRadius: Radii.sheetRadius),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Spacing.lg,
              Spacing.md,
              Spacing.lg,
              Spacing.xs,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Receipt ${_index + 1} of ${widget.files.length}',
                    style: AppType.title.copyWith(color: colors.textPrimary),
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(Icons.close, color: colors.textSecondary),
                ),
              ],
            ),
          ),
          SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.65,
            child: PageView.builder(
              controller: _controller,
              itemCount: widget.files.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (context, i) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
                child: InteractiveViewer(
                  child: Image.file(
                    widget.files[i],
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
          ),
          if (widget.files.length > 1)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < widget.files.length; i++)
                    Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i == _index
                            ? colors.accent
                            : colors.textSecondary.withValues(alpha: 0.4),
                      ),
                    ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Spacing.lg,
              Spacing.xs,
              Spacing.lg,
              Spacing.md,
            ),
            child: Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
