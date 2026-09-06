import 'package:expense/models.dart';
import 'package:expense/sync/wifi_client.dart';
import 'package:expense/sync/wifi_host.dart';
import 'package:flutter_test/flutter_test.dart';

/// Real end-to-end test of the WiFi sync protocol: a live shelf HTTP
/// server (the SENDER, as started by SyncScreen) plus the real http
/// client (the RECEIVER). Runs over localhost with PIN auth.

Snapshot _deviceSnapshot({
  required String deviceId,
  required String deviceName,
  required DateTime updatedAt,
  String note = '',
}) {
  return Snapshot(
    version: kSnapshotVersion,
    updatedAt: updatedAt.toUtc().toIso8601String(),
    deviceId: deviceId,
    deviceName: deviceName,
    categories: defaultCategories(),
    projects: const [],
    transactions: [
      Txn(
        id: 't-$deviceId',
        type: 'expense',
        amount: 100,
        categoryId: 'food',
        date: updatedAt.millisecondsSinceEpoch,
        note: note,
      ),
    ],
    loans: const [],
  );
}

void main() {
  test('e2e: receiver pulls newer snapshot from sender', () async {
    final newer = _deviceSnapshot(
      deviceId: 'phone',
      deviceName: 'Phone',
      updatedAt: DateTime.utc(2026, 9, 3, 12),
      note: 'sender-data',
    ).encode();
    String? uploaded;
    final session = await startSendServer(
      currentSnapshot: () => newer,
      onUpload: (body) => uploaded = body,
      pin: '123456',
    );
    try {
      expect(session.url.startsWith('http://'), isTrue);

      // Wrong PIN is rejected.
      expect(
        () => WifiClient.fetchRemoteMeta(session.url, '000000'),
        throwsA(isA<FormatException>()),
      );

      // Meta + full snapshot round-trip with the right PIN.
      final meta =
          await WifiClient.fetchRemoteMeta(session.url, '123456');
      expect(meta?.toUtc().toIso8601String(),
          DateTime.utc(2026, 9, 3, 12).toIso8601String());
      final body =
          await WifiClient.fetchRemoteSnapshot(session.url, '123456');
      final decoded = Snapshot.decode(body);
      expect(decoded.deviceName, 'Phone');
      expect(decoded.transactions.single.note, 'sender-data');
      expect(uploaded, isNull); // pull-only so far
    } finally {
      await session.close();
    }
  });

  test('e2e: newer receiver pushes to older sender (both directions)',
      () async {
    // Sender (older, "desktop") hosts; receiver ("phone") holds newer data.
    final older = _deviceSnapshot(
      deviceId: 'desktop',
      deviceName: 'Desktop',
      updatedAt: DateTime.utc(2026, 9, 1, 8),
    ).encode();
    final newer = _deviceSnapshot(
      deviceId: 'phone',
      deviceName: 'Phone',
      updatedAt: DateTime.utc(2026, 9, 3, 12),
      note: 'phone-data',
    ).encode();

    var hosted = older; // what the sender currently has
    final session = await startSendServer(
      currentSnapshot: () => hosted,
      onUpload: (body) => hosted = body, // sender adopts pushed snapshot
      pin: '654321',
    );
    try {
      // Direction 1: receiver is newer -> push wins.
      final remoteMeta =
          await WifiClient.fetchRemoteMeta(session.url, '654321');
      final remoteTime = remoteMeta ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      final localTime =
          Snapshot.decode(newer).updatedAtTime; // receiver's copy
      expect(localTime.isAfter(remoteTime), isTrue);
      await WifiClient.pushLocalSnapshot(
          session.url, '654321', newer);
      expect(Snapshot.decode(hosted).deviceName, 'Phone');
      expect(Snapshot.decode(hosted).transactions.single.note,
          'phone-data');

      // Direction 2: sender now newer -> receiver pulls.
      final pulled =
          await WifiClient.fetchRemoteSnapshot(session.url, '654321');
      expect(Snapshot.decode(pulled).deviceName, 'Phone');
    } finally {
      await session.close();
    }

    // Server is gone after close.
    expect(
      () => WifiClient.fetchRemoteMeta(session.url, '654321'),
      throwsA(anything),
    );
  });
}