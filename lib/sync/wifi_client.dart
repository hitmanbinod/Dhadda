import 'dart:convert';

import 'package:http/http.dart' as http;

const _pinHeader = 'x-sync-pin';
const _authHeader = 'authorization';
const _qrPrefix = 'EXPENSESYNC::';

/// Client side of WiFi sync. Runs everywhere incl. Web (plain HTTP GET/POST
/// to the sender on the same LAN).
///
/// Phase 5: receivers bootstrap one session (POST /auth with the QR PIN)
/// and then use the short-lived Bearer token; the legacy PIN header keeps
/// working for old senders (404 on /auth). HTTP 429 means the sender is
/// throttling guesses — surfaced as a wait-and-retry message.
class WifiClient {
  static Map<String, String> _h(String pin, [String? token]) =>
      token == null || token.isEmpty
          ? {_pinHeader: pin}
          : {_authHeader: 'Bearer $token'};

  static Never _fail(http.Response res) {
    if (res.statusCode == 403) {
      throw const FormatException('Wrong PIN.');
    }
    if (res.statusCode == 429) {
      throw const FormatException(
          'Sender is rate-limiting guesses - wait a minute and retry.');
    }
    throw FormatException('Sender replied ${res.statusCode}.');
  }

  static Future<DateTime?> fetchRemoteMeta(String baseUrl, String pin,
      {String? token}) async {
    final res = await http
        .get(Uri.parse('$baseUrl/meta'), headers: _h(pin, token))
        .timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) _fail(res);
    final m = jsonDecode(res.body) as Map<String, dynamic>;
    return DateTime.tryParse('${m['updatedAt']}');
  }

  static Future<String> fetchRemoteSnapshot(String baseUrl, String pin,
      {String? token}) async {
    final res = await http
        .get(Uri.parse('$baseUrl/snapshot'), headers: _h(pin, token))
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) _fail(res);
    return res.body;
  }

  static Future<String?> fetchRemoteSnapshotV2(String baseUrl, String pin,
      {String? token}) async {
    final res = await http
        .get(Uri.parse('$baseUrl/snapshot-v2'), headers: _h(pin, token))
        .timeout(const Duration(seconds: 20));
    if (res.statusCode == 404) return null; // v1-only sender
    if (res.statusCode != 200) _fail(res);
    return res.body;
  }

  static Future<void> pushLocalSnapshot(
      String baseUrl, String pin, String snapshotJson,
      {String? token}) async {
    final res = await http
        .post(Uri.parse('$baseUrl/snapshot'),
            headers: {..._h(pin, token), 'Content-Type': 'application/json'},
            body: snapshotJson)
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) _fail(res);
  }

  /// One PIN bootstrap yielding a short-lived session token, or null when
  /// the sender predates sessions (404: keep using the PIN header).
  static Future<String?> establishSession(String baseUrl, String pin) async {
    final res = await http
        .post(Uri.parse('$baseUrl/auth'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'pin': pin}))
        .timeout(const Duration(seconds: 10));
    if (res.statusCode == 404) return null;
    if (res.statusCode != 200) _fail(res);
    final token =
        (jsonDecode(res.body) as Map<String, dynamic>)['token'];
    if (token is! String || token.isEmpty) {
      throw const FormatException('Sender replied badly.');
    }
    return token;
  }

  /// Best-effort session revoke (idempotent server-side).
  static Future<void> logout(
      String baseUrl, String pin, String token) async {
    final res = await http
        .post(Uri.parse('$baseUrl/logout'),
            headers: {
              ..._h(pin, token),
              'Content-Type': 'application/json'
            },
            body: jsonEncode({'token': token}))
        .timeout(const Duration(seconds: 10));
    if (res.statusCode == 404) return;
    if (res.statusCode != 200) _fail(res);
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
