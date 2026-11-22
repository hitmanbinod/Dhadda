// Dhadda cloud vault sync client (Prompt 2, Phase 5).
// Presentation/state only: no schema change. The outbox and per-record ua map
// live in app-private SharedPreferences; domain collections are untouched
// except for an explicit additive merge method on ExpenseStore.
import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../home_layout.dart';
import '../store.dart';

class CloudSync {
  CloudSync(this.store, {String? workerUrl})
      : worker = workerUrl ?? 'https://dhadda-sync.YOUR-SUBDOMAIN.workers.dev';

  final ExpenseStore store;
  final String worker;

  /// Pure LWW rule from SYNC_PROTOCOL.md §5. Exposed for vector tests.
  static Map<String, dynamic> resolveWinner(
    Map<String, dynamic> incoming,
    Map<String, dynamic>? current,
  ) {
    if (current == null) return incoming;
    final a = (incoming['ua'] as num).toInt();
    final b = (current['ua'] as num).toInt();
    if (a != b) return a > b ? incoming : current;
    final da = '${incoming['device_id'] ?? ''}';
    final db = '${current['device_id'] ?? ''}';
    return da.compareTo(db) > 0 ? incoming : current;
  }

  static const _vault = 'expense_cloud_vault_v1';
  static const _token = 'expense_cloud_token_v1';
  static const _key = 'expense_cloud_key_v1';
  static const _seq = 'expense_cloud_seq_v1';
  static const _outbox = 'expense_cloud_outbox_v1';
  static const _kUas = 'expense_cloud_ua_v1';

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();
  final _aes = AesGcm.with256bits();

  String? get vaultId => _vaultId;
  String? _vaultId;
  String? _tokenValue;
  List<int>? _keyBytes;
  int _lastSeq = 0;
  Map<String, int> _uas = {};

  Future<void> load() async {
    final p = await _prefs;
    _vaultId = p.getString(_vault);
    _tokenValue = p.getString(_token);
    final rawKey = p.getString(_key);
    if (rawKey != null) _keyBytes = base64.decode(rawKey);
    _lastSeq = p.getInt(_seq) ?? 0;
    try {
      _uas = (jsonDecode(p.getString(_kUas) ?? '{}') as Map<String, dynamic>)
          .map((k, v) => MapEntry(k, (v as num).toInt()));
    } catch (_) {
      _uas = {};
    }
  }

  bool get isPaired =>
      _vaultId != null && _tokenValue != null && _keyBytes != null;

  int _ua(String key) {
    final next = max(DateTime.now().millisecondsSinceEpoch, (_uas[key] ?? 0) + 1);
    _uas[key] = next;
    return next;
  }

  Future<void> _saveUas() =>
      _prefs.then((p) => p.setString(_kUas, jsonEncode(_uas)));

  /// Creates the vault once and returns a link carrying the key in the
  /// fragment. The token/key are shown once and never logged.
  Future<String> createLink() async {
    // Safety first: keep a local snapshot before any cloud state is created.
    final p0 = await _prefs;
    await p0.setString('expense_cloud_prebackup_v1', store.exportJson());
    final res = await http.post(
      Uri.parse('$worker/v1/vault'),
      headers: {'Content-Type': 'application/json'},
      body: '{}',
    );
    if (res.statusCode != 201) throw StateError('Vault creation failed');
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    _vaultId = j['vault_id'] as String;
    _tokenValue = j['token'] as String;
    final random = Random.secure();
    _keyBytes = List<int>.generate(32, (_) => random.nextInt(256));
    final p = await _prefs;
    await p.setString(_vault, _vaultId!);
    await p.setString(_token, _tokenValue!);
    await p.setString(_key, base64.encode(_keyBytes!));
    await p.setInt(_seq, 0);
    final site = worker.replaceFirst('dhadda-sync', 'dhadda-web');
    return '$site/#v=${Uri.encodeComponent(_vaultId!)}'
        '&t=${Uri.encodeComponent(_tokenValue!)}'
        '&k=${Uri.encodeComponent(base64Url.encode(_keyBytes!))}';
  }

  Future<Map<String, String>> _encrypt(Map<String, dynamic> envelope) async {
    final nonce = _aes.newNonce();
    final box = await _aes.encrypt(
      utf8.encode(jsonEncode(envelope)),
      secretKey: SecretKey(_keyBytes!),
      nonce: nonce,
    );
    return {
      'iv': base64.encode(nonce),
      'ct': base64.encode([...box.cipherText, ...box.mac.bytes]),
    };
  }

  Future<Map<String, dynamic>> _decrypt(String ivB64, String ctB64) async {
    final nonce = base64.decode(ivB64);
    final bytes = base64.decode(ctB64);
    final mac = bytes.sublist(bytes.length - 16);
    final cipher = bytes.sublist(0, bytes.length - 16);
    final plain = await _aes.decrypt(
      SecretBox(cipher, nonce: nonce, mac: Mac(mac)),
      secretKey: SecretKey(_keyBytes!),
    );
    return jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
  }

