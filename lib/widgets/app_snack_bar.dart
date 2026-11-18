import 'package:flutter/material.dart';

import '../theme/haptics.dart';

/// App snackbars, including the standard delete-with-Undo shape. Styling
/// lives in the theme; this helper only keeps the content and the haptic
/// on Undo consistent.
abstract final class AppSnackBar {
  static void show(
    BuildContext context,
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        action: actionLabel != null && onAction != null
            ? SnackBarAction(
                label: actionLabel,
                onPressed: () {
                  Haptics.selection();
                  onAction();
                },
              )
            : null,
      ),
    );
  }

  /// "Message" + Undo, with a selection haptic before the restore runs.
  static void undo(
    BuildContext context,
    String message, {
    required VoidCallback onUndo,
  }) {
    show(context, message, actionLabel: 'Undo', onAction: onUndo);
  }
}
