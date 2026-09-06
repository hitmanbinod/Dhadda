import 'package:expense/models.dart';
import 'package:expense/sync/sms_parse.dart';
import 'package:flutter_test/flutter_test.dart';

SmsCandidate? parse(String sender, String body) => parseSms(
    id: '1', sender: sender, body: body, dateMs: 1725400000000);

void main() {
  test('Nabil-style debit', () {
    final c = parse('NABIL',
        'Rs.1,250.00 debited from A/C XX1234 at BHATBHATENI on 03-Sep-26. Avl bal Rs.45,000');
    expect(c, isNotNull);
    expect(c!.amount, 1250);
    expect(c.isIncome, isFalse);
    expect(c.mode, 'bank');
    expect(c.merchant.toUpperCase(), contains('BHATBHATENI'));
  });

  test('eSewa receive is income + ewallet', () {
    final c = parse(
        'eSewa', 'You have received NPR 2,000.00 from 98XXXXXXXX. Ref: 123.');
    expect(c, isNotNull);
    expect(c!.amount, 2000);
    expect(c.isIncome, isTrue);
    expect(c.mode, 'ewallet');
  });

  test('Khalti payment is expense', () {
    final c = parse('Khalti',
        'Payment of Rs 350 successful to DARAZ. TxnID X. Thank you.');
    expect(c, isNotNull);
    expect(c!.amount, 350);
    expect(c.isIncome, isFalse);
    expect(c.mode, 'ewallet');
  });

  test('NIC Asia credited salary', () {
    final c = parse('NIC-ASIA',
        'Your account has been credited with NPR 85,000.00 towards SALARY.');
    expect(c, isNotNull);
    expect(c!.amount, 85000);
    expect(c.isIncome, isTrue);
  });

  test('ATM withdrawal', () {
    final c = parse('GLOBAL',
        'Rs.10,000 withdrawn from ATM KATHMANDU. Avl Bal 20,000');
    expect(c, isNotNull);
    expect(c!.amount, 10000);
    expect(c.isIncome, isFalse);
  });

  test('non-transaction SMS ignored', () {
    expect(parse('NTC', 'Your balance is Rs.50. Recharge soon.'), isNull);
    expect(parse('Friend', 'Lunch tomorrow?'), isNull);
    expect(parse('BANK', 'OTP is 482910. Do not share.'), isNull);
  });

  test('sender allowlist filters junk', () {
    SmsCandidate? allow(String sender, String body) => parseSms(
        id: '1',
        sender: sender,
        body: body,
        dateMs: 1725400000000,
        allowedSenders: const ['eSewa', 'Nabil']);
    expect(
        allow('eSewa',
            'You have received NPR 500 from 98X.'),
        isNotNull);
    expect(
        allow('NABIL',
            'Rs.500 debited from A/C XX1 at ATM.'),
        isNotNull);
    // Not allow-listed: dropped even if parseable.
    expect(
        allow('PROMO',
            'Rs.500 debited for your recharge.'),
        isNull);
    // Empty list = accept all as before.
    expect(
        parseSms(
            id: '1',
            sender: 'PROMO',
            body: 'Rs.500 debited for recharge.',
            dateMs: 1),
        isNotNull);
  });

  test('auto-categorize maps remarks, custom names win', () {
    final cats = defaultCategories();
    String cat(String merchant, String body) => categorizeSms(
        merchant: merchant, body: body, candidates: cats);
    expect(
        cat('BHATBHATENI', 'Rs.1000 debited at BHATBHATENI'),
        cats
            .firstWhere((c) => c.name == 'Shopping')
            .id);
    expect(cat('', 'Petrol Rs.2000 debited'), 'fuel');
    expect(cat('', 'Salary credited NPR 50000'), 'other');
    expect(cat('Nope', 'nothing matching here Rs.10 debited'),
        'other');
    expect(cat('', ''), 'other');
    expect(categorizeSms(merchant: '', body: '', candidates: []),
        '');
  });
}