// Phase 4 transport e2e: v2 sync over real localhost HTTP, both transports.
// - Direct WiFi: shelf sender (v1 + v2 endpoints) <-> http receiver.
// - Link mailbox: phone-hosted shelf relay (same LinkStore protocol as the
//   Node relay) carrying v2 slots alongside v1.
// VM-only (dart:io shelf servers + drift native); never compiled to web.
import 'dart:io';

import 'package:expense/data/app_db.dart';
import 'package:expense/data/domain_store.dart';
import 'package:expense/data/drift_domain_store.dart';
import 'package:expense/store.dart';
import 'package:expense/sync/phone_host_io.dart';
import 'package:expense/sync/relay_client.dart';
import 'package:expense/sync/wifi_client.dart';
import 'package:expense/sync/wifi_host.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:drift/native.dart';

class _Db {
  DriftDomainStore backend;
  final File file;
  _Db._(this.backend, this.file);

  static Future<_Db> open(String name) async {
    final file = File('${Directory.systemTemp.path}/dhadda_p4e_$name.sqlite');
    for (final s in ['', '-journal', '-wal', '-shm']) {
      final f = s.isEmpty ? file : File('${file.path}$s');
      if (await f.exists()) {
        try {
          await f.delete();
        } catch (_) {}
      }
    }
    return _Db._(DriftDomainStore(AppDb(NativeDatabase(file))), file);
  }

  Future<void> dispose() async {
    try {
      await backend.close();
    } catch (_) {}
    for (var i = 0; i < 20; i++) {
      try {
        if (await file.exists()) await file.delete();
        return;
      } catch (_) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
    }
  }
}

Future<ExpenseStore> _store(DomainStore backend, String device) async {
  SharedPreferences.setMockInitialValues({});
  final s = ExpenseStore(domainOverride: backend);
  await s.load();
  s.deviceId = device;
  return s;
}

Future<void> _addTxn(ExpenseStore s, String note, double amount) =>
    s.addTransaction(
      type: 'expense',
      amount: amount,
      categoryId: 'food',
      date: DateTime(2026, 9, 6),
      note: note,
    );

void main() {
  test('direct WiFi v2: merge both ways over HTTP', () async {
    final dba = await _Db.open('wifia');
    final dbb = await _Db.open('wifib');
    HostSession? session;
    try {
      final a = await _store(dba.backend, 'devA');
      final b = await _store(dbb.backend, 'devB');
      await _addTxn(a, 'A1', 100);
      session = await startSendServer(
        currentSnapshot: a.exportJson,
        currentSnapshotV2: a.exportSnapshotV2,
        onUpload: (body) async {
          await a.ingestPeerSnapshot(body);
        },
        pin: '123456',
      );
      // Receiver merges the v2 snapshot, then posts its union back.
      final v2 = await WifiClient.fetchRemoteSnapshotV2(
        session.url,
        session.pin,
      );
      expect(v2, isNotNull);
      expect(await b.ingestPeerSnapshot(v2!), startsWith('Synced'));
      await _addTxn(b, 'B1', 200);
      await WifiClient.pushLocalSnapshot(
        session.url,
        session.pin,
        b.exportSnapshotV2(),
      );
      // Sender merged the union (no whole-replace anywhere).
      expect(a.transactions.any((t) => t.note == 'B1'), isTrue);
      expect(a.transactions.any((t) => t.note == 'A1'), isTrue);
      expect(b.transactions.any((t) => t.note == 'A1'), isTrue);
    } finally {
      await session?.close();
      await dba.dispose();
      await dbb.dispose();
    }
  });

  test('direct WiFi falls back to v1 against old senders', () async {
    final dbb = await _Db.open('wififb');
    HostSession? session;
    try {
      // v1-only sender: no v2 closure, like a pre-Phase-4 app.
      String v1 =
          '{"version":1,"updatedAt":"2026-09-06T12:00:00.000Z",'
          '"deviceId":"old","deviceName":"Old","categories":[],'
          '"transactions":[{"id":"o1","type":"expense","amount":5,'
          '"categoryId":"food","date":1788220800000,"note":"Old","mode":"cash",'
          '"projectId":""}],"loans":[],"projects":[]}';
      session = await startSendServer(
        currentSnapshot: () => v1,
        onUpload: (_) {},
        pin: '123456',
      );
      expect(
        await WifiClient.fetchRemoteSnapshotV2(session.url, session.pin),
        isNull,
      ); // 404 -> fallback
      final b = await _store(dbb.backend, 'devB');
      final msg = await b.ingestPeerSnapshot(
        await WifiClient.fetchRemoteSnapshot(session.url, session.pin),
        peerName: 'Old',
      );
      expect(msg, startsWith('Synced'));
      expect(b.transactions.any((t) => t.id == 'o1'), isTrue);
    } finally {
      await session?.close();
      await dbb.dispose();
    }
  });

  test('link mailbox carries v2 end to end over HTTP', () async {
    final dba = await _Db.open('linka');
    final dbb = await _Db.open('linkb');
    PhoneHostSession? host;
    try {
      host = await startPhoneHost();
    } catch (_) {
      markTestSkipped('local HTTP host unavailable');
    }
    try {
      final origin = host!.url;
      final a = await _store(dba.backend, 'devA');
      final b = await _store(dbb.backend, 'devB');
      const pin = '123456';
      final created = await LinkClient(origin).create(
        pin: pin,
        deviceId: 'devA',
        snapshot: a.exportJson(),
        snapshotV2: a.exportSnapshotV2(),
        name: 'A',
        time: a.updatedAt,
      );
      await _addTxn(a, 'A1', 100);
      // B joins with both encodings, then both converge via the mailbox.
      await LinkClient(origin).push(
        link: created.link,
        pin: pin,
        deviceId: 'devB',
        snapshot: b.exportJson(),
        snapshotV2: b.exportSnapshotV2(),
        name: 'B',
        time: b.updatedAt,
      );
      for (final peer in await LinkClient(
        origin,
      ).pull(link: created.link, pin: pin, deviceId: 'devA')) {
        expect(peer.snapshotV2, isNotEmpty); // v2 survived the relay
        await a.ingestPeerSnapshot(peer.snapshotV2, peerName: peer.name);
      }
      await _addTxn(b, 'B1', 200);
      await LinkClient(origin).push(
        link: created.link,
        pin: pin,
        deviceId: 'devB',
        snapshot: b.exportJson(),
        snapshotV2: b.exportSnapshotV2(),
        name: 'B',
        time: b.updatedAt,
      );
      for (final peer in await LinkClient(
        origin,
      ).pull(link: created.link, pin: pin, deviceId: 'devA')) {
        await a.ingestPeerSnapshot(peer.snapshotV2, peerName: peer.name);
      }
      await LinkClient(origin).push(
        link: created.link,
        pin: pin,
        deviceId: 'devA',
        snapshot: a.exportJson(),
        snapshotV2: a.exportSnapshotV2(),
        name: 'A',
        time: a.updatedAt,
      );
      for (final peer in await LinkClient(
        origin,
      ).pull(link: created.link, pin: pin, deviceId: 'devB')) {
        await b.ingestPeerSnapshot(peer.snapshotV2, peerName: peer.name);
      }
      expect(a.transactions.any((t) => t.note == 'B1'), isTrue);
      expect(b.transactions.any((t) => t.note == 'A1'), isTrue);
    } finally {
      await host?.close();
      await dba.dispose();
      await dbb.dispose();
    }
  });
}
