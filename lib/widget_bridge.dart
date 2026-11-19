import 'package:flutter/services.dart';

/// Thin bridge to the native home-screen widgets. All calls are best-effort:
/// on web, in tests, or on Android versions without widgets they simply no-op.
class WidgetBridge {
  static const _channel = MethodChannel('expense/widget');
  static const _actions = MethodChannel('expense/widget_actions');

  /// The action carried by the last Quick-add widget tap, consumed once.
  static Future<String?> takeQuickAction() async {
    try {
      return await _channel.invokeMethod<String>('takeQuickAction');
    } catch (_) {
      return null;
    }
  }

  /// Ask Android to repaint every widget from the current on-device data.
  static Future<void> refresh() async {
    try {
      await _channel.invokeMethod<void>('refresh');
    } catch (_) {}
  }

  /// A tap while the app is already running arrives here.
  static void listen(void Function(String action) onAction) {
    _actions.setMethodCallHandler((call) async {
      if (call.method == 'action' && call.arguments is String) {
        onAction(call.arguments as String);
      }
    });
  }
}
