import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Tiny, always-safe haptic helpers. Web and desktop report nothing and
/// failures never escape into the UI; a missing motor is not an error.
abstract final class Haptics {
  /// Toggles, chip selection, undo.
  static void selection() => unawaited(_fire(HapticFeedback.selectionClick));

  /// Save and delete - the slightly stronger cue.
  static void tap() => unawaited(_fire(HapticFeedback.lightImpact));

  static Future<void> _fire(Future<void> Function() effect) async {
    if (kIsWeb) return;
    try {
      await effect();
    } catch (_) {
      // Haptics are decorative; never surface a platform failure.
    }
  }
}
