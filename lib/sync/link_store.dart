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
  LinkSlot({
    required this.snapshot,
    this.snapshotV2 = '',
    required this.name,
    required this.time,
  });
}

class _Box {
  String pin;

  /// High-entropy link secret (128-bit hex, client-generated). Empty means
  /// a legacy box: PIN-only auth with reduced strength. Present means both
  /// PIN and secret are required — PIN-only attempts are rejected, never
  /// silently downgraded. Dies with the box (TTL/unlink); never logged or
  /// returned in pull responses.
  String secret;
  final Map<String, LinkSlot> slots = {};
  DateTime touched;
  _Box({required this.pin, this.secret = '', required DateTime now})
    : touched = now;
}

enum LinkOutcome { ok, gone, forbidden, badInput, secretRequired }

class LinkPull {
  final LinkOutcome outcome;
  final List<MapEntry<String, LinkSlot>> peers;
  const LinkPull(this.outcome, this.peers);
}

/// Fresh 128-bit link secret (32 hex chars) from a CSPRNG. Generated
/// client-side at link create and carried in the pairing QR; the server
/// stores it opaquely and never returns it. Independent from the app PIN,
/// user PINs, timestamps, and device IDs.
String newLinkSecret() {
  final r = Random.secure();
  final bytes = List<int>.generate(16, (_) => r.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
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
      id = List.generate(8, (_) => _abc[_random.nextInt(_abc.length)]).join();
    } while (_boxes.containsKey(id));
    return id;
  }

  /// Creates a mailbox with this device's first slot. Returns the
  /// link id, or null on bad input. [secret] is stored opaquely; when
  /// non-empty the box requires it on every push/pull alongside the PIN.
  String? create({
    required String pin,
    required String deviceId,
    required String snapshot,
    String snapshotV2 = '',
    String secret = '',
    required String name,
    required String time,
  }) {
    if (!_validPin(pin) || deviceId.isEmpty || snapshot.isEmpty) {
      return null;
    }
    sweep();
    if (_boxes.length >= maxBoxes) {
      final oldest = _boxes.entries
          .reduce((a, b) => a.value.touched.isBefore(b.value.touched) ? a : b)
          .key;
      _boxes.remove(oldest);
    }
    final id = _nid();
    final box = _Box(pin: pin, secret: secret, now: _clock());
    box.slots[deviceId] = LinkSlot(
      snapshot: snapshot,
      snapshotV2: snapshotV2,
      name: name,
      time: time,
    );
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

  /// PIN + secret gate shared by push/pull. A box carrying a secret
  /// rejects callers without it (no silent downgrade to PIN-only).
  /// Returns null when authorized, otherwise the rejecting outcome.
  LinkOutcome? _authGate(_Box b, String pin, String secret) {
    if (b.pin != pin) return LinkOutcome.forbidden;
    if (!_secretOk(b, secret)) return LinkOutcome.secretRequired;
    return null;
  }

  /// True when no secret is required, or the presented one matches.
  bool _secretOk(_Box b, String secret) =>
      b.secret.isEmpty || secret == b.secret;

  LinkOutcome push({
    required String id,
    required String pin,
    required String deviceId,
    required String snapshot,
    String snapshotV2 = '',
    String secret = '',
    required String name,
    required String time,
  }) {
    final b = _get(id);
    if (b == null) return LinkOutcome.gone;
    final gate = _authGate(b, pin, secret);
    if (gate != null) return gate;
    if (deviceId.isEmpty || snapshot.isEmpty) {
      return LinkOutcome.badInput;
    }
    b.slots[deviceId] = LinkSlot(
      snapshot: snapshot,
      snapshotV2: snapshotV2,
      name: name,
      time: time,
    );
    b.touched = _clock();
    return LinkOutcome.ok;
  }

  /// Everyone else's slots (never the requester's own).
  LinkPull pull({
    required String id,
    required String pin,
    required String deviceId,
    String secret = '',
  }) {
    final b = _get(id);
    if (b == null) return const LinkPull(LinkOutcome.gone, []);
    final gate = _authGate(b, pin, secret);
    if (gate != null) return LinkPull(gate, []);
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