  Map<String, dynamic> _row(String t, String id, Object data, int deleted) => {
        't': t, 'id': id, 'ua': _ua('$t:$id'), 'd': deleted,
        'data': data,
      };

  /// Queues a local change for the next push. Call from repository hooks.
  Future<void> queue(String t, String id, Object data, {bool deleted = false}) async {
    if (!isPaired) return;
    final p = await _prefs;
    final list = _decodeList(p.getString(_outbox));
    final row = _row(t, id, data, deleted ? 1 : 0);
    list.removeWhere((r) => r['t'] == t && r['id'] == id);
    list.add(row);
    await p.setString(_outbox, jsonEncode(list));
    await _saveUas();
  }

  List<Map<String, dynamic>> _decodeList(String? raw) {
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  /// Queues the full local dataset (initial sync or manual resync).
  Future<void> pushAll() async {
    if (!isPaired) return;
    for (final c in store.categories) await queue('categories', c.id, c.toJson());
    for (final t in store.transactions) await queue('entries', t.id, t.toJson());
    for (final p in store.projects) await queue('events', p.id, p.toJson());
    for (final l in store.loans) await queue('people', l.id, l.toJson());
    await queue('settings', 'userName', {'value': store.userName});
    await queue('settings', 'currency', {'value': store.currency});
    await queue('settings', 'calendarSystem', {'value': store.calendarSystem});
    await queue('settings', 'homeLayout', {'value': encodeHomeLayout(store.homeLayout)});
  }

  Future<int> push() async {
    if (!isPaired) return 0;
    final p = await _prefs;
    final queued = _decodeList(p.getString(_outbox));
    if (queued.isEmpty) return 0;
    final rows = <Map<String, dynamic>>[];
    for (final r in queued) {
      final enc = await _encrypt(r);
      rows.add({
        't': r['t'], 'id': r['id'], 'ua': r['ua'], 'd': r['d'],
        'device_id': store.deviceId,
        'iv': enc['iv']!, 'ct': enc['ct']!,
      });
    }
    final res = await http.post(
      Uri.parse('$worker/v1/push'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_tokenValue',
      },
      body: jsonEncode({'device_id': store.deviceId, 'rows': rows}),
    );
    if (res.statusCode != 200) throw StateError('Push failed (${res.statusCode})');
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    await p.setString(_outbox, '[]');
    if (j['server_seq'] is int) {
      _lastSeq = j['server_seq'] as int;
      await p.setInt(_seq, _lastSeq);
    }
    return (j['accepted'] as num?)?.toInt() ?? 0;
  }

  /// Pulls up to 500 rows and applies them additively through the store.
  Future<int> pull() async {
    if (!isPaired) return 0;
    final res = await http.get(
      Uri.parse('$worker/v1/pull?since=$_lastSeq&limit=500'),
      headers: {'Authorization': 'Bearer $_tokenValue'},
    );
    if (res.statusCode != 200) throw StateError('Pull failed (${res.statusCode})');
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    final rows = (j['rows'] as List? ?? []).cast<Map<String, dynamic>>();
    final applied = <Map<String, dynamic>>[];
    for (final w in rows) {
      final env = await _decrypt(w['iv'] as String, w['ct'] as String);
      final t = env['t'] as String;
      final id = env['id'] as String;
      final ua = (w['ua'] as num).toInt();
      final k = '$t:$id';
      if (ua <= (_uas[k] ?? 0)) continue;
      _uas[k] = ua;
      applied.add({'t': t, 'id': id, 'data': env['data'], 'd': w['d']});
    }
    if (applied.isNotEmpty) await store.applyCloudRows(applied);
    await _saveUas();
    if (j['next'] is int && j['next'] > _lastSeq) {
      _lastSeq = j['next'] as int;
      await _prefs.then((p) => p.setInt(_seq, _lastSeq));
    }
    if (j['more'] == true) return pull();
    return applied.length;
  }

  Future<void> rotate() async {
    if (!isPaired) return;
    final res = await http.post(
      Uri.parse('$worker/v1/rotate'),
      headers: {'Authorization': 'Bearer $_tokenValue'},
    );
    if (res.statusCode != 200) throw StateError('Rotate failed');
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    _tokenValue = j['token'] as String;
    await _prefs.then((p) => p.setString(_token, _tokenValue!));
  }

  Future<void> deleteCloudCopy() async {
    if (!isPaired) return;
    final res = await http.delete(
      Uri.parse('$worker/v1/vault'),
      headers: {'Authorization': 'Bearer $_tokenValue'},
    );
    if (res.statusCode != 200) throw StateError('Delete failed');
    final p = await _prefs;
    for (final k in [_vault, _token, _key, _seq, _outbox, _kUas]) {
      await p.remove(k);
    }
    _vaultId = null; _tokenValue = null; _keyBytes = null; _lastSeq = 0; _uas = {};
  }
}
