import 'dart:math';

/// One device's latest state inside a link mailbox.
/// [snapshotV2] carries the record-level sync encoding alongside the legacy
/// v1 [snapshot]; empty when the peer is v1-only. Relays treat both as
/// opaque strings.
class LinkSlot {
  String snapshot;
  String snapshotV2;
  String name;
  String time;
  LinkSlot(
      {required this.snapshot,
      this.snapshotV2 = '',
      required this.name,
      required this.time});
}

class _Box {
  String pin;
  final Map<String, LinkSlot> slots = {};
  DateTime touched;
  _Box({required this.pin, required DateTime now}) : touched = now;
}

enum LinkOutcome { ok, gone, forbidden, badInput }

class LinkPull {
  final LinkOutcome outcome;
  final List<MapEntry<String, LinkSlot>> peers;
  const LinkPull(this.outcome, this.peers);
}

/// In-memory link mail_boxes with a sliding TTL.
/// Pure Dart (no platform code) so it is unit-testable. The PC relay
/// and the phone-hosted server implement the same protocol as this.
class LinkStore {
  static const ttl = Duration(days: 7);
  static const maxBoxes = 50;
  static const _abc = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

  final Map<String, _Box> _boxes = {};
  final Random _random;
  final DateTime Function() _clock;

  LinkStore({Random? random, DateTime Function()? clock})
      : _random = random ?? Random.secure(),
        _clock = clock ?? DateTime.now;

  void sweep() {
    final now = _clock();
    _boxes.removeWhere((_, b) => now.difference(b.touched) > ttl);
  }

  bool _validPin(String pin) => pin.length >= 4 && pin.length <= 12;

  String _nid() {
    var id = '';
    do {
      id = List.generate(
              8, (_) => _abc[_random.nextInt(_abc.length)])
          .join();
    } while (_boxes.containsKey(id));
    return id;
  }

  /// Creates a mailbox with this device's first slot. Returns the
  /// link id, or null on bad input.
  String? create(
      {required String pin,
      required String deviceId,
      required String snapshot,
      String snapshotV2 = '',
      required String name,
      required String time}) {
    if (!_validPin(pin) || deviceId.isEmpty || snapshot.isEmpty) {
      return null;
    }
    sweep();
    if (_boxes.length >= maxBoxes) {
      final oldest = _boxes.entries
          .reduce((a, b) => a.value.touched.isBefore(b.value.touched)
              ? a
              : b)
          .key;
      _boxes.remove(oldest);
    }
    final id = _nid();
    final box = _Box(pin: pin, now: _clock());
    box.slots[deviceId] = LinkSlot(
        snapshot: snapshot, snapshotV2: snapshotV2, name: name, time: time);
    _boxes[id] = box;
    return id;
  }

  _Box? _get(String id) {
    final b = _boxes[id];
    if (b == null) return null;
    if (_clock().difference(b.touched) > ttl) {
      _boxes.remove(id);
      return null;
    }
    return b;
  }

  LinkOutcome push(
      {required String id,
      required String pin,
      required String deviceId,
      required String snapshot,
      String snapshotV2 = '',
      required String name,
      required String time}) {
    final b = _get(id);
    if (b == null) return LinkOutcome.gone;
    if (b.pin != pin) return LinkOutcome.forbidden;
    if (deviceId.isEmpty || snapshot.isEmpty) {
      return LinkOutcome.badInput;
    }
    b.slots[deviceId] = LinkSlot(
        snapshot: snapshot, snapshotV2: snapshotV2, name: name, time: time);
    b.touched = _clock();
    return LinkOutcome.ok;
  }

  /// Everyone else's slots (never the requester's own).
  LinkPull pull(
      {required String id,
      required String pin,
      required String deviceId}) {
    final b = _get(id);
    if (b == null) return const LinkPull(LinkOutcome.gone, []);
    if (b.pin != pin) {
      return const LinkPull(LinkOutcome.forbidden, []);
    }
    b.touched = _clock();
    final peers = b.slots.entries
        .where((e) => e.key != deviceId)
        .toList(growable: false);
    return LinkPull(LinkOutcome.ok, peers);
  }

  /// Deletes the box when the PIN matches. Always reports true.
  bool unlink({required String id, required String pin}) {
    final b = _boxes[id];
    if (b != null && b.pin == pin) _boxes.remove(id);
    return true;
  }
}