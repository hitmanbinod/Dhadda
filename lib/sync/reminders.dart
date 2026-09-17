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

  /// Notification ids currently believed to be scheduled (per process).
  /// Lets refresh() cancel only stale entries instead of cancelAll(),
  /// so a mid-refresh failure can no longer wipe every reminder.
  static final Set<int> _active = <int>{};

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

  /// Whether the OS currently grants exact-alarm access. Never throws;
  /// false means scheduling falls back to inexact (may arrive late).
  /// Android 14+ does not pre-grant this on fresh installs: the user
  /// must enable "Alarms & reminders" special access for Dhadda.
  static Future<bool> canUseExactAlarms() async {
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      return await android?.canScheduleExactNotifications() ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Opens the system "Alarms & reminders" access screen so the user can
  /// grant exact-alarm access in context. Never throws.
  static Future<void> requestExactAlarmAccess() async {
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestExactAlarmsPermission();
    } catch (_) {}
  }

  static String _title(Loan l) =>
      l.isBorrowed ? 'Return money' : 'Ask for money';
  static String _body(ExpenseStore store, Loan l) {
    final amount = money(l.pending);
    return l.isBorrowed
        ? 'You still owe ${l.person} $amount - time to return it.'
        : '${l.person} still owes you $amount - time to ask.';
  }

  static Future<void> _scheduleOne(ExpenseStore store, Loan l) async {
    if (l.settled || l.remindAt <= 0) {
      await _plugin.cancel(id: idFor(l.id));
      return;
    }
    final when = tz.TZDateTime.fromMillisecondsSinceEpoch(tz.local, l.remindAt);
    if (!when.isAfter(tz.TZDateTime.now(tz.local))) {
      // Moment already passed: nothing to fire, clear any stale entry.
      await _plugin.cancel(id: idFor(l.id));
      return;
    }
    Future<void> schedule(AndroidScheduleMode mode) => _plugin.zonedSchedule(
      id: idFor(l.id),
      title: _title(l),
      body: _body(store, l),
      scheduledDate: when,
      androidScheduleMode: mode,
      notificationDetails: NotificationDetails(android: _details()),
    );
    // Exact alarms for explicit user reminders; inexact fallback keeps
    // the reminder (possibly late) instead of losing it when access is
    // denied, unavailable, or revoked between check and schedule.
    final exact = await canUseExactAlarms();
    try {
      await schedule(
        exact
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } catch (_) {
      if (exact) {
        try {
          await schedule(AndroidScheduleMode.inexactAllowWhileIdle);
        } catch (_) {}
      }
    }
  }

  /// Rebuilds every reminder from current data: call on boot, on
  /// resume, and after any loan change (wired via store.onLoansChanged).
  /// Diff-based: only stale ids (deleted/settled/disabled/past) are
  /// cancelled, each loan is rescheduled independently, and the active
  /// set is only updated with what actually scheduled — a failure part
  /// way through leaves every other reminder untouched.
  static Future<void> refresh(ExpenseStore store) async {
    if (kIsWeb) return;
    try {
      await _ensure();
      try {
        await _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.requestNotificationsPermission();
      } catch (_) {}
      final wanted = <int>{};
      final scheduled = <int>{};
      for (final l in store.loans) {
        final id = idFor(l.id);
        final active = !l.settled && l.remindAt > 0;
        if (active) {
          final when =
              tz.TZDateTime.fromMillisecondsSinceEpoch(tz.local, l.remindAt);
          if (when.isAfter(tz.TZDateTime.now(tz.local))) wanted.add(id);
        }
        try {
          await _scheduleOne(store, l);
          if (wanted.contains(id)) scheduled.add(id);
        } catch (_) {
          // Keep the old id in _active (if it was there) so a later
          // refresh still knows the OS may hold this reminder.
        }
      }
      // Cancel only ids no longer wanted — never a blanket cancelAll.
      for (final id in _active.difference(wanted)) {
        try {
          await _plugin.cancel(id: id);
        } catch (_) {}
      }
      _active
        ..clear()
        ..addAll(scheduled);
    } catch (_) {}
  }
}
