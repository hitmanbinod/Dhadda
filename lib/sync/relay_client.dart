import 'dart:convert';

import 'package:http/http.dart' as http;

/// Client for the LAN sync relay served by your own PC
/// (the same server that hosts the web app - $0, LAN-only).
/// Flow: one device OFFERS (shows QR) -> other device scans & ANSWERS.
/// Newer snapshot wins; both sides end up synced, no typing.
class RelayClient {
  final String origin;
  RelayClient(this.origin);

  Uri _u(String p) => Uri.parse('$origin$p');
  static const _json = {'Content-Type': 'application/json'};
  static const _timeout = Duration(seconds: 10);

  /// Offer this device's snapshot. Returns the 6-char session code.
  Future<String> offer(
      {required String pin,
      required String snapshot,
      required String name}) async {
    final res = await http
        .post(_u('/api/sync/offer'),
            headers: _json,
            body: jsonEncode(
                {'pin': pin, 'snapshot': snapshot, 'name': name}))
        .timeout(_timeout);
    if (res.statusCode != 200) {
      throw FormatException('Relay refused offer (${res.statusCode}).');
    }
    return '${(jsonDecode(res.body) as Map<String, dynamic>)['session']}';
  }

  /// Read a session (offer + answer-if-any). Throws on wrong PIN/expiry.
  Future<RelayView> fetch(
      {required String session, required String pin}) async {
    final res = await http
        .get(_u('/api/sync/session?id=$session&pin=$pin'))
        .timeout(_timeout);
    if (res.statusCode == 403) {
      throw const FormatException('Wrong PIN.');
    }
    if (res.statusCode == 404) {
      throw const FormatException('Code expired - make a new one.');
    }
    if (res.statusCode == 410) {
      throw const FormatException('Already answered.');
    }
    if (res.statusCode != 200) {
      throw FormatException('Relay error (${res.statusCode}).');
    }
    return RelayView.fromJson(
        jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// Answer a session. Pass your snapshot if YOU are newer, else null
  /// (meaning "I took yours").
  Future<void> answer(
      {required String session,
      required String pin,
      required String? snapshot,
      required String name,
      required String time}) async {
    final res = await http
        .post(_u('/api/sync/answer'),
            headers: _json,
            body: jsonEncode({
              'session': session,
              'pin': pin,
              'snapshot': snapshot,
              'name': name,
              'time': time,
            }))
        .timeout(_timeout);
    if (res.statusCode == 403) {
      throw const FormatException('Wrong PIN.');
    }
    if (res.statusCode == 404) {
      throw const FormatException('Code expired - make a new one.');
    }
    if (res.statusCode == 410) {
      throw const FormatException('Someone already answered this code.');
    }
    if (res.statusCode != 200) {
      throw FormatException('Relay error (${res.statusCode}).');
    }
  }

  /// Best-effort cleanup after a finished session.
  Future<void> close(
      {required String session, required String pin}) async {
    try {
      await http
          .post(_u('/api/sync/close'),
              headers: _json,
              body: jsonEncode({'session': session, 'pin': pin}))
          .timeout(_timeout);
    } catch (_) {}
  }
}

class RelayView {
  final bool done;
  final String offerSnapshot;
  final String offerName;
  final String offerTime;
  final String? answerSnapshot;
  final String? answerName;
  final String? answerTime;

  const RelayView({
    required this.done,
    required this.offerSnapshot,
    required this.offerName,
    required this.offerTime,
    this.answerSnapshot,
    this.answerName,
    this.answerTime,
  });

  factory RelayView.fromJson(Map<String, dynamic> j) {
    final offer = j['offer'] is Map<String, dynamic>
        ? j['offer'] as Map<String, dynamic>
        : <String, dynamic>{};
    final answer = j['answer'] is Map<String, dynamic>
        ? j['answer'] as Map<String, dynamic>
        : null;
    final ansSnap = answer?['snapshot'];
    return RelayView(
      done: j['stage'] == 'done',
      offerSnapshot: '${offer['snapshot'] ?? ''}',
      offerName: '${offer['name'] ?? 'device'}',
      offerTime: '${offer['time'] ?? ''}',
      answerSnapshot: ansSnap is String ? ansSnap : null,
      answerName:
          answer == null ? null : '${answer['name'] ?? 'device'}',
      answerTime: answer == null ? null : '${answer['time'] ?? ''}',
    );
  }
}

/// Which way should data flow? Newer snapshot always wins.
enum SyncDirection { pull, push }

/// Turns technical failures into one-line human messages.
String friendlySyncError(Object e) {
  final m = '$e';
  if (m.contains('Connection refused') ||
      m.contains('SocketException') ||
      m.contains('No route to host') ||
      m.contains('Network is unreachable') ||
      m.contains('TimeoutException') ||
      m.contains('ClientException') ||
      m.contains('Failed host lookup')) {
    return 'Could not reach the other side. Same WiFi? Is the PC app running?';
  }
  const prefix = 'FormatException: ';
  final f = m.startsWith(prefix) ? m.substring(prefix.length) : m;
  return f.length > 140 ? '${f.substring(0, 140)}...' : f;
}
SyncDirection decideSync(
    {required DateTime local, required DateTime remote}) =>
    remote.isAfter(local) ? SyncDirection.pull : SyncDirection.push;

/// QR v2 payload: relay origin + session + pin. Origin is included so the
/// phone works even if the PC's LAN address changes one day.
class QrV2 {
  static const prefix = 'EXPENSESYNC2::';
  final String origin;
  final String session;
  final String pin;
  const QrV2(
      {required this.origin,
      required this.session,
      required this.pin});

  static String build(String origin, String session, String pin) =>
      '$prefix$origin::$session::$pin';

  static QrV2? parse(String raw) {
    final s = raw.trim();
    if (!s.startsWith(prefix)) return null;
    final parts = s.substring(prefix.length).split('::');
    if (parts.length != 3) return null;
    final origin = parts[0].trim();
    final session = parts[1].trim();
    final pin = parts[2].trim();
    if (origin.isEmpty || session.isEmpty || pin.isEmpty) return null;
    if (!origin.startsWith('http://') &&
        !origin.startsWith('https://')) {
      return null;
    }
    return QrV2(origin: origin, session: session, pin: pin);
  }
}

/// One slot in a persistent link mailbox (someone else's latest state).
class LinkPeer {
  final String deviceId;
  final String snapshot;
  final String name;
  final String time;
  const LinkPeer(
      {required this.deviceId,
      required this.snapshot,
      required this.name,
      required this.time});

  factory LinkPeer.fromJson(Map<String, dynamic> j) => LinkPeer(
        deviceId: '${j['deviceId'] ?? ''}',
        snapshot: '${j['snapshot'] ?? ''}',
        name: '${j['name'] ?? 'device'}',
        time: '${j['time'] ?? ''}',
      );

  DateTime get timeValue =>
      DateTime.tryParse(time) ??
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
}

/// Client for persistent link mailboxes: pair once by scan, then push
/// your snapshot and pull others' for as long as you're on the network.
class LinkClient {
  final String origin;
  LinkClient(this.origin);

  Uri _u(String p) => Uri.parse('$origin$p');
  static const _json = {'Content-Type': 'application/json'};
  static const _timeout = Duration(seconds: 10);

  Never _fail(http.Response res) {
    if (res.statusCode == 403) {
      throw const FormatException('Wrong PIN.');
    }
    if (res.statusCode == 404) {
      throw const FormatException('Link gone - pair again.');
    }
    throw FormatException('Relay error (${res.statusCode}).');
  }

  /// Create a mailbox holding this device's snapshot.
  /// Returns the link id plus the server's own LAN origin, so QR codes
  /// never contain "localhost" (which phones cannot reach).
  Future<({String link, String origin})> create(
      {required String pin,
      required String deviceId,
      required String snapshot,
      required String name,
      required String time}) async {
    final res = await http
        .post(_u('/api/sync/link'),
            headers: _json,
            body: jsonEncode({
              'pin': pin,
              'deviceId': deviceId,
              'snapshot': snapshot,
              'name': name,
              'time': time,
            }))
        .timeout(_timeout);
    if (res.statusCode != 200) _fail(res);
    final m = jsonDecode(res.body) as Map<String, dynamic>;
    return (link: '${m['link']}', origin: '${m['origin'] ?? ''}');
  }

  /// Announce your latest snapshot to the mailbox.
  Future<void> push(
      {required String link,
      required String pin,
      required String deviceId,
      required String snapshot,
      required String name,
      required String time}) async {
    final res = await http
        .post(_u('/api/sync/push'),
            headers: _json,
            body: jsonEncode({
              'link': link,
              'pin': pin,
              'deviceId': deviceId,
              'snapshot': snapshot,
              'name': name,
              'time': time,
            }))
        .timeout(_timeout);
    if (res.statusCode != 200) _fail(res);
  }

  /// Read everyone else's latest snapshots (never your own slot).
  Future<List<LinkPeer>> pull(
      {required String link,
      required String pin,
      required String deviceId}) async {
    final res = await http
        .get(_u('/api/sync/pull?link=$link&pin=$pin&deviceId=$deviceId'))
        .timeout(_timeout);
    if (res.statusCode != 200) _fail(res);
    final list = (jsonDecode(res.body) as Map<String, dynamic>)['peers'];
    if (list is! List) return const [];
    return list
        .whereType<Map<String, dynamic>>()
        .map(LinkPeer.fromJson)
        .toList();
  }

  /// Best-effort mailbox deletion (unpair).
  Future<void> unlink({required String link, required String pin}) async {
    try {
      await http
          .post(_u('/api/sync/unlink'),
              headers: _json,
              body: jsonEncode({'link': link, 'pin': pin}))
          .timeout(_timeout);
    } catch (_) {}
  }
}