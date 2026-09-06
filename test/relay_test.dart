import 'package:expense/models.dart';
import 'package:expense/sync/relay_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('decideSync: newer side always wins', () {
    final old = DateTime.utc(2026, 9, 1);
    final newerTime = DateTime.utc(2026, 9, 3);
    expect(
        decideSync(local: old, remote: newerTime), SyncDirection.pull);
    expect(
        decideSync(local: newerTime, remote: old), SyncDirection.push);
    expect(
        decideSync(local: old, remote: old), SyncDirection.push);
  });

  test('QR v2 builds and parses (origin travels in the code)', () {
    const origin = 'http://192.168.1.75:8080';
    final payload = QrV2.build(origin, 'AB12CD', '123456');
    final t = QrV2.parse(payload);
    expect(t, isNotNull);
    expect(t!.origin, origin);
    expect(t.session, 'AB12CD');
    expect(t.pin, '123456');
    expect(QrV2.parse('hello'), isNull);
    expect(QrV2.parse('EXPENSESYNC2::only-two::parts'), isNull);
    expect(QrV2.parse('EXPENSESYNC2::ftp://x::AB12CD::1'), isNull);
  });

  test('relay view parses waiting and done stages', () {
    final waiting = RelayView.fromJson({
      'stage': 'waiting',
      'offer': {'snapshot': '{}', 'name': 'PC', 'time': 't'},
      'answer': null,
    });
    expect(waiting.done, isFalse);
    expect(waiting.offerName, 'PC');
    expect(waiting.answerSnapshot, isNull);

    final done = RelayView.fromJson({
      'stage': 'done',
      'offer': {'snapshot': '{}', 'name': 'PC', 'time': 't'},
      'answer': {'snapshot': '{"a":1}', 'name': 'Phone', 'time': 't2'},
    });
    expect(done.done, isTrue);
    expect(done.answerSnapshot, '{"a":1}');
  });

  test('snapshot carries relay-safe metadata', () {
    final s = Snapshot(
      version: kSnapshotVersion,
      updatedAt: DateTime.utc(2026, 9, 3).toIso8601String(),
      deviceId: 'd1',
      deviceName: 'PC',
      categories: defaultCategories(),
      transactions: const [],
      loans: const [],
      projects: const [],
    );
    final back = Snapshot.decode(s.encode());
    expect(back.deviceName, 'PC');
    expect(back.updatedAtTime, DateTime.utc(2026, 9, 3));
  });
}