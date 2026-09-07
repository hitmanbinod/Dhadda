import 'dart:convert';

import 'package:http/http.dart' as http;

const _pinHeader = 'x-sync-pin';
const _qrPrefix = 'EXPENSESYNC::';

/// Client side of WiFi sync. Runs everywhere incl. Web (plain HTTP GET/POST
/// to the sender on the same LAN).
class WifiClient {
  static Map<String, String> _h(String pin) => {_pinHeader: pin};

  static Future<DateTime?> fetchRemoteMeta(String baseUrl, String pin) async {
    final res = await http
        .get(Uri.parse('$baseUrl/meta'), headers: _h(pin))
        .timeout(const Duration(seconds: 8));
    if (res.statusCode == 403) throw const FormatException('Wrong PIN.');
    if (res.statusCode != 200) {
      throw FormatException('Sender replied ${res.statusCode}.');
    }
    final m = jsonDecode(res.body) as Map<String, dynamic>;
    return DateTime.tryParse('${m['updatedAt']}');
  }

  static Future<String> fetchRemoteSnapshot(String baseUrl, String pin) async {
    final res = await http
        .get(Uri.parse('$baseUrl/snapshot'), headers: _h(pin))
        .timeout(const Duration(seconds: 20));
    if (res.statusCode == 403) throw const FormatException('Wrong PIN.');
    if (res.statusCode != 200) {
      throw FormatException('Sender replied ${res.statusCode}.');
    }
    return res.body;
  }

  /// v2 snapshot when the sender has one; null on 404 (v1-only sender).
  /// Callers fall back to [fetchRemoteSnapshot] + compat merge.
  static Future<String?> fetchRemoteSnapshotV2(
    String baseUrl,
    String pin,
  ) async {
    final res = await http
        .get(Uri.parse('$baseUrl/snapshot-v2'), headers: _h(pin))
        .timeout(const Duration(seconds: 20));
    if (res.statusCode == 403) throw const FormatException('Wrong PIN.');
    if (res.statusCode == 404) return null;
    if (res.statusCode != 200) {
      throw FormatException('Sender replied ${res.statusCode}.');
    }
    return res.body;
  }

  static Future<void> pushLocalSnapshot(
    String baseUrl,
    String pin,
    String snapshotJson,
  ) async {
    final res = await http
        .post(
          Uri.parse('$baseUrl/snapshot'),
          headers: {..._h(pin), 'Content-Type': 'application/json'},
          body: snapshotJson,
        )
        .timeout(const Duration(seconds: 20));
    if (res.statusCode == 403) throw const FormatException('Wrong PIN.');
    if (res.statusCode != 200) {
      throw FormatException('Sender replied ${res.statusCode}.');
    }
  }

  static String buildQrPayload(String baseUrl, String pin) =>
      '$_qrPrefix$baseUrl::$pin';

  static QrTarget? parseQrPayload(String raw) {
    final s = raw.trim();
    if (!s.startsWith(_qrPrefix)) return null;
    final rest = s.substring(_qrPrefix.length);
    final sep = rest.lastIndexOf('::');
    if (sep < 0) return null;
    final url = rest.substring(0, sep).trim();
    final pin = rest.substring(sep + 2).trim();
    if (url.isEmpty || pin.isEmpty) return null;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      return null;
    }
    return QrTarget(url: url, pin: pin);
  }
}

class QrTarget {
  final String url;
  final String pin;
  const QrTarget({required this.url, required this.pin});
}
