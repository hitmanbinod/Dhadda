import 'dart:async';

import '../store.dart';
import 'relay_client.dart';

DateTime _epoch() =>
    DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

/// Keeps linked devices converged for as long as the app is open:
/// pushes on every local change (debounced) and polls the relay
/// mailbox every 15 seconds. Newer snapshot always wins, so the
/// two sides can never ping-pong.
class LinkEngine {
  final ExpenseStore store;
  Timer? _poll;
  Timer? _debounce;
  bool _syncing = false;
  bool _started = false;
  String? _lastPushedAt;
  void Function()? _onStore;

  LinkEngine(this.store);

  bool get isLinked => store.linked;

  void start() {
    if (_started) return;
    _started = true;
    _onStore = () {
      if (!store.linked) return;
      _debounce?.cancel();
      _debounce = Timer(
          const Duration(seconds: 3), () => syncNow());
    };
    store.addListener(_onStore!);
    _poll?.cancel();
    _poll = Timer.periodic(
        const Duration(seconds: 15), (_) => syncNow());
    syncNow(); // immediate catch-up on boot
  }

  void stop() {
    _started = false;
    _poll?.cancel();
    _poll = null;
    _debounce?.cancel();
    _debounce = null;
    final l = _onStore;
    if (l != null) store.removeListener(l);
    _onStore = null;
  }

  /// Forgets what was last announced (used after unpair/repair).
  void reset() {
    _lastPushedAt = null;
  }

  /// Records an externally completed converge so the next poll stays quiet.
  void markAnnounced(String updatedAt) {
    _lastPushedAt = updatedAt;
  }

  /// One full cycle: pull peers, take anything newer, announce self.
  /// Returns a short human message for snackbars.
  Future<String> syncNow() async {
    if (!store.linked) return 'Not linked yet.';
    if (_syncing) return 'Sync already running.';
    final origin = store.relayOrigin;
    if (origin.isEmpty) {
      return 'No relay - open the app on your PC first.';
    }
    _syncing = true;
    try {
      final client = LinkClient(origin);
      final peers = await client.pull(
          link: store.linkId,
          pin: store.linkPin,
          deviceId: store.deviceId);
      LinkPeer? best;
      for (final p in peers) {
        if (p.snapshot.isEmpty) continue;
        if (best == null ||
            p.timeValue.isAfter(best.timeValue)) {
          best = p;
        }
      }
      final localTime =
          DateTime.tryParse(store.updatedAt) ?? _epoch();
      if (best != null && best.timeValue.isAfter(localTime)) {
        final msg = store.importSnapshotString(best.snapshot);
        store.noteSynced();
        await _announce(client);
        store.setLinkStatus('Synced with ${best.name}.');
        return msg;
      }
      if (store.updatedAt != _lastPushedAt) {
        await _announce(client);
        store.noteSynced();
        store.setLinkStatus('Synced.');
      } else {
        store.setLinkStatus('Up to date.');
      }
      return 'Up to date.';
    } on FormatException catch (e) {
      final m = '$e';
      if (m.contains('gone') || m.contains('expired')) {
        await store.clearLink('Link expired - pair again.');
        return 'Link expired - scan a fresh code to pair again.';
      }
      store.setLinkStatus('Sync needs attention.');
      return m.replaceFirst('FormatException: ', '');
    } catch (_) {
      store.setLinkStatus('Offline - will retry by itself.');
      return 'Could not reach the other side (same WiFi?).';
    } finally {
      _syncing = false;
    }
  }

  Future<void> _announce(LinkClient client) async {
    await client.push(
        link: store.linkId,
        pin: store.linkPin,
        deviceId: store.deviceId,
        snapshot: store.exportJson(),
        name: store.deviceName,
        time: store.updatedAt);
    _lastPushedAt = store.updatedAt;
  }
}