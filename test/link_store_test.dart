import 'package:expense/sync/link_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  DateTime t0() => DateTime.utc(2026, 9, 4, 12);

  test('create then pull sees the slot (never own)', () {
    final s = LinkStore();
    final id = s.create(
      pin: '123456',
      deviceId: 'pc',
      snapshot: '{"a":1}',
      name: 'PC',
      time: '2026-09-04T12:00:00.000Z',
    )!;
    expect(id.length, 8);
    final self = s.pull(id: id, pin: '123456', deviceId: 'pc');
    expect(self.outcome, LinkOutcome.ok);
    expect(self.peers, isEmpty);
  });

  test('two devices converge through push/pull', () {
    final s = LinkStore();
    final id = s.create(
      pin: '123456',
      deviceId: 'pc',
      snapshot: 'OLD',
      name: 'PC',
      time: '2026-09-03T00:00:00.000Z',
    )!;
    expect(
      s.push(
        id: id,
        pin: '123456',
        deviceId: 'ph',
        snapshot: 'NEW',
        name: 'Phone',
        time: '2026-09-04T00:00:00.000Z',
      ),
      LinkOutcome.ok,
    );
    final forPc = s.pull(id: id, pin: '123456', deviceId: 'pc');
    expect(forPc.peers.single.value.snapshot, 'NEW');
    final forPh = s.pull(id: id, pin: '123456', deviceId: 'ph');
    expect(forPh.peers.single.value.snapshot, 'OLD');
  });

  test('wrong pin, unknown box, bad input rejected', () {
    final s = LinkStore();
    final id = s.create(
      pin: '123456',
      deviceId: 'pc',
      snapshot: '{}',
      name: 'PC',
      time: 't',
    )!;
    expect(
      s.pull(id: id, pin: '000000', deviceId: 'x').outcome,
      LinkOutcome.forbidden,
    );
    expect(
      s.pull(id: 'ZZZZZZZZ', pin: '123456', deviceId: 'x').outcome,
      LinkOutcome.gone,
    );
    expect(
      s.push(
        id: id,
        pin: '123456',
        deviceId: '',
        snapshot: '{}',
        name: 'x',
        time: 't',
      ),
      LinkOutcome.badInput,
    );
    expect(
      s.create(pin: '12', deviceId: 'pc', snapshot: '{}', name: 'x', time: 't'),
      isNull,
    );
    expect(
      s.create(
        pin: '123456',
        deviceId: 'pc',
        snapshot: '',
        name: 'x',
        time: 't',
      ),
      isNull,
    );
  });

  test('boxes expire after TTL and unlink deletes', () {
    var now = t0();
    final s = LinkStore(clock: () => now);
    final id = s.create(
      pin: '123456',
      deviceId: 'pc',
      snapshot: '{}',
      name: 'PC',
      time: 't',
    )!;
    now = now.add(const Duration(days: 8));
    expect(
      s.pull(id: id, pin: '123456', deviceId: 'x').outcome,
      LinkOutcome.gone,
    );

    var now2 = t0();
    final s2 = LinkStore(clock: () => now2);
    final id2 = s2.create(
      pin: '123456',
      deviceId: 'pc',
      snapshot: '{}',
      name: 'PC',
      time: 't',
    )!;
    expect(s2.unlink(id: id2, pin: '000000'), isTrue);
    expect(
      s2.pull(id: id2, pin: '123456', deviceId: 'x').outcome,
      LinkOutcome.ok,
    ); // wrong pin keeps the box
    expect(s2.unlink(id: id2, pin: '123456'), isTrue);
    expect(
      s2.pull(id: id2, pin: '123456', deviceId: 'x').outcome,
      LinkOutcome.gone,
    );
  });

  group('link secrets (Phase 5 closure)', () {
    test('generated secrets are distinct 128-bit hex', () {
      final seen = <String>{};
      for (var i = 0; i < 50; i++) {
        final s = newLinkSecret();
        // 16 bytes = 32 lowercase hex chars = 128 bits.
        expect(s, matches(RegExp(r'^[0-9a-f]{32}$')));
        expect(seen.add(s), isTrue); // no repeats
      }
    });

    test('correct secret authorizes; wrong secret rejects', () {
      final s = LinkStore();
      final id = s.create(
        pin: '1234',
        deviceId: 'a',
        snapshot: '{}',
        secret: '00' * 16,
        name: 'A',
        time: 't',
      )!;
      expect(
        s.push(
          id: id,
          pin: '1234',
          deviceId: 'b',
          snapshot: '{}',
          secret: '00' * 16,
          name: 'B',
          time: 't',
        ),
        LinkOutcome.ok,
      );
      expect(
        s.push(
          id: id,
          pin: '1234',
          deviceId: 'b',
          snapshot: '{}',
          secret: 'ff' * 16,
          name: 'B',
          time: 't',
        ),
        LinkOutcome.secretRequired,
      );
      expect(
        s.pull(id: id, pin: '1234', deviceId: 'a', secret: '00' * 16).outcome,
        LinkOutcome.ok,
      );
      expect(
        s.pull(id: id, pin: '1234', deviceId: 'a', secret: 'nope').outcome,
        LinkOutcome.secretRequired,
      );
    });

    test('short PIN alone cannot authorize a secret box (no downgrade)', () {
      final s = LinkStore();
      final id = s.create(
        pin: '1234',
        deviceId: 'a',
        snapshot: '{}',
        secret: 'ab' * 16,
        name: 'A',
        time: 't',
      )!;
      // Correct short PIN, missing secret: rejected distinctly.
      expect(
        s.pull(id: id, pin: '1234', deviceId: 'x').outcome,
        LinkOutcome.secretRequired,
      );
      expect(
        s.push(
          id: id,
          pin: '1234',
          deviceId: 'x',
          snapshot: '{}',
          name: 'X',
          time: 't',
        ),
        LinkOutcome.secretRequired,
      );
      // Wrong PIN stays "wrong pin" (checked first).
      expect(
        s.pull(id: id, pin: '0000', deviceId: 'x').outcome,
        LinkOutcome.forbidden,
      );
    });

    test('legacy boxes without secrets stay PIN-only', () {
      final s = LinkStore();
      final id = s.create(
        pin: '1234',
        deviceId: 'a',
        snapshot: '{}',
        name: 'A',
        time: 't',
      )!;
      expect(
        s.pull(id: id, pin: '1234', deviceId: 'x').outcome,
        LinkOutcome.ok,
      );
      expect(
        s.push(
          id: id,
          pin: '1234',
          deviceId: 'x',
          snapshot: '{}',
          name: 'X',
          time: 't',
        ),
        LinkOutcome.ok,
      );
    });

    test('secret dies with the box (TTL expiry and unlink)', () {
      var now = t0();
      final s = LinkStore(clock: () => now);
      final id = s.create(
        pin: '1234',
        deviceId: 'a',
        snapshot: '{}',
        secret: 'ab' * 16,
        name: 'A',
        time: 't',
      )!;
      now = now.add(const Duration(days: 8));
      expect(
        s.pull(id: id, pin: '1234', deviceId: 'x', secret: 'ab' * 16).outcome,
        LinkOutcome.gone,
      ); // expired: even the secret cannot revive it

      final s2 = LinkStore();
      final id2 = s2.create(
        pin: '1234',
        deviceId: 'a',
        snapshot: '{}',
        secret: 'ab' * 16,
        name: 'A',
        time: 't',
      )!;
      expect(s2.unlink(id: id2, pin: '1234'), isTrue); // Stop/Unpair
      expect(
        s2.pull(id: id2, pin: '1234', deviceId: 'x', secret: 'ab' * 16).outcome,
        LinkOutcome.gone,
      );
    });
  });
}
