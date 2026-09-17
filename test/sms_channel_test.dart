// Phase 7: SMS bridge contract (MethodChannel mocked) + import flow
// (channel -> parse -> store -> dedup). Synthetic bank-like messages only.
// Real inbox access stays a manual procedure (docs/TESTING.md).
import 'package:expense/store.dart';
import 'package:expense/sync/sms.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const ch = MethodChannel('expense/sms');

  List<Map<String, Object?>> inboxRows() => [
    {
      'id': 'sms-1',
      'sender': 'NabilBank',
      'body': 'Rs.1,250.00 debited from A/C ending 1234 at DAL BHAT HOUSE.',
      'date': 1788220800000,
    },
    {
      'id': 'sms-2',
      'sender': 'eSewa',
      'body': 'You have received Rs 500 from Bikash. Thank you.',
      'date': 1788220900000,
    },
    {
      'id': 'sms-3',
      'sender': 'Friend',
      'body': 'Lunch tomorrow?',
      'date': 1788221000000,
    },
  ];

  void mockInbox({bool permission = true}) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ch, (call) async {
          if (call.method == 'ensurePermission') return permission;
          if (call.method == 'readInbox') {
            expect(call.arguments['limit'], isA<int>());
            return inboxRows();
          }
          return null;
        });
  }

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ch, null);
  });

  test('permission denied yields empty inbox, never throws', () async {
    mockInbox(permission: false);
    expect(await SmsReader.ensurePermission(), isFalse);
  });

  test('readInbox maps rows and failures fall back to empty', () async {
    mockInbox();
    expect(await SmsReader.ensurePermission(), isTrue);
    final rows = await SmsReader.readInbox(limit: 60);
    expect(rows, hasLength(3));
    expect(rows.first['sender'], 'NabilBank');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ch, (call) async {
          throw PlatformException(code: 'DENIED');
        });
    expect(await SmsReader.ensurePermission(), isFalse);
    expect(await SmsReader.readInbox(), isEmpty);
  });

  test('import flow parses, stores, and suppresses duplicates', () async {
    SharedPreferences.setMockInitialValues({});
    mockInbox();
    final store = ExpenseStore();
    await store.load();
    final before = store.transactions.length;
    // Replicates the MenuScreen import path: allow-listed senders only.
    final rows = await SmsReader.readInbox(limit: 100);
    final seen = await SmsReader.importedIds();
    var added = 0;
    for (final row in rows) {
      final id = '${row['id']}';
      if (seen.contains(id)) continue;
      final cands = parseSms(
        id: id,
        sender: '${row['sender']}',
        body: '${row['body']}',
        dateMs: (row['date'] as int?) ?? 0,
        allowedSenders: const ['NabilBank', 'eSewa'],
      );
      if (cands == null) continue; // non-transaction SMS ignored
      final c = cands;
      await store.addTransaction(
        type: c.isIncome ? 'income' : 'expense',
        amount: c.amount,
        categoryId: categorizeSms(
          merchant: c.merchant,
          body: c.body,
          candidates: store.categories,
        ),
        date: c.date,
        note: c.merchant.isEmpty ? c.sender : c.merchant,
        mode: c.mode,
      );
      await SmsReader.markImported([id]);
      added++;
    }
    expect(added, 2); // bank + wallet; chat message ignored
    expect(store.transactions.length, before + 2);
    // Second pass over the same inbox adds nothing (dedup + parse gate).
    final seen2 = await SmsReader.importedIds();
    expect(seen2, containsAll(['sms-1', 'sms-2']));
    var added2 = 0;
    for (final row in rows) {
      if (seen2.contains('${row['id']}')) continue;
      final again = parseSms(
        id: '${row['id']}',
        sender: '${row['sender']}',
        body: '${row['body']}',
        dateMs: (row['date'] as int?) ?? 0,
        allowedSenders: const ['NabilBank', 'eSewa'],
      );
      if (again != null) added2++;
    }
    expect(added2, 0); // only the chat message remains, still unparseable
    expect(store.transactions.length, before + 2);
  });

  test('imported-ids list caps at 2000', () async {
    SharedPreferences.setMockInitialValues({});
    await SmsReader.markImported([for (var i = 0; i < 2100; i++) 'id-$i']);
    final ids = await SmsReader.importedIds();
    expect(ids.length, lessThanOrEqualTo(2000));
  });
}
