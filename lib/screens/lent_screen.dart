import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app_dates.dart';
import '../format.dart';
import '../store.dart';
import '../sync/reminders.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import '../widgets/app_card.dart';
import '../widgets/empty_state.dart';
import '../widgets/page.dart';
import '../widgets/segmented_tabs.dart';
import '../widgets/profile_avatar.dart';

/// Lent-money ledger: who owes you, partial repayments, settled history.
class LentScreen extends StatefulWidget {
  /// Opens Settings from the small avatar in the title row.
  final VoidCallback? onOpenSettings;

  const LentScreen({super.key, this.onOpenSettings});

  @override
  State<LentScreen> createState() => _LentScreenState();
}

class _LentScreenState extends State<LentScreen> {
  String _dir = 'lent'; // lent | borrowed
  String _filter = 'pending'; // pending | settled | all
  final Set<String> _expanded = {};

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ExpenseStore>();
    final colors = AppColors.of(context);
    final hPad = math.max(
      Spacing.screen,
      (MediaQuery.sizeOf(context).width - kPageMaxWidth) / 2,
    );
    final loans = store.loans.where((l) {
      if ((l.isBorrowed ? 'borrowed' : 'lent') != _dir) return false;
      if (_filter == 'pending') return !l.settled;
      if (_filter == 'settled') return l.settled;
      return true;
    }).toList();

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: pageGutter(context)),
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(hPad, Spacing.sm, hPad, 0),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Lent',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.largeTitle.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Money lent and borrowed',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.caption.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                SettingsAvatarButton(
                  name: store.userName,
                  onTap: widget.onOpenSettings,
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(hPad, Spacing.sm, hPad, 0),
            child: AppCard.group(
              children: [
                _summaryRow(
                  context,
                  store,
                  colors,
                  icon: Icons.handshake_outlined,
                  label: 'To receive',
                  value: store.pendingLoansTotal,
                  borrowed: false,
                ),
                _summaryRow(
                  context,
                  store,
                  colors,
                  icon: Icons.outbox_outlined,
                  label: 'To return',
                  value: store.pendingBorrowedTotal,
                  borrowed: true,
                ),
              ],
            ),
          ),
          if (!store.oneHanded) _toggles(colors, hPad),
          Expanded(
            child: loans.isEmpty
                ? Padding(
                    padding: EdgeInsets.fromLTRB(
                      hPad,
                      Spacing.lg,
                      hPad,
                      Spacing.lg,
                    ),
                    child: AppCard(
                      child: EmptyState(
                        icon: Icons.handshake_outlined,
                        message: _dir == 'lent'
                            ? 'No lent money here yet.'
                            : 'No borrowed money here yet.',
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: EdgeInsets.only(
                      bottom: tabScrollBottomPadding(context),
                    ),
                    itemCount: loans.length,
                    itemBuilder: (ctx, i) =>
                        _loanTile(context, store, loans[i]),
                  ),
          ),
          if (store.oneHanded)
            Padding(
              padding: EdgeInsets.fromLTRB(
                hPad,
                Spacing.sm,
                hPad,
                tabScrollBottomPadding(context) + Spacing.sm,
              ),
              child: _toggles(colors, 0),
            ),
        ],
      ),
    );
  }

  Widget _toggles(AppColors colors, double hPad) {
    return Padding(
      padding: EdgeInsets.fromLTRB(hPad, Spacing.md, hPad, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedTabs(
            labels: const ['Lent', 'Borrowed'],
            selectedIndex: _dir == 'lent' ? 0 : 1,
            onChanged: (i) => setState(() => _dir = i == 0 ? 'lent' : 'borrowed'),
          ),
          const SizedBox(height: Spacing.sm),
          SegmentedTabs(
            labels: const ['Pending', 'Settled', 'All'],
            selectedIndex: const ['pending', 'settled', 'all'].indexOf(_filter),
            onChanged: (i) => setState(
              () => _filter = const ['pending', 'settled', 'all'][i],
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(
    BuildContext context,
    ExpenseStore store,
    AppColors colors, {
    required IconData icon,
    required String label,
    required double value,
    required bool borrowed,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Spacing.lg,
        Spacing.md,
        Spacing.md,
        Spacing.md,
      ),
      child: Row(
        children: [
          Container(
            width: Sizes.iconTile,
            height: Sizes.iconTile,
            decoration: BoxDecoration(
              color: colors.accent.withValues(alpha: 0.12),
              borderRadius: Radii.iconRadius,
            ),
            child: Icon(icon, size: Sizes.iconGlyph, color: colors.accent),
          ),
          const SizedBox(width: Spacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppType.caption.copyWith(color: colors.textSecondary),
                ),
                const SizedBox(height: 2),
                Text(
                  money(value),
                  style: AppType.statValue.copyWith(
                    fontSize: 20,
                    color: colors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: Spacing.sm),
          SizedBox(
            width: 120,
            child: FilledButton(
              onPressed: () =>
                  _personDialog(context, store, borrowed: borrowed),
              child: Text(borrowed ? 'Borrowed' : 'Lent'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _loanTile(BuildContext context, ExpenseStore store, Loan l) {
    final colors = AppColors.of(context);
    final open = _expanded.contains(l.id);
    final ratio = l.totalLent > 0
        ? ((l.totalLent - l.pending) / l.totalLent).clamp(0.0, 1.0)
        : 0.0;
    final statusColor = l.settled ? colors.income : colors.expense;
    return AppCard(
      key: ValueKey('loan-${l.id}'),
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            key: Key('loan-header-${l.id}'),
            onTap: () => setState(() {
              if (open) {
                _expanded.remove(l.id);
              } else {
                _expanded.add(l.id);
              }
            }),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                Spacing.lg,
                Spacing.md,
                Spacing.lg,
                Spacing.md,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      ProfileAvatar(name: l.person, size: 40),
                      const SizedBox(width: Spacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l.person,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppType.title.copyWith(
                                color: colors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${l.isBorrowed ? 'Borrowed' : 'Lent'} '
                              '${money(l.totalLent)} · '
                              '${dayStr(DateTime.fromMillisecondsSinceEpoch(l.dateLent))}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppType.caption.copyWith(
                                color: colors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: Spacing.sm),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            l.settled ? 'Settled' : money(l.pending),
                            style: AppType.amount.copyWith(color: statusColor),
                          ),
                          const SizedBox(height: 2),
                          Icon(
                            open ? Icons.expand_less : Icons.expand_more,
                            size: 18,
                            color: colors.textSecondary,
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: Spacing.sm),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: ratio,
                      minHeight: 4,
                      backgroundColor: colors.track,
                      color: l.settled ? colors.income : colors.accent,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: Motion.of(context, Motion.base),
            curve: Motion.ease,
            alignment: Alignment.topCenter,
            child: open
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Divider(height: 1, color: colors.hairline),
                      if (l.note.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                            Spacing.lg,
                            Spacing.md,
                            Spacing.lg,
                            0,
                          ),
                          child: Text(
                            'Note: ${l.note}',
                            style: AppType.body.copyWith(
                              fontSize: 14,
                              color: colors.textSecondary,
                            ),
                          ),
                        ),
                      // Principal first: the trail reads top-down.
                      _loanLine(
                        colors,
                        icon: l.isBorrowed
                            ? Icons.arrow_downward
                            : Icons.arrow_upward,
                        label: '${l.isBorrowed ? 'Borrowed' : 'Lent'} '
                            '${money(l.lent)}',
                        detail: dayStr(
                          DateTime.fromMillisecondsSinceEpoch(l.dateLent),
                        ),
                      ),
                      for (final r in l.repayments)
                        _loanLine(
                          colors,
                          icon: Icons.replay,
                          label: '${l.isBorrowed ? 'Paid back' : 'Returned'} '
                              '${money(r.amount)}',
                          detail:
                              '${dayStr(DateTime.fromMillisecondsSinceEpoch(r.date))}${r.note.isEmpty ? '' : ' - ${r.note}'}',
                        ),
                      for (final t in l.topups)
                        _loanLine(
                          colors,
                          icon: Icons.add_circle_outline,
                          label: '${l.isBorrowed ? 'Borrowed more' : 'Lent more'} '
                              '${money(t.amount)}',
                          detail:
                              '${dayStr(DateTime.fromMillisecondsSinceEpoch(t.date))}${t.note.isEmpty ? '' : ' - ${t.note}'}',
                        ),
                      ListTile(
                        dense: true,
                        leading: Icon(
                          Icons.notifications_outlined,
                          size: 18,
                          color: colors.textSecondary,
                        ),
                        title: Text(
                          l.remindAt <= 0
                              ? 'No reminder'
                              : 'Once · ${_remindLabel(l.remindAt)}',
                          style: AppType.body.copyWith(fontSize: 14),
                        ),
                        trailing: TextButton(
                          onPressed: () => _remindDialog(context, store, l),
                          child: const Text('Change'),
                        ),
                      ),
                      OverflowBar(
                        children: [
                          TextButton.icon(
                            onPressed: () => _topupDialog(context, store, l),
                            icon: const Icon(Icons.add),
                            label: Text(
                              l.isBorrowed ? 'Borrow more' : 'Lend more',
                            ),
                          ),
                          if (!l.settled)
                            TextButton.icon(
                              onPressed: () =>
                                  _repaymentDialog(context, store, l),
                              icon: const Icon(Icons.replay),
                              label: Text(
                                l.isBorrowed ? 'Paid back' : 'Repayment',
                              ),
                            ),
                          TextButton.icon(
                            onPressed: () => store.deleteLoan(l.id),
                            icon: Icon(
                              Icons.delete_outline,
                              color: colors.expense,
                            ),
                            label: Text(
                              'Delete',
                              style: TextStyle(color: colors.expense),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: Spacing.sm),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _loanLine(
    AppColors colors, {
    required IconData icon,
    required String label,
    required String detail,
  }) {
    return ListTile(
      dense: true,
      leading: Icon(icon, size: 18, color: colors.textSecondary),
      title: Text(label, style: AppType.body.copyWith(fontSize: 14)),
      subtitle: Text(
        detail,
        style: AppType.caption.copyWith(
          fontSize: 12,
          color: colors.textSecondary,
        ),
      ),
    );
  }

  Future<void> _personDialog(
    BuildContext context,
    ExpenseStore store, {
    required bool borrowed,
  }) async {
    final person = TextEditingController();
    final amount = TextEditingController();
    final note = TextEditingController();
    DateTime date = DateTime.now();
    final people = <String>{for (final l in store.loans) l.person.trim()}
      ..remove('');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(borrowed ? 'Borrowed money from...' : 'Lent money to...'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Autocomplete<String>(
                optionsBuilder: (value) {
                  final q = value.text.trim().toLowerCase();
                  final names = people.toList()..sort();
                  if (q.isEmpty) return names;
                  return names.where((n) => n.toLowerCase().contains(q));
                },
                displayStringForOption: (o) => o,
                onSelected: (o) => person.text = o,
                fieldViewBuilder: (ctx, ctrl, focus, onSubmit) {
                  return TextField(
                    controller: ctrl,
                    focusNode: focus,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Person name',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) => person.text = v,
                  );
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: amount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => FocusScope.of(ctx).nextFocus(),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                decoration: InputDecoration(
                  labelText: 'Amount (${store.currencySymbol})',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: note,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => Navigator.of(ctx).pop(true),
                decoration: const InputDecoration(
                  labelText: 'Note (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  final p = await showAppDatePicker(
                    context: ctx,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                    initialDate: date,
                  );
                  if (p != null) setD(() => date = p);
                },
                icon: const Icon(Icons.calendar_today),
                label: Text(dayStr(date)),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    final v = parseAmount(amount.text);
    if (ok == true && person.text.trim().isNotEmpty && v != null) {
      if (borrowed) {
        await store.addBorrow(
          person: person.text.trim(),
          amount: v,
          date: date,
          note: note.text.trim(),
        );
      } else {
        await store.addLoan(
          person: person.text.trim(),
          amount: v,
          date: date,
          note: note.text.trim(),
        );
      }
    } else if (ok == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Need a name and a valid amount')),
      );
    }
  }

  Future<void> _topupDialog(
    BuildContext context,
    ExpenseStore store,
    Loan l,
  ) async {
    final amount = TextEditingController();
    final note = TextEditingController();
    DateTime date = DateTime.now();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(
            l.isBorrowed
                ? 'Borrowed more from ${l.person}'
                : 'Lent more to ${l.person}',
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Still pending: ${money(l.pending)}'),
              const SizedBox(height: 12),
              TextField(
                controller: amount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => FocusScope.of(ctx).nextFocus(),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                decoration: InputDecoration(
                  labelText: 'Amount (${store.currencySymbol})',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: note,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => Navigator.of(ctx).pop(true),
                decoration: const InputDecoration(
                  labelText: 'Note (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  final p = await showAppDatePicker(
                    context: ctx,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                    initialDate: date,
                  );
                  if (p != null) setD(() => date = p);
                },
                icon: const Icon(Icons.calendar_today),
                label: Text(dayStr(date)),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    final v = parseAmount(amount.text);
    if (ok == true && v != null) {
      await store.lendMore(l.id, v, date, note.text.trim());
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lent ${money(v)} more to ${l.person}')),
        );
      }
    } else if (ok == true && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Enter an amount > 0')));
    }
  }

  /// One-time nudge: pick a day (and time) to be reminded once.
  /// Ask for lent money, return borrowed money.
  Future<void> _remindDialog(
    BuildContext context,
    ExpenseStore store,
    Loan l,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final asking = !l.isBorrowed;
    DateTime? picked = l.remindAt > 0
        ? DateTime.fromMillisecondsSinceEpoch(l.remindAt)
        : null;
    var enabled = picked != null;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(
            asking
                ? 'Remind me to ask ${l.person}'
                : 'Remind me to return to ${l.person}',
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Remind once'),
                value: enabled,
                onChanged: (v) async {
                  if (!v) {
                    setD(() => enabled = false);
                    return;
                  }
                  final now = DateTime.now();
                  final d = await showAppDatePicker(
                    context: ctx,
                    firstDate: now,
                    lastDate: now.add(const Duration(days: 365)),
                    initialDate: picked ?? now.add(const Duration(days: 1)),
                  );
                  if (d == null) return;
                  if (!ctx.mounted) return;
                  final t = await showTimePicker(
                    context: ctx,
                    initialTime: picked == null
                        ? const TimeOfDay(hour: 9, minute: 0)
                        : TimeOfDay.fromDateTime(picked!),
                  );
                  if (t == null) return;
                  setD(() {
                    enabled = true;
                    picked = DateTime(d.year, d.month, d.day, t.hour, t.minute);
                  });
                },
              ),
              if (enabled && picked != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Once · ${_remindLabel(picked!.millisecondsSinceEpoch)}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              Text(
                asking
                    ? 'Nudges you once to ask ${l.person} for ${money(l.pending)}.'
                    : 'Nudges you once to return ${money(l.pending)} to ${l.person}.',
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      await store.setReminderAt(l.id, enabled ? picked : null);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            !enabled || picked == null
                ? 'Reminder off.'
                : 'Will remind once · ${_remindLabel(picked!.millisecondsSinceEpoch)}',
          ),
        ),
      );
      if (enabled && picked != null) {
        await _maybePromptExactAlarms(messenger);
      }
    }
  }

  /// In-context exact-alarm explanation, shown once when a reminder is
  /// saved without the system "Alarms & reminders" access (not
  /// pre-granted on Android 14+). The reminder is still scheduled via
  /// the inexact fallback, so nothing is lost if the user declines.
  Future<void> _maybePromptExactAlarms(ScaffoldMessengerState messenger) async {
    if (await Reminders.canUseExactAlarms()) return;
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: const Text(
          'For on-time reminders, allow “Alarms & reminders” for Dhadda in system settings. Without it, reminders may arrive late.',
        ),
        action: SnackBarAction(
          label: 'Open settings',
          onPressed: () => Reminders.requestExactAlarmAccess(),
        ),
        duration: const Duration(seconds: 8),
      ),
    );
  }

  String _remindLabel(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${dayStr(d)} · ${TimeOfDay.fromDateTime(d).format(context)}';
  }

  Future<void> _repaymentDialog(
    BuildContext context,
    ExpenseStore store,
    Loan l,
  ) async {
    final amount = TextEditingController(text: l.pending.toStringAsFixed(0));
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          l.isBorrowed
              ? 'You returned to ${l.person}...'
              : '${l.person} returned...',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              textInputAction: TextInputAction.next,
              onSubmitted: (_) => FocusScope.of(ctx).nextFocus(),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              decoration: InputDecoration(
                labelText:
                    "Amount (${store.currencySymbol}, pending ${money(l.pending)})",
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: note,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => Navigator.of(ctx).pop(true),
              decoration: const InputDecoration(
                labelText: 'Note (optional)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    final v = parseAmount(amount.text);
    if (ok == true && v != null) {
      await store.addRepayment(l.id, v, DateTime.now(), note.text.trim());
      if (context.mounted && v >= l.pending - 0.005) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('${l.person} settled up!')));
      }
    }
  }
}
