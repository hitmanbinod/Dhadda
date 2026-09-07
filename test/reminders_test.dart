// Phase 7: reminder scheduling integration (store -> Reminders ->
// notification plugin channel, mocked) + timezone data the app relies on.
// Synthetic loans only. Actual OS delivery stays a manual procedure
// (documented in docs/TESTING.md).
import 'package:expense/store.dart';
import 'package:expense/sync/reminders.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Fake Android notification backend: records scheduling decisions instead
/// of touching the OS. Unit tests have no plugin registrant, and the real
/// method-channel implementation can't run here.
class FakeAndroidNotifications extends AndroidFlutterLocalNotificationsPlugin
    with MockPlatformInterfaceMixin {
  final scheduled = <Map<String, Object?>>[];
  final cancelledIds = <int>[];
  var cancelAllCount = 0;

  void reset() {
    scheduled.clear();
    cancelledIds.clear();
    cancelAllCount = 0;
  }

  @override
  Future<void> zonedSchedule({
    required int id,
    String? title,
    String? body,
    required tz.TZDateTime scheduledDate,
    String? payload,
    DateTimeComponents? matchDateTimeComponents,
    AndroidNotificationDetails? notificationDetails,
    AndroidScheduleMode scheduleMode = AndroidScheduleMode.exact,
  }) async {
    scheduled.add({
      'id': id,
      'title': title,
      'body': body,
      'scheduledDate': scheduledDate,
    });
  }

  @override
  Future<void> cancel({required int id, String? tag}) async {
    cancelledIds.add(id);
  }

  @override
  Future<void> cancelAll() async {
    cancelAllCount++;
  }

  @override
  Future<bool?> requestNotificationsPermission() async => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final fake = FakeAndroidNotifications();
  FlutterLocalNotificationsPlatform.instance = fake;

  // The facade dispatches on defaultTargetPlatform: force the Android
  // branch (host is Windows) so calls reach the mocked channel.
  debugDefaultTargetPlatformOverride = TargetPlatform.android;
  tearDownAll(() => debugDefaultTargetPlatformOverride = null);

  const pluginCh = MethodChannel('dexterous.com/flutter/local_notifications');
  const tzCh = MethodChannel('flutter_timezone');

  // The facade's initialize() still goes through the base method channel
  // (unit tests have no registrant for it); the tz channel mock makes
  // timezone resolution deterministic.
  setUp(() {
    fake.reset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(tzCh, (call) async {
          if (call.method == 'getLocalTimezone') return 'UTC';
          return null;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pluginCh, (call) async {
          // initialize() requires a real bool (null throws inside the
          // facade and would silently cancel the whole refresh).
          if (call.method == 'initialize') return true;
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pluginCh, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(tzCh, null);
  });

  Future<ExpenseStore> loanStore() async {
    SharedPreferences.setMockInitialValues({});
    final s = ExpenseStore();
    await s.load();
    return s;
  }

  List<Map<String, Object?>> scheduled() => fake.scheduled;

  test('idFor is stable and a valid positive Android id', () {
    expect(Reminders.idFor('abc'), Reminders.idFor('abc'));
    expect(Reminders.idFor('abc'), greaterThan(0));
    expect(Reminders.idFor(''), greaterThan(0));
  });

  test('future reminder schedules with person + id', () async {
    final s = await loanStore();
    await s.addLoan(person: 'Asha', amount: 5000, date: DateTime(2026, 1, 1));
    final id = s.loans.single.id;
    await s.setReminderAt(id, DateTime.now().add(const Duration(days: 2)));
    await Reminders.refresh(s);
    final zoned = scheduled();
    expect(zoned, hasLength(1));
    expect(zoned.single['id'], Reminders.idFor(id));
    expect(zoned.single['title'], 'Ask for money');
    expect('${zoned.single['body']}', contains('Asha'));
  });

  test('borrowed reminder uses return wording', () async {
    final s = await loanStore();
    await s.addBorrow(
      person: 'Bikash',
      amount: 3000,
      date: DateTime(2026, 1, 1),
    );
    await s.setReminderAt(
      s.loans.single.id,
      DateTime.now().add(const Duration(days: 2)),
    );
    await Reminders.refresh(s);
    expect(scheduled().single['title'], 'Return money');
  });

  test('past, settled, and disabled reminders cancel instead', () async {
    final s = await loanStore();
    await s.addLoan(person: 'Past', amount: 100, date: DateTime(2026, 1, 1));
    final pastId = s.loans.single.id;
    await s.setReminderAt(
      pastId,
      DateTime.now().subtract(const Duration(days: 1)),
    );
    await s.addLoan(person: 'Settled', amount: 100, date: DateTime(2026, 1, 1));
    final settled = s.loans.last;
    await s.addRepayment(settled.id, 100, DateTime(2026, 1, 2), 'done');
    await Reminders.refresh(s);
    // Nothing scheduled; stale entries cancelled (cancelAll first).
    expect(scheduled(), isEmpty);
    expect(fake.cancelAllCount, greaterThan(0));
    expect(
      fake.cancelledIds,
      containsAll([Reminders.idFor(pastId), Reminders.idFor(settled.id)]),
    );
  });

  test('repayment changes the rescheduled amount', () async {
    final s = await loanStore();
    await s.addLoan(person: 'Asha', amount: 5000, date: DateTime(2026, 1, 1));
    final id = s.loans.single.id;
    await s.setReminderAt(id, DateTime.now().add(const Duration(days: 2)));
    await Reminders.refresh(s);
    final first = '${scheduled().single['body']}';
    await s.addRepayment(id, 2000, DateTime(2026, 1, 2), 'part');
    fake.reset();
    await Reminders.refresh(s);
    final second = '${scheduled().single['body']}';
    expect(second == first, isFalse); // pending dropped 5000 -> 3000
    expect(second, contains('Asha'));
  });

  test('plugin failure never escapes refresh', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pluginCh, (call) async {
          throw PlatformException(code: 'DOWN');
        });
    final s = await loanStore();
    await s.addLoan(person: 'A', amount: 1, date: DateTime(2026, 1, 1));
    await Reminders.refresh(s); // must not throw
  });

  test('timezone data: Kathmandu, UTC, and a DST zone', () {
    tzdata.initializeTimeZones();
    int offsetMs(tz.Location loc, int year, int month) => loc
        .timeZone(DateTime.utc(year, month).millisecondsSinceEpoch)
        .offset
        .inMilliseconds;
    final ktm = tz.getLocation('Asia/Kathmandu');
    // Nepal is UTC+5:45 year-round (no DST).
    expect(offsetMs(ktm, 2026, 1), (5 * 3600 + 45 * 60) * 1000);
    expect(offsetMs(ktm, 2026, 7), (5 * 3600 + 45 * 60) * 1000);
    expect(offsetMs(tz.getLocation('Etc/UTC'), 2026, 1), 0);
    final ny = tz.getLocation('America/New_York');
    expect(offsetMs(ny, 2026, 1), -5 * 3600 * 1000); // EST
    expect(offsetMs(ny, 2026, 7), -4 * 3600 * 1000); // EDT
  });
}
