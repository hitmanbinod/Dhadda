import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../format.dart';
import '../store.dart';
import '../sync/reminders.dart';
import '../widgets/page.dart';

/// Lent-money ledger: who owes you, partial repayments, settled history.
class LentScreen extends StatefulWidget {
  const LentScreen({super.key});

  @override
  State<LentScreen> createState() => _LentScreenState();
}

class _LentScreenState extends State<LentScreen> {
  String _dir = 'lent'; // lent | borrowed
  String _filter = 'pending'; // pending | settled | all

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ExpenseStore>();
    final loans = store.loans.where((l) {
      if ((l.isBorrowed ? 'borrowed' : 'lent') != _dir) return false;
      if (_filter == 'pending') return !l.settled;
      if (_filter == 'settled') return l.settled;
      return true;
    }).toList();

    return Padding(
      padding:
          EdgeInsets.symmetric(horizontal: pageGutter(context)),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Card(
            color: Theme.of(context)
                .colorScheme
                .secondaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(Icons.handshake, size: 28),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            const Text('To receive'),
                            Text(money(store.pendingLoansTotal),
                                style: Theme.of(context)
                                    .textTheme
                                    .titleLarge
                                    ?.copyWith(
                                        fontWeight:
                                            FontWeight.bold)),
                          ],
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: () => _personDialog(
                            context, store,
                            borrowed: false),
                        icon: const Icon(Icons.add),
                        label: const Text('Lent'),
                      ),                    ],
                  ),
                  const Divider(height: 24),
                  Row(
                    children: [
                      const Icon(Icons.outbox, size: 28),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            const Text('To return'),
                            Text(
                                money(store
                                    .pendingBorrowedTotal),
                                style: Theme.of(context)
                                    .textTheme
                                    .titleLarge
                                    ?.copyWith(
                                        fontWeight:
                                            FontWeight.bold)),
                          ],
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: () => _personDialog(
                            context, store,
                            borrowed: true),
                        icon: const Icon(Icons.add),
                        label: const Text('Borrowed'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                  value: 'lent', label: Text('Lent')),
              ButtonSegment(
                  value: 'borrowed', label: Text('Borrowed')),
            ],
            selected: {_dir},
            onSelectionChanged: (s) =>
                setState(() => _dir = s.first),
          ),
        ),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: 'pending', label: Text('Pending')),
            ButtonSegment(value: 'settled', label: Text('Settled')),
            ButtonSegment(value: 'all', label: Text('All')),
          ],
          selected: {_filter},
          onSelectionChanged: (s) =>
              setState(() => _filter = s.first),
        ),
        Expanded(
          child: loans.isEmpty
              ? const Center(child: Text('Nothing here.'))
              : ListView.builder(
                  itemCount: loans.length,
                  itemBuilder: (ctx, i) =>
                      _loanTile(context, store, loans[i]),
                ),
        ),
      ],
      ),
    );
  }

  Widget _loanTile(BuildContext context, ExpenseStore store, Loan l) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: l.settled
              ? Colors.green.withValues(alpha: 0.15)
              : Colors.orange.withValues(alpha: 0.15),
          child: Icon(
              l.settled ? Icons.check : Icons.person,
              color: l.settled ? Colors.green : Colors.orange),
        ),
        title: Text(l.person,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(
            '${l.isBorrowed ? 'Borrowed' : 'Lent'} ${money(l.totalLent)} total since ${dayStr(DateTime.fromMillisecondsSinceEpoch(l.dateLent))}'),
        trailing: Text(
          l.settled ? 'Settled' : money(l.pending),
          style: TextStyle(
              fontWeight: FontWeight.bold,
              color: l.settled ? Colors.green : Colors.orange),
        ),
        children: [
          if (l.note.isNotEmpty)
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Note: ${l.note}')),
            ),
          // The original amount first, so the full money trail
          // (principal -> top-ups -> repayments) reads top-down.
          ListTile(
            dense: true,
            leading: Icon(
                l.isBorrowed
                    ? Icons.arrow_downward
                    : Icons.arrow_upward,
                size: 18),
            title: Text(
                '${l.isBorrowed ? 'Borrowed' : 'Lent'} ${money(l.lent)}'),
            subtitle: Text(dayStr(
                DateTime.fromMillisecondsSinceEpoch(l.dateLent))),
          ),
          for (final r in l.repayments)
            ListTile(
              dense: true,
              leading: const Icon(Icons.replay, size: 18),
              title: Text(
                  '${l.isBorrowed ? 'Paid back' : 'Returned'} ${money(r.amount)}'),
              subtitle: Text(
                  '${dayStr(DateTime.fromMillisecondsSinceEpoch(r.date))}${r.note.isEmpty ? '' : ' - ${r.note}'}'),
            ),
          for (final t in l.topups)
            ListTile(
              dense: true,
              leading: const Icon(Icons.add_circle_outline,
                  size: 18),
              title: Text(
                  '${l.isBorrowed ? 'Borrowed more' : 'Lent more'} ${money(t.amount)}'),
              subtitle: Text(
                  '${dayStr(DateTime.fromMillisecondsSinceEpoch(t.date))}${t.note.isEmpty ? '' : ' - ${t.note}'}'),
            ),
          ListTile(
            dense: true,
            leading: const Icon(Icons.notifications_outlined,
                size: 18),
            title: Text(l.remindAt <= 0
                ? 'No reminder'
                : 'Once · ${_remindLabel(l.remindAt)}'),
            trailing: TextButton(
              onPressed: () =>
                  _remindDialog(context, store, l),
              child: const Text('Change'),
            ),
          ),
          OverflowBar(
            children: [
              TextButton.icon(
                onPressed: () => _topupDialog(context, store, l),
                icon: const Icon(Icons.add),
                label: Text(
                    l.isBorrowed ? 'Borrow more' : 'Lend more'),
              ),
              if (!l.settled)
                TextButton.icon(
                  onPressed: () =>
                      _repaymentDialog(context, store, l),
                  icon: const Icon(Icons.replay),
                  label: Text(
                      l.isBorrowed ? 'Paid back' : 'Repayment'),
                ),
              TextButton.icon(
                onPressed: () => store.deleteLoan(l.id),
                icon: const Icon(Icons.delete, color: Colors.red),
                label: const Text('Delete',
                    style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Future<void> _personDialog(BuildContext context,
      ExpenseStore store,
      {required bool borrowed}) async {
    final person = TextEditingController();
    final amount = TextEditingController();
    final note = TextEditingController();
    DateTime date = DateTime.now();
    final people = <String>{
      for (final l in store.loans) l.person.trim(),
    }..remove('');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(borrowed
              ? 'Borrowed money from...'
              : 'Lent money to...'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Autocomplete<String>(
                optionsBuilder: (value) {
                  final q = value.text.trim().toLowerCase();
                  final names = people.toList()..sort();
                  if (q.isEmpty) return names;
                  return names.where(
                      (n) => n.toLowerCase().contains(q));
                },
                displayStringForOption: (o) => o,
                onSelected: (o) => person.text = o,
                fieldViewBuilder:
                    (ctx, ctrl, focus, onSubmit) {
                  return TextField(
                    controller: ctrl,
                    focusNode: focus,
                    textCapitalization:
                        TextCapitalization.words,
                    decoration: const InputDecoration(
                        labelText: 'Person name',
                        border: OutlineInputBorder()),
                    onChanged: (v) => person.text = v,
                  );
                },
              ),
              const SizedBox(height: 12),
              TextField(
                  controller: amount,
                  keyboardType:
                      const TextInputType.numberWithOptions(
                          decimal: true),
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) =>
                      FocusScope.of(ctx).nextFocus(),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                        RegExp(r'[0-9.,]')),
                  ],
                  decoration: InputDecoration(
                      labelText: 'Amount (${store.currencySymbol})',
                      border: const OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(
                  controller: note,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) =>
                      Navigator.of(ctx).pop(true),
                  decoration: const InputDecoration(
                      labelText: 'Note (optional)',
                      border: OutlineInputBorder())),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  final p = await showDatePicker(
                      context: ctx,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now()
                          .add(const Duration(days: 365)),
                      initialDate: date);
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
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () =>
                    Navigator.of(ctx).pop(true),
                child: const Text('Save')),
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
            note: note.text.trim());
      } else {
        await store.addLoan(
            person: person.text.trim(),
            amount: v,
            date: date,
            note: note.text.trim());
      }
    } else if (ok == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Need a name and a valid amount')));
    }
  }

  Future<void> _topupDialog(
      BuildContext context, ExpenseStore store, Loan l) async {
    final amount = TextEditingController();
    final note = TextEditingController();
    DateTime date = DateTime.now();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(l.isBorrowed
              ? 'Borrowed more from ${l.person}'
              : 'Lent more to ${l.person}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Still pending: ${money(l.pending)}'),
              const SizedBox(height: 12),
              TextField(
                  controller: amount,
                  keyboardType:
                      const TextInputType.numberWithOptions(
                          decimal: true),
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) =>
                      FocusScope.of(ctx).nextFocus(),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                        RegExp(r'[0-9.,]')),
                  ],
                decoration: InputDecoration(
                    labelText: 'Amount (${store.currencySymbol})',
                    border: const OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(
                  controller: note,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) =>
                      Navigator.of(ctx).pop(true),
                  decoration: const InputDecoration(
                      labelText: 'Note (optional)',
                      border: OutlineInputBorder())),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  final p = await showDatePicker(
                      context: ctx,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now()
                          .add(const Duration(days: 365)),
                      initialDate: date);
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
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Save')),
          ],
        ),
      ),
    );
    final v = parseAmount(amount.text);
    if (ok == true && v != null) {
      await store.lendMore(l.id, v, date, note.text.trim());
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'Lent ${money(v)} more to ${l.person}')));
      }
    } else if (ok == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter an amount > 0')));
    }
  }

  /// One-time nudge: pick a day (and time) to be reminded once.
  /// Ask for lent money, return borrowed money.
  Future<void> _remindDialog(
      BuildContext context, ExpenseStore store, Loan l) async {
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
          title: Text(asking
              ? 'Remind me to ask ${l.person}'
              : 'Remind me to return to ${l.person}'),
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
                  final d = await showDatePicker(
                    context: ctx,
                    firstDate: now,
                    lastDate:
                        now.add(const Duration(days: 365)),
                    initialDate: picked ??
                        now.add(const Duration(days: 1)),
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
                    picked = DateTime(
                        d.year, d.month, d.day, t.hour, t.minute);
                  });
                },
              ),
              if (enabled && picked != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Once · ${_remindLabel(picked!.millisecondsSinceEpoch)}',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold),
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
                onPressed: () =>
                    Navigator.of(ctx).pop(false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () =>
                    Navigator.of(ctx).pop(true),
                child: const Text('Save')),
          ],
        ),
      ),
    );
    if (ok == true) {
      await store.setReminderAt(
          l.id, enabled ? picked : null);
      messenger.showSnackBar(SnackBar(
          content: Text(!enabled || picked == null
              ? 'Reminder off.'
              : 'Will remind once · ${_remindLabel(picked!.millisecondsSinceEpoch)}')));
      if (enabled && picked != null) {
        await _maybePromptExactAlarms(messenger);
      }
    }
  }

  /// In-context exact-alarm explanation, shown once when a reminder is
  /// saved without the system "Alarms & reminders" access (not
  /// pre-granted on Android 14+). The reminder is still scheduled via
  /// the inexact fallback, so nothing is lost if the user declines.
  Future<void> _maybePromptExactAlarms(
      ScaffoldMessengerState messenger) async {
    if (await Reminders.canUseExactAlarms()) return;
    if (!mounted) return;
    messenger.showSnackBar(SnackBar(
      content: const Text(
          'For on-time reminders, allow “Alarms & reminders” for Dhadda in system settings. Without it, reminders may arrive late.'),
      action: SnackBarAction(
        label: 'Open settings',
        onPressed: () => Reminders.requestExactAlarmAccess(),
      ),
      duration: const Duration(seconds: 8),
    ));
  }

  String _remindLabel(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${dayStr(d)} · ${TimeOfDay.fromDateTime(d).format(context)}';
  }

  Future<void> _repaymentDialog(
      BuildContext context, ExpenseStore store, Loan l) async {
    final amount = TextEditingController(
        text: l.pending.toStringAsFixed(0));
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.isBorrowed
            ? 'You returned to ${l.person}...'
            : '${l.person} returned...'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: amount,
                keyboardType:
                    const TextInputType.numberWithOptions(
                        decimal: true),
                textInputAction: TextInputAction.next,
                onSubmitted: (_) =>
                    FocusScope.of(ctx).nextFocus(),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                      RegExp(r'[0-9.,]')),
                ],
                decoration: InputDecoration(
                    labelText:
                        "Amount (${store.currencySymbol}, pending ${money(l.pending)})",
                    border: const OutlineInputBorder())),
            const SizedBox(height: 12),
                TextField(
                    controller: note,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) =>
                        Navigator.of(ctx).pop(true),
                    decoration: const InputDecoration(
                        labelText: 'Note (optional)',
                        border: OutlineInputBorder())),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Save')),
        ],
      ),
    );
    final v = parseAmount(amount.text);
    if (ok == true && v != null) {
      await store.addRepayment(l.id, v, DateTime.now(), note.text.trim());
      if (context.mounted && v >= l.pending - 0.005) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${l.person} settled up!')));
      }
    }
  }
}