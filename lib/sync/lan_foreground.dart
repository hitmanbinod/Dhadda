// Thin Dart bridge to the Kotlin foreground service (Prompt 3 Phase 7).
// No new Dart dependency. Failures are non-fatal: the app-open server still
// works if the service cannot start (permission denied, OEM restriction, ...).
import 'package:flutter/services.dart';

class LanForeground {
  static const MethodChannel _ch = MethodChannel('expense/host_service');
  static bool _listening = false;

  /// Starts the notification/wake-lock service. Returns false if unavailable.
  static Future<bool> start() async {
    try {
      return await _ch.invokeMethod<bool>('start') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> stop() async {
    try {
      await _ch.invokeMethod('stop');
    } catch (_) {}
  }

  /// Tells the service when a computer is connected so its 2-hour idle timer
  /// only fires while nobody is using the phone-hosted page.
  static Future<void> updateConnected(bool connected) async {
    try {
      await _ch.invokeMethod('updateConnected', {'connected': connected});
    } catch (_) {}
  }

  /// The notification's Stop action asks Dart to tear down the HTTP server.
  static void onStopRequested(void Function() callback) {
    if (_listening) return;
    _listening = true;
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'stopRequested') callback();
    });
  }
}
