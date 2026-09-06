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
        time: '2026-09-04T12:00:00.000Z')!;
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
        time: '2026-09-03T00:00:00.000Z')!;
    expect(
        s.push(
            id: id,
            pin: '123456',
            deviceId: 'ph',
            snapshot: 'NEW',
            name: 'Phone',
            time: '2026-09-04T00:00:00.000Z'),
        LinkOutcome.ok);
    final forPc =
        s.pull(id: id, pin: '123456', deviceId: 'pc');
    expect(forPc.peers.single.value.snapshot, 'NEW');
    final forPh =
        s.pull(id: id, pin: '123456', deviceId: 'ph');
    expect(forPh.peers.single.value.snapshot, 'OLD');
  });

  test('wrong pin, unknown box, bad input rejected', () {
    final s = LinkStore();
    final id = s.create(
        pin: '123456',
        deviceId: 'pc',
        snapshot: '{}',
        name: 'PC',
        time: 't')!;
    expect(s.pull(id: id, pin: '000000', deviceId: 'x').outcome,
        LinkOutcome.forbidden);
    expect(s.pull(id: 'ZZZZZZZZ', pin: '123456', deviceId: 'x').outcome,
        LinkOutcome.gone);
    expect(
        s.push(
            id: id,
            pin: '123456',
            deviceId: '',
            snapshot: '{}',
            name: 'x',
            time: 't'),
        LinkOutcome.badInput);
    expect(
        s.create(
            pin: '12',
            deviceId: 'pc',
            snapshot: '{}',
            name: 'x',
            time: 't'),
        isNull);
    expect(
        s.create(
            pin: '123456',
            deviceId: 'pc',
            snapshot: '',
            name: 'x',
            time: 't'),
        isNull);
  });

  test('boxes expire after TTL and unlink deletes', () {
    var now = t0();
    final s = LinkStore(clock: () => now);
    final id = s.create(
        pin: '123456',
        deviceId: 'pc',
        snapshot: '{}',
        name: 'PC',
        time: 't')!;
    now = now.add(const Duration(days: 8));
    expect(s.pull(id: id, pin: '123456', deviceId: 'x').outcome,
        LinkOutcome.gone);

    var now2 = t0();
    final s2 = LinkStore(clock: () => now2);
    final id2 = s2.create(
        pin: '123456',
        deviceId: 'pc',
        snapshot: '{}',
        name: 'PC',
        time: 't')!;
    expect(s2.unlink(id: id2, pin: '000000'), isTrue);
    expect(
        s2.pull(id: id2, pin: '123456', deviceId: 'x').outcome,
        LinkOutcome.ok); // wrong pin keeps the box
    expect(s2.unlink(id: id2, pin: '123456'), isTrue);
    expect(s2.pull(id: id2, pin: '123456', deviceId: 'x').outcome,
        LinkOutcome.gone);
  });
}