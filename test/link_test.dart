import 'package:expense/store.dart';
import 'package:expense/sync/relay_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('link pairing persists across restarts; unlink forgets', () async {
    SharedPreferences.setMockInitialValues({});
    final a = ExpenseStore();
    await a.load();
    expect(a.linked, isFalse);

    await a.setRelayOrigin('http://pc:8080');
    await a.setLink(
      id: 'ABCDEFGH',
      pin: '123456',
      peer: 'PC',
      secret: '00' * 16,
    );
    expect(a.linked, isTrue);
    expect(a.linkPeer, 'PC');
    expect(a.linkSecret, '00' * 16);

    final b = ExpenseStore();
    await b.load();
    expect(b.linked, isTrue);
    expect(b.linkId, 'ABCDEFGH');
    expect(b.linkPin, '123456');
    expect(b.linkPeer, 'PC');
    expect(b.linkSecret, '00' * 16);
    expect(b.relayOrigin, 'http://pc:8080');

    await b.clearLink();
    expect(b.linked, isFalse);
    expect(b.linkSecret, '');
    final c = ExpenseStore();
    await c.load();
    expect(c.linked, isFalse);
    expect(c.linkSecret, '');
  });

  test('newest peer slot wins the converge decision', () {
    final old = LinkPeer(
      deviceId: 'd1',
      snapshot: '{}',
      name: 'A',
      time: '2026-09-01T00:00:00.000Z',
    );
    final newer = LinkPeer(
      deviceId: 'd2',
      snapshot: '{}',
      name: 'B',
      time: '2026-09-03T00:00:00.000Z',
    );
    LinkPeer? best;
    for (final p in [old, newer]) {
      if (best == null || p.timeValue.isAfter(best.timeValue)) best = p;
    }
    expect(best?.deviceId, 'd2');
    expect(
      decideSync(local: DateTime.utc(2026, 9, 2), remote: newer.timeValue),
      SyncDirection.pull,
    );
  });
}
