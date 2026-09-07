import 'dart:async';

import 'package:flutter/foundation.dart' hide Category;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models.dart';
import '../store.dart';
import '../widgets/page.dart';
import '../widgets/backup_password.dart';
import '../sync/backup_crypto.dart';
import '../sync/file_sync.dart';
import '../sync/link_sync.dart';
import '../sync/mdns.dart';
import '../sync/permissions.dart';
import '../sync/phone_host.dart';
import '../sync/relay_client.dart';
import '../sync/wifi_client.dart';
import '../sync/wifi_host.dart';
import 'scan_screen.dart';

/// Settings + Sync hub.
/// Option 1: manual Export/Import file. Option 3: WiFi QR sync.
/// Also: categories & budgets, local backups.
class SyncScreen extends StatefulWidget {
  /// Bumped by the Home sync button - the screen auto-offers a code.
  final LinkEngine? engine;
  const SyncScreen({super.key, this.engine});

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  LinkEngine? get _engine => widget.engine;

  HostSession? _session;
  String _sendUrl = '';
  String _sendPin = '';
  final _recvUrl = TextEditingController();
  final _recvPin = TextEditingController();
  bool _busy = false;
  // Quick sync (LAN relay) state.
  Timer? _poll;
  String? _offerSession;
  String? _offerPin;
  String _offerOrigin = '';
  final _quickCode = TextEditingController();
  final _srvCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();
  PhoneHostSession? _serve;
  String? _mdnsUrl;
  bool _mdnsDone = false;

  @override
  void dispose() {
    _serve?.close();
    Mdns.unregister();
    _recvUrl.dispose();
    _recvPin.dispose();
    _quickCode.dispose();
    _srvCtrl.dispose();
    _codeCtrl.dispose();
    _pinCtrl.dispose();
    _poll?.cancel();
    _session?.close();
    super.dispose();
  }

  void _say(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ---------- Quick sync (LAN relay, scan & done) ----------

  /// Where the relay lives. Web knows its own origin; native reuses the
  /// address learned from the last scanned code.
  String get _relayOrigin {
    if (kIsWeb) return Uri.base.origin;
    return context.read<ExpenseStore>().relayOrigin;
  }

  /// Offer side: create a lasting link box and show its code.
  /// Whoever scans it joins the same box - then both stay synced.
  Future<void> _startQuickOffer() async {
    final store = context.read<ExpenseStore>();
    final origin = _relayOrigin;
    if (origin.isEmpty) {
      _say(
        'Tip: tap Show my code on your DESKTOP first (same WiFi), then scan it here. One scan pairs both for good.',
      );
      return;
    }
    final pin = _makePin();
    try {
      final created = await LinkClient(origin).create(
        pin: pin,
        deviceId: store.deviceId,
        snapshot: store.exportJson(),
        snapshotV2: store.exportSnapshotV2(),
        name: store.deviceName,
        time: store.updatedAt,
      );
      if (!mounted) return;
      // Prefer the server's own LAN address for the QR: if this page
      // was opened via localhost, its origin would strand the phone.
      var showOrigin = origin;
      final host = Uri.tryParse(created.origin)?.host ?? '';
      if (host.isNotEmpty && host != 'localhost' && !host.startsWith('127.')) {
        showOrigin = created.origin;
      }
      setState(() {
        _offerSession = created.link;
        _offerPin = pin;
        _offerOrigin = showOrigin;
      });
      _poll?.cancel();
      _poll = Timer.periodic(const Duration(seconds: 2), (_) => _pollLink());
    } catch (e) {
      _say('Could not start quick sync: ${friendlySyncError(e)}');
    }
  }

  /// Offer side: wait until the other device joins the link box,
  /// then converge exactly like the joining side does.
  Future<void> _pollLink() async {
    final link = _offerSession;
    final pin = _offerPin;
    if (link == null || pin == null) return;
    final store = context.read<ExpenseStore>();
    final origin = _relayOrigin;
    if (origin.isEmpty) return;
    try {
      final peers = await LinkClient(origin)
          .pull(link: link, pin: pin, deviceId: store.deviceId);
      if (peers.isEmpty) return; // nobody joined yet
      _poll?.cancel();
      _poll = null;
      final msg = await _adoptPeers(LinkClient(origin), link, pin, peers);
      if (!mounted) return;
      setState(() {
        _offerSession = null;
        _offerPin = null;
        _offerOrigin = '';
      });
      _say(msg);
    } catch (e) {
      _poll?.cancel();
      _poll = null;
      if (!mounted) return;
      setState(() {
        _offerSession = null;
        _offerPin = null;
        _offerOrigin = '';
      });
      _say('Quick sync ended: ${friendlySyncError(e)}');
    }
  }

  /// Merges every peer slot (v2 when present, else v1-as-baseline),
  /// announces our union, and saves the pairing. Identical logic on both
  /// sides, so a single scan converges the pair no matter who changed what.
  Future<String> _adoptPeers(
    LinkClient client,
    String link,
    String pin,
    List<LinkPeer> peers,
  ) async {
    final store = context.read<ExpenseStore>();
    String? firstMsg;
    String peerName = 'other device';
    var sawPeer = false;
    for (final p in peers) {
      final raw = p.snapshotV2.isNotEmpty ? p.snapshotV2 : p.snapshot;
      if (raw.isEmpty) continue;
      if (!sawPeer) {
        sawPeer = true;
        peerName = p.name;
      }
      try {
        final m = await store.ingestPeerSnapshot(raw, peerName: p.name);
        if (m.startsWith('Synced') && firstMsg == null) firstMsg = m;
      } catch (_) {
        // Malformed peer slot: skip it, keep converging with the rest.
      }
    }
    await client.push(
      link: link,
      pin: pin,
      deviceId: store.deviceId,
      snapshot: store.exportJson(),
      snapshotV2: store.exportSnapshotV2(),
      name: store.deviceName,
      time: store.updatedAt,
    );
    await store.setRelayOrigin(client.origin);
    await store.setLink(id: link, pin: pin, peer: peerName);
    store.noteSynced();
    _engine?.markAnnounced(store.updatedAt);
    return firstMsg ?? 'Paired - both will stay in sync now.';
  }

  /// Stops showing our code. Keeps the mailbox if it became our live
  /// link, otherwise deletes the unused box.
  Future<void> _finishOffer() async {
    _poll?.cancel();
    _poll = null;
    final link = _offerSession;
    final pin = _offerPin;
    final store = context.read<ExpenseStore>();
    final origin = _relayOrigin;
    if (link != null && pin != null && origin.isNotEmpty) {
      if (store.linked && store.linkId == link) {
        // Live link - leave the mailbox in place.
      } else {
        await LinkClient(origin).unlink(link: link, pin: pin);
      }
    }
    if (mounted) {
      setState(() {
        _offerSession = null;
        _offerPin = null;
        _offerOrigin = '';
      });
    }
  }

  Future<void> _linkedSyncNow() async {
    final engine = _engine;
    if (engine == null) return;
    setState(() => _busy = true);
    try {
      _say(await engine.syncNow());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _unlink() async {
    final store = context.read<ExpenseStore>();
    final origin = _relayOrigin;
    if (store.linkId.isNotEmpty && origin.isNotEmpty) {
      await LinkClient(origin).unlink(link: store.linkId, pin: store.linkPin);
    }
    _engine?.reset();
    await store.clearLink('Unlinked.');
    _say('Unlinked. Your data stays on this device.');
  }

  /// Joining side: read the link box, converge, save the pairing.
  /// Accepts a full scanned code, or manual Server + Code + PIN below.
  Future<void> _quickAnswer({String? presetRaw}) async {
    String? server;
    String? code;
    String? pin;
    final raw = (presetRaw ?? '').trim();
    if (raw.isNotEmpty) {
      final v2 = QrV2.parse(raw);
      if (v2 == null) {
        // Old-style direct code - use the direct flow below.
        await _receive(presetRaw: raw);
        return;
      }
      server = v2.origin;
      code = v2.session;
      pin = v2.pin;
    } else {
      final store = context.read<ExpenseStore>();
      server = _srvCtrl.text.trim().isEmpty
          ? store.relayOrigin
          : _srvCtrl.text.trim();
      code = _codeCtrl.text.trim();
      pin = _pinCtrl.text.trim();
      if (server.isEmpty || code.isEmpty || pin.isEmpty) {
        _say('Fill server, code and PIN - all three sit under the QR.');
        return;
      }
    }
    final host = Uri.tryParse(server)?.host ?? '';
    if (!kIsWeb && (host == 'localhost' || host.startsWith('127.'))) {
      _say(
        'This code points to this phone itself. Show the code on the DESKTOP instead - it carries the right address.',
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final store = context.read<ExpenseStore>();
      final client = LinkClient(server);
      final peers = await client.pull(
        link: code,
        pin: pin,
        deviceId: store.deviceId,
      );
      final msg = await _adoptPeers(client, code, pin, peers);
      _quickCode.clear();
      _srvCtrl.clear();
      _codeCtrl.clear();
      _pinCtrl.clear();
      _say(msg);
    } catch (e) {
      _say('Quick sync failed: ${friendlySyncError(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _scanQuick() async {
    final navigator = Navigator.of(context);
    if (!await _ensureCamera()) return;
    final raw = await navigator.push<String>(
      MaterialPageRoute(builder: (_) => const ScanScreen()),
    );
    if (raw != null) await _quickAnswer(presetRaw: raw);
  }

  /// The ZXing scanner needs an explicit camera grant first.
  Future<bool> _ensureCamera() async {
    try {
      if (await Permissions.ensureCamera()) return true;
    } catch (_) {}
    if (!mounted) return false;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Camera blocked - allow it in system Settings, Apps, Dhadda, Permissions.',
        ),
      ),
    );
    return false;
  }

  // ---------- Option 1: file ----------

  /// Phone-hosted mode: serve the app + sync API on your WiFi so any
  /// same-network browser can open the tracker straight from this phone.
  Future<void> _startServe() async {
    try {
      final s = await startPhoneHost();
      try {
        // Screen on = Android cannot suspend the server mid-transfer.
        await WakelockPlus.enable();
      } catch (_) {}
      if (!mounted) {
        await s.close();
        return;
      }
      setState(() {
        _serve = s;
        _mdnsUrl = null;
        _mdnsDone = false;
      });
      _registerMdns(s.url);
    } on UnsupportedError catch (e) {
      _say('$e');
    } catch (e) {
      _say('Could not start PC mode: ${friendlySyncError(e)}');
    }
  }

  /// Best-effort mDNS: stable dhadda.local alongside the IP.
  /// Never blocks serving; IP access always keeps working.
  Future<void> _registerMdns(String url) async {
    final port = Uri.tryParse(url)?.port ?? 0;
    if (port <= 0) {
      if (mounted) setState(() => _mdnsDone = true);
      return;
    }
    // Two attempts: mDNS sometimes needs a moment after WiFi changes.
    var r = await Mdns.register(name: 'dhadda', port: port);
    if (!r.ok) {
      await Future<void>.delayed(const Duration(seconds: 3));
      if (!mounted) return;
      r = await Mdns.register(name: 'dhadda', port: port);
    }
    if (!mounted) return;
    setState(() {
      _mdnsUrl = r.ok ? 'http://${r.name}.local:$port' : null;
      _mdnsDone = true;
    });
  }

  Future<void> _stopServe() async {
    await _serve?.close();
    await Mdns.unregister();
    try {
      await WakelockPlus.disable();
    } catch (_) {}
    if (mounted) {
      setState(() {
        _serve = null;
        _mdnsUrl = null;
        _mdnsDone = false;
      });
    }
  }

  Future<void> _exportFile() async {
    final store = context.read<ExpenseStore>();
    await FileSync.exportJson(
      context,
      store.exportJson(),
      FileSync.fileNameFor(DateTime.now()),
    );
  }

  Future<void> _importFile() async {
    final raw = await FileSync.importJson();
    if (raw == null) return; // cancelled
    if (!mounted) return;
    final store = context.read<ExpenseStore>();
    String payload = raw;
    if (BackupCrypto.isEncrypted(raw)) {
      final pw = await askBackupPassword(context, confirm: false);
      if (pw == null || !mounted) return;
      try {
        payload = await BackupCrypto.decrypt(raw, pw);
      } catch (e) {
        _say(e is FormatException ? e.message : 'Could not decrypt.');
        return;
      }
    }
    final msg = await store.importFilePayload(payload);
    store.noteSynced();
    _say(msg);
  }

  // ---------- Option 3: WiFi ----------

  String _makePin() =>
      '${100000 + (DateTime.now().millisecondsSinceEpoch % 900000)}';

  Future<void> _startSend() async {
    final store = context.read<ExpenseStore>();
    final pin = _makePin();
    try {
      final s = await startSendServer(
        currentSnapshot: store.exportJson,
        currentSnapshotV2: store.exportSnapshotV2,
        onUpload: (body) async {
          // Uniform ingest: v2 merges by revision, v1 converts to
          // baseline rev-0 records and merges the same way. Never replaces.
          await store.ingestPeerSnapshot(body);
          store.noteSynced();
        },
        pin: pin,
      );
      setState(() {
        _session = s;
        _sendUrl = s.url;
        _sendPin = s.pin.isEmpty ? pin : s.pin;
      });
    } on UnsupportedError catch (e) {
      _say('$e');
    } catch (e) {
      _say('Could not start sender: $e');
    }
  }

  Future<void> _stopSend() async {
    await _session?.close();
    setState(() {
      _session = null;
      _sendUrl = '';
      _sendPin = '';
    });
  }

  Future<void> _receive({String? presetRaw}) async {
    String url = _recvUrl.text.trim().replaceAll(RegExp(r'/+$'), '');
    String pin = _recvPin.text.trim();
    if (presetRaw != null) {
      final t = WifiClient.parseQrPayload(presetRaw);
      if (t == null) {
        _say('That QR is not a sync code.');
        return;
      }
      url = t.url;
      pin = t.pin;
      _recvUrl.text = url;
      _recvPin.text = pin;
    }
    if (url.isEmpty || pin.isEmpty) {
      _say('Enter sender address + PIN (or scan its QR).');
      return;
    }
    setState(() => _busy = true);
    try {
      final store = context.read<ExpenseStore>();
      // Session bootstrap first (404 = v1-only sender, keep PIN header).
      // One PIN exchange, then a short-lived token — the PIN no longer
      // travels on every request.
      final token = await WifiClient.establishSession(url, pin).catchError((e) {
        // Old senders have no /auth route; anything else is a real error.
        if ('$e'.contains('404')) return null;
        throw e;
      });
      // v2-capable sender: merge by revision both ways in one tap (our
      // union goes back so the sender converges too). The sender proved
      // v2-capable by serving it, so the v2 POST below is safe.
      final v2body = await WifiClient.fetchRemoteSnapshotV2(
        url,
        pin,
        token: token,
      );
      String msg;
      if (v2body != null) {
        msg = await store.ingestPeerSnapshot(v2body);
        await WifiClient.pushLocalSnapshot(
          url,
          pin,
          store.exportSnapshotV2(),
          token: token,
        );
        if (token != null) {
          try {
            await WifiClient.logout(url, pin, token);
          } catch (_) {}
        }
      } else {
        // v1-only sender: legacy meta-compare flow, v1 bytes only.
        final remoteMeta = await WifiClient.fetchRemoteMeta(url, pin);
        final localTime =
            DateTime.tryParse(store.updatedAt) ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
        if (remoteMeta != null && remoteMeta.isAfter(localTime)) {
          final body = await WifiClient.fetchRemoteSnapshot(url, pin);
          msg = await store.ingestPeerSnapshot(body);
        } else {
          await WifiClient.pushLocalSnapshot(url, pin, store.exportJson());
          msg = 'This device was newer - sent it to the other device.';
        }
      }
      store.noteSynced();
      _say(msg);
    } catch (e) {
      _say('Sync failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _scanAndReceive() async {
    final navigator = Navigator.of(context);
    if (!await _ensureCamera()) return;
    final raw = await navigator.push<String>(
      MaterialPageRoute(builder: (_) => const ScanScreen()),
    );
    if (raw != null) await _receive(presetRaw: raw);
  }

  // ---------- categories ----------

  // ---------- categories moved to the Category tab ----------

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ExpenseStore>();
    final backups = store.backups;

    return Scaffold(
      appBar: AppBar(title: const Text('Sync')),
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: ListView(
        padding: pageInsets(context),
        children: [
          Text('Scan to sync', style: Theme.of(context).textTheme.titleMedium),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (store.linked) ...[
                    Row(
                      children: [
                        const Icon(Icons.link, color: Colors.green),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Linked with ${store.linkPeer}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (store.linkStatus.isNotEmpty)
                                Text(
                                  store.linkStatus,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Both devices sync by themselves on the same WiFi.',
                    ),
                    const SizedBox(height: 8),
                    OverflowBar(
                      children: [
                        FilledButton.icon(
                          onPressed: _busy ? null : _linkedSyncNow,
                          icon: const Icon(Icons.sync),
                          label: const Text('Sync now'),
                        ),
                        TextButton(
                          onPressed: _busy ? null : _unlink,
                          child: const Text('Unlink'),
                        ),
                      ],
                    ),
                  ] else if (_offerSession == null) ...[
                    const Text(
                      '1) Tap Show my code on ONE device. 2) Scan it with the other. One scan pairs them - then they stay synced by themselves.',
                    ),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: _busy ? null : _startQuickOffer,
                      icon: const Icon(Icons.qr_code),
                      label: const Text('Show my code'),
                    ),
                    const Divider(),
                    if (!kIsWeb)
                      FilledButton.icon(
                        onPressed: _busy ? null : _scanQuick,
                        icon: const Icon(Icons.qr_code_scanner),
                        label: const Text('Scan other device code'),
                      )
                    else
                      const Text('On this browser, paste the code text:'),
                    const SizedBox(height: 8),
                    if (kIsWeb)
                      TextField(
                        controller: _quickCode,
                        decoration: const InputDecoration(
                          labelText: 'Paste code text here',
                          border: OutlineInputBorder(),
                        ),
                      )
                    else ...[
                      TextField(
                        controller: _srvCtrl,
                        keyboardType: TextInputType.url,
                        decoration: const InputDecoration(
                          labelText: 'Server',
                          hintText: 'shown under the desktop QR',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _codeCtrl,
                              textCapitalization: TextCapitalization.characters,
                              decoration: const InputDecoration(
                                labelText: 'Code',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _pinCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'PIN',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: _busy ? null : () => _quickAnswer(),
                      icon: _busy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.sync),
                      label: const Text('Sync now'),
                    ),
                  ] else ...[
                    const Text('Let the other device scan this:'),
                    const Text(
                      'This code + PIN can join your sync while it lives - don’t share its screenshot. Stop when paired.',
                      style: TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: Container(
                        color: Colors.white,
                        padding: const EdgeInsets.all(12),
                        child: QrImageView(
                          data: QrV2.build(
                            _offerOrigin,
                            _offerSession!,
                            _offerPin!,
                          ),
                          version: QrVersions.auto,
                          size: 240,
                          padding: EdgeInsets.zero,
                          backgroundColor: Colors.white,
                          errorCorrectionLevel: QrErrorCorrectLevel.M,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SelectableText(
                      'Code ${_offerSession!}   PIN: ${_offerPin!}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    SelectableText(
                      'Server $_offerOrigin',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 4),
                    const Text('Waiting for the other device... (auto-closes)'),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _finishOffer,
                      icon: const Icon(Icons.stop),
                      label: const Text('Stop'),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (!kIsWeb) ...[
            Text('Show on PC', style: Theme.of(context).textTheme.titleMedium),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_serve == null) ...[
                      const Text(
                        'Serve this app on your WiFi - open it in any PC browser. Works while this app stays open.',
                      ),
                      const Text(
                        'Use only a network you trust (home WiFi or personal hotspot) - never airport, hotel, or open WiFi.',
                        style: TextStyle(fontSize: 12),
                      ),
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        onPressed: _startServe,
                        icon: const Icon(Icons.dns),
                        label: const Text('Show on PC'),
                      ),
                    ] else ...[
                      const Text('Open this address in any same-WiFi browser:'),
                      const SizedBox(height: 8),
                      Center(
                        child: Container(
                          color: Colors.white,
                          padding: const EdgeInsets.all(12),
                          child: QrImageView(
                            data: _serve!.url,
                            version: QrVersions.auto,
                            size: 200,
                            padding: EdgeInsets.zero,
                            backgroundColor: Colors.white,
                            errorCorrectionLevel: QrErrorCorrectLevel.M,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Center(
                        child: SelectableText(
                          _serve!.url,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      if (_mdnsUrl != null) ...[
                        const SizedBox(height: 8),
                        Center(
                          child: SelectableText(
                            _mdnsUrl!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        const Text(
                          'Stable address - no need to check the IP.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12),
                        ),
                      ] else if (_mdnsDone) ...[
                        const SizedBox(height: 8),
                        const Text(
                          'mDNS blocked on this network - the IP address above still works.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12),
                        ),
                      ],
                      const SizedBox(height: 4),
                      ValueListenableBuilder<int>(
                        valueListenable: _serve!.hits,
                        builder: (_, h, _) => Center(
                          child: Text(
                            h == 0
                                ? 'Waiting for a PC browser… (keep this app open)'
                                : 'Served $h request(s) — a PC is connected!',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _stopServe,
                        icon: const Icon(Icons.stop),
                        label: const Text('Stop'),
                      ),
                      const Text(
                        'Stop serving when done, especially on shared networks.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          Text('This device', style: Theme.of(context).textTheme.titleMedium),
          Card(
            child: ListTile(
              leading: Icon(kIsWeb ? Icons.web : Icons.smartphone),
              title: Text(store.deviceName),
              subtitle: Text(
                'Updated ${store.updatedAt}\nLast synced: ${store.lastSynced}\nTheme ${Theme.of(context).brightness.name} · #${store.accent.toRadixString(16)}',
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'File backup (Option 1)',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _exportFile,
                      icon: const Icon(Icons.upload),
                      label: const Text('Export'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _importFile,
                      icon: const Icon(Icons.download),
                      label: const Text('Import'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Text(
            'Send the exported file to your other device (chat, mail, USB, Drive) and Import it there.',
          ),
          const SizedBox(height: 16),
          ExpansionTile(
            title: const Text('Direct WiFi (no PC needed)'),
            subtitle: const Text('Advanced - phone sends straight to PC'),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'STEP 1 - on the SENDING device tap Send, then on the other device tap Receive. Same WiFi, no internet needed. Server stops after 5 min.',
                      ),
                      const Text(
                        'Trusted networks only (home WiFi or hotspot). The QR holds the address + PIN - don’t forward its screenshot.',
                        style: TextStyle(fontSize: 12),
                      ),
                      const SizedBox(height: 8),
                      if (_session == null)
                        FilledButton.icon(
                          onPressed: _startSend,
                          icon: const Icon(Icons.wifi),
                          label: const Text('Send via WiFi'),
                        )
                      else ...[
                        Center(
                          child: Container(
                            color: Colors.white,
                            padding: const EdgeInsets.all(12),
                            child: QrImageView(
                              data: WifiClient.buildQrPayload(
                                _sendUrl,
                                _sendPin,
                              ),
                              version: QrVersions.auto,
                              size: 200,
                              padding: EdgeInsets.zero,
                              backgroundColor: Colors.white,
                              errorCorrectionLevel: QrErrorCorrectLevel.M,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SelectableText(
                          '$_sendUrl   PIN: $_sendPin',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: _stopSend,
                          icon: const Icon(Icons.stop),
                          label: const Text('Stop sending'),
                        ),
                      ],
                      const Divider(),
                      const Text('STEP 2 - on the RECEIVING device:'),
                      const SizedBox(height: 8),
                      if (!kIsWeb)
                        FilledButton.icon(
                          onPressed: _busy ? null : _scanAndReceive,
                          icon: const Icon(Icons.qr_code_scanner),
                          label: const Text('Scan sender QR'),
                        )
                      else
                        const Text(
                          'Web cannot scan - type the address + PIN shown on the sender.',
                        ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _recvUrl,
                        decoration: const InputDecoration(
                          labelText: 'Sender address (http://192.168.1.x:port)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _recvPin,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'PIN',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        onPressed: _busy ? null : () => _receive(),
                        icon: _busy
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.sync),
                        label: const Text('Receive / sync now'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const SizedBox(height: 16),
          ExpansionTile(
            title: Text('Local backups (${backups.length}/5)'),
            subtitle: const Text('Auto-saved before every sync'),
            children: [
              if (backups.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      'Backups appear automatically before a sync overwrites this device.',
                    ),
                  ),
                ),
              for (var i = 0; i < backups.length; i++)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.history),
                  title: Text('Backup ${i + 1}'),
                  subtitle: Text(_backupLabel(backups[i])),
                  trailing: TextButton(
                    onPressed: () async {
                      final msg = await store.restoreBackup(i);
                      store.noteSynced();
                      _say(msg);
                    },
                    child: const Text('Restore'),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 24),
          const Text(
            'Private by design: data lives on your devices + files you move yourself. No account, no server, no fees.',
          ),
        ],
      ),
    );
  }

  // ---------- PIN + budgets live in the Menu / History tabs ----------

  String _backupLabel(String raw) {
    try {
      final s = Snapshot.decode(raw);
      return '${s.deviceName} - ${s.updatedAt}';
    } catch (_) {
      return 'backup';
    }
  }
}
