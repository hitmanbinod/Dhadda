import 'package:flutter/services.dart';

/// Runtime permission helper through a tiny native bridge.
/// No extra plugin: only CAMERA can ever be granted here.
class Permissions {
  static const _ch = MethodChannel('expense/perm');

  static Future<bool> ensureCamera() async {
    try {
      return await _ch.invokeMethod<bool>(
              'ensure', {'name': 'android.permission.CAMERA'}) ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// Android 13+ notification permission for the hosting foreground service.
  /// Returns false when denied; foreground serving still works without it.
  static Future<bool> ensureNotifications() async {
    try {
      return await _ch.invokeMethod<bool>(
              'ensure', {'name': 'android.permission.POST_NOTIFICATIONS'}) ??
          false;
    } catch (_) {
      return false;
    }
  }
}