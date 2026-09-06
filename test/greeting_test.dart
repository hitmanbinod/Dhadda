import 'package:expense/format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('daypart boundaries', () {
    expect(daypartFor(DateTime(2026, 9, 4, 0)), 'morning');
    expect(daypartFor(DateTime(2026, 9, 4, 11, 59)), 'morning');
    expect(daypartFor(DateTime(2026, 9, 4, 12)), 'afternoon');
    expect(daypartFor(DateTime(2026, 9, 4, 16, 59)), 'afternoon');
    expect(daypartFor(DateTime(2026, 9, 4, 17)), 'evening');
    expect(daypartFor(DateTime(2026, 9, 4, 23)), 'evening');
  });

  test('home greeting uses name when present', () {
    expect(homeGreeting('', DateTime(2026, 9, 4, 9)), 'Good morning');
    expect(homeGreeting('Ram', DateTime(2026, 9, 4, 9)),
        'Good morning, Ram');
    expect(homeGreeting('  Ram  ', DateTime(2026, 9, 4, 20)),
        'Good evening, Ram');
    expect(homeGreeting('Ram', DateTime(2026, 9, 4, 14)),
        'Good afternoon, Ram');
  });
}