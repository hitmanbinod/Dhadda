// Phase 7: log-privacy regression tests. Captures debugPrint output in a
// zone while exercising failure paths loaded with secret-marked data, and
// asserts no secrets, PINs, financial content, or payloads leak.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:expense/data/app_db.dart';
import 'package:expense/data/domain_store.dart';
import 'package:expense/data/drift_domain_store.dart';
import 'package:expense/store.dart';
import 'package:expense/sync/phone_host_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

Future<List<String>> _capturePrints(Future<void> Function() fn) async {
  final lines = <String>[];
  await runZoned(
    () async => fn(),
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) => lines.add(line),
    ),
  );
  return lines;
}

/// Backend that fails writes with attacker-visible error text.
class _LoudFailure extends DriftDomainStore {
  _LoudFailure(super.db);

  @override
  Future<void> applyV2({
    required DomainData data,
    required Map<String, RecordMeta> meta,
    required List<TombEntry> tombs,
  }) =>
      throw StateError(
          'disk gone SECRETNOTE-XYZ amount 9999 pin 1234');
}

void main() {
  test('store failure logs carry no secrets or financial content', () async {
    SharedPreferences.setMockInitialValues({});
    final file = File(
        '${Directory.systemTemp.path}/dhadda_p7_logfail.sqlite');
    for (final s in ['', '-journal', '-wal', '-shm']) {
      final f = s.isEmpty ? file : File('${file.path}$s');
      if (await f.exists()) {
        try {
          await f.delete();
        } catch (_) {}
      }
    }
    DriftDomainStore? backend;
    try {
      backend = DriftDomainStore(AppDb(NativeDatabase(file)));
      final s = ExpenseStore(domainOverride: backend);
      await s.load();
      await s.addTransaction(
          type: 'expense',
          amount: 4321,
          categoryId: 'food',
          date: DateTime(2026, 9, 6),
          note: 'SECRETNOTE-XYZ');
      final failing = ExpenseStore(
          domainOverride: _LoudFailure(backend.db));
      await failing.load();
      final lines = await _capturePrints(() async {
        await failing.importSnapshotV2(s.exportSnapshotV2());
      });
      final blob = lines.join('\n');
      expect(blob, isNot(contains('SECRETNOTE-XYZ')));
      expect(blob, isNot(contains('4321')));
      expect(blob, isNot(contains('disk gone')));
      expect(blob, isNot(contains('1234')));
      await backend.close();
    } finally {
      try {
        await backend?.close();
      } catch (_) {}
      for (final s in ['', '-journal', '-wal', '-shm']) {
        final f = s.isEmpty ? file : File('${file.path}$s');
        if (await f.exists()) {
          try {
            await f.delete();
          } catch (_) {}
        }
      }
    }
  });

  test('phone-host failures log no PINs, secrets, or payloads', () async {
    final lines = await _capturePrints(() async {
      late PhoneHostSession h;
      try {
        h = await startPhoneHost();
        const secret = 'aa11bb22cc33dd44ee55ff6600112233';
        // Create a box carrying secrets, then fail against it repeatedly.
        var r = await http.post(Uri.parse('${h.url}/api/sync/link'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'pin': '9876',
              'deviceId': 'd',
              'snapshot': '{"note":"SECRETNOTE-XYZ"}',
              'secret': secret,
              'name': 'A',
              'time': '',
            }));
        expect(r.statusCode, 200);
        final link =
            (jsonDecode(r.body) as Map)['link'] as String;
        for (var i = 0; i < 12; i++) {
          r = await http.get(Uri.parse(
              '${h.url}/api/sync/pull?link=$link&pin=0000&deviceId=d'));
        }
        expect(r.statusCode, 429);
        // Oversized + malformed bodies.
        r = await http.post(Uri.parse('${h.url}/api/sync/push'),
            headers: const {'Content-Type': 'application/json'},
            body: '{"link":"$link","pin":"9876","oops":');
        expect(r.statusCode, 400);
      } finally {
        try { await h.close(); } catch (_) {}
      }
    });
    final blob = lines.join('\n');
    expect(blob, isNot(contains('9876')));
    expect(blob, isNot(contains('aa11bb22cc33dd44ee55ff6600112233')));
    expect(blob, isNot(contains('SECRETNOTE-XYZ')));
    // Useful diagnostics remain: methods, paths, error classes.
    expect(blob, contains('phone-host'));
  });
}
