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
}