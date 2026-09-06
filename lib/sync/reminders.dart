import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../format.dart';
import '../store.dart';

/// One-time OS reminders for lent / borrowed entries.
/// Everything is best-effort: no throw ever escapes,
/// so a notification failure can never break expenses or sync.
class Reminders {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static const _channelId = 'loan_reminders';
  static const _channelName = 'Loan reminders';

  /// Stable notification id per entry (Android needs a positive int).
  static int idFor(String loanId) {
    final id = loanId.hashCode & 0x7fffffff;
    return id == 0 ? 1 : id;
  }

  static Future<void> _ensure() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    try {
      final zone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(zone.identifier));
    } catch (_) {}
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _plugin.initialize(settings: settings);
    _ready = true;
  }

  static AndroidNotificationDetails _details() =>
      const AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription:
            'Nudges to ask for lent money or return borrowed money',
        importance: Importance.max,
        priority: Priority.high,
      );

  static String _title(Loan l) =>
      l.isBorrowed ? 'Return money' : 'Ask for money';
  static String _body(ExpenseStore store, Loan l) {
    final amount = money(l.pending);
    return l.isBorrowed
        ? 'You still owe ${l.person} $amount - time to return it.'
        : '${l.person} still owes you $amount - time to ask.';
  }

  static Future<void> _scheduleOne(
      ExpenseStore store, Loan l) async {
    if (l.settled || l.remindAt <= 0) {
      await _plugin.cancel(id: idFor(l.id));
      return;
    }
    final when =
        tz.TZDateTime.fromMillisecondsSinceEpoch(tz.local, l.remindAt);
    if (!when.isAfter(tz.TZDateTime.now(tz.local))) {
      // Moment already passed: nothing to fire, clear any stale entry.
      await _plugin.cancel(id: idFor(l.id));
      return;
    }
    await _plugin.zonedSchedule(
      id: idFor(l.id),
      title: _title(l),
      body: _body(store, l),
      scheduledDate: when,
      androidScheduleMode:
          AndroidScheduleMode.inexactAllowWhileIdle,
      notificationDetails:
          NotificationDetails(android: _details()),
    );
  }

  /// Rebuilds every reminder from current data: call on boot, on
  /// resume, and after any loan change (wired via store.onLoansChanged).
  /// Stale entries (deleted/settled/disabled) are cancelled first.
  static Future<void> refresh(ExpenseStore store) async {
    if (kIsWeb) return;
    try {
      await _ensure();
      try {
        await _plugin
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.requestNotificationsPermission();
      } catch (_) {}
      await _plugin.cancelAll();
      for (final l in store.loans) {
        try {
          await _scheduleOne(store, l);
        } catch (_) {}
      }
    } catch (_) {}
  }
}