import 'package:expense/models.dart';
import 'package:expense/sync/wifi_client.dart';
import 'package:flutter_test/flutter_test.dart';

Snapshot _sample() {
  final cats = defaultCategories();
  return Snapshot(
    version: kSnapshotVersion,
    updatedAt: DateTime.utc(2026, 9, 3, 10).toIso8601String(),
    deviceId: 'dev-a',
    deviceName: 'Phone',
    categories: cats,
    projects: const [],    transactions: [
      Txn(
          id: 't1',
          type: 'expense',
          amount: 250,
          categoryId: 'food',
          date: DateTime.utc(2026, 9, 2).millisecondsSinceEpoch,
          note: 'lunch',
          mode: 'upi'),
      Txn(
          id: 't2',
          type: 'income',
          amount: 50000,
          categoryId: 'other',
          date: DateTime.utc(2026, 9, 1).millisecondsSinceEpoch),
    ],
    loans: [
      Loan(
        id: 'l1',
        person: 'Asha',
        lent: 1000,
        dateLent: DateTime.utc(2026, 8, 20).millisecondsSinceEpoch,
        repayments: [
          Repayment(
              id: 'r1',
              amount: 400,
              date: DateTime.utc(2026, 8, 25).millisecondsSinceEpoch),
        ],
      ),
    ],
  );
}

void main() {
  test('snapshot JSON round-trips without loss', () {
    final s = _sample();
    final back = Snapshot.decode(s.encode());
    expect(back.transactions.length, 2);
    expect(back.loans.length, 1);
    expect(back.loans.first.pending, 600);
    expect(back.loans.first.settled, isFalse);
    expect(back.categories.length, defaultCategories().length);
    expect(back.updatedAtTime.isAfter(DateTime.utc(2026, 1, 1)), isTrue);
  });

  test('corrupt snapshot throws instead of half-loading', () {
    expect(() => Snapshot.decode('not json'), throwsA(anything));
    expect(() => Snapshot.decode('{"version":1}'), returnsNormally);
  });

  test('QR payload builds and parses', () {
    const url = 'http://192.168.1.5:51234';
    const pin = '123456';
    final payload = WifiClient.buildQrPayload(url, pin);
    final t = WifiClient.parseQrPayload(payload);
    expect(t, isNotNull);
    expect(t!.url, url);
    expect(t.pin, pin);
    expect(WifiClient.parseQrPayload('hello'), isNull);
    expect(WifiClient.parseQrPayload('EXPENSESYNC::onlyone'), isNull);
  });

  test('loan top-ups raise pending; repayments lower it', () {
    final loan = Loan(
      id: 'l9',
      person: 'Test',
      lent: 1000,
      dateLent: DateTime.utc(2026, 8, 1).millisecondsSinceEpoch,
      repayments: [
        Repayment(
            id: 'r1',
            amount: 400,
            date: DateTime.utc(2026, 8, 25).millisecondsSinceEpoch),
      ],
      topups: [
        Topup(
            id: 't1',
            amount: 600,
            date: DateTime.utc(2026, 9, 1).millisecondsSinceEpoch),
      ],
    );
    expect(loan.totalLent, 1600);
    expect(loan.pending, 1200);
    expect(loan.settled, isFalse);

    // Round-trips through JSON (sync format).
    final back = Loan.fromJson(loan.toJson());
    expect(back.topups.length, 1);
    expect(back.pending, 1200);

    // Old snapshots without 'topups' still load.
    final legacy = Loan.fromJson({
      'id': 'l0',
      'person': 'Old',
      'lent': 500,
      'dateLent': 0,
    });
    expect(legacy.topups, isEmpty);
    expect(legacy.pending, 500);
  });
}