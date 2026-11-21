import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_dates.dart';
import '../format.dart';
import '../receipts.dart';
import '../store.dart';
import '../theme/tokens.dart';
import 'delete.dart';
import 'receipt_field.dart';

const _modes = ['cash', 'bank', 'card', 'ewallet'];

/// Tap (desktop: left-click) an entry: edit amount, note, category,
/// payment mode, date, project and receipts in one sheet - or delete it.
Future<void> showEntryActions(
    BuildContext context, ExpenseStore store, Txn txn) async {
  // Load receipt paths without touching [context] after an await. The dialog
  // helper below receives the context and uses it synchronously.
  List<String> originalReceipts = [];
  try {
    originalReceipts = await (await ReceiptStore.create()).forEntryPaths(txn.id);
  } catch (_) {}
  if (!context.mounted) return;
  await _showEditDialog(context, store, txn, originalReceipts);
}

Future<void> _showEditDialog(
  BuildContext context,
  ExpenseStore store,
  Txn txn,
  List<String> originalReceipts,
) async {
  final amount = TextEditingController(
      text: txn.amount.toStringAsFixed(
          txn.amount.truncateToDouble() == txn.amount ? 0 : 2));
  final note = TextEditingController(text: txn.note);
  var categoryId = txn.categoryId;
  var categoryChanged = false;
  if (store.categories.isNotEmpty &&
      store.categories.every((c) => c.id != categoryId)) {
    categoryId = store.categories.first.id;
  }
  var mode = _modes.contains(txn.mode) ? txn.mode : 'cash';
  var accountId = txn.accountId.isEmpty
      ? accountIdForMode(txn.mode)
      : txn.accountId;
  var projectId = txn.projectId;
  var date = txn.dateTime;
  var time = TimeOfDay.fromDateTime(txn.dateTime);
  final cat = store.categoryOf(txn.categoryId);

  List<String> storedReceipts = [...originalReceipts];
  List<String> capturedReceipts = [];

  final saved = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) {
        Future<void> submit() async {
          final v = parseAmount(amount.text);
          if (v == null) {
            if (ctx.mounted) {
              ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(
                      content: Text(
                          'Enter a valid amount (numbers only)')));
            }
            return;
          }
          final ok = await store.updateTransaction(txn.id,
              amount: v,
              note: note.text.trim(),
              categoryId: categoryId,
              mode: mode,
              accountId: accountId,
              date: DateTime(date.year, date.month,
                  date.day, time.hour, time.minute),
              projectId: projectId);
          if (!ok) {
            if (ctx.mounted) {
              ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                  content: Text(
                      'Could not save — storage failed. '
                      'Your edit was not applied. Please try again.')));
            }
            return;
          }
          // Receipt changes are applied only after the entry edit succeeds,
          // so a failed save never drops a photo.
          try {
            final receipts = await ReceiptStore.create();
            final plan = planReceiptChanges(originalReceipts, storedReceipts);
            for (final path in plan.removed) {
              await receipts.removeOne(path);
            }
            if (capturedReceipts.isNotEmpty) {
              final attached = await receipts.attach(txn.id, capturedReceipts);
              storedReceipts = [
                ...storedReceipts.where((p) => !isCapturedReceiptPath(p)),
                ...attached,
              ];
            }
            capturedReceipts = [];
          } catch (_) {
            // Photos are local-only; a failure here must not undo the edit.
          }
          if (ctx.mounted) Navigator.of(ctx).pop(true);
        }

        return AlertDialog(
          title: Text(txn.isExpense ? 'Edit expense' : 'Edit income'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                    '${cat.name} - ${money(txn.amount)} - ${dayStr(txn.dateTime)}',
                    style: Theme.of(ctx).textTheme.bodySmall),
                const SizedBox(height: 12),
                TextField(
                  controller: amount,
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true),
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) => FocusScope.of(ctx).nextFocus(),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  decoration: InputDecoration(
                    labelText: 'Amount',
                    border: const OutlineInputBorder(),
                    prefixText: '${store.currencySymbol} '),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: note,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => submit(),
                  decoration: const InputDecoration(
                    labelText: 'Note',
                    border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: categoryId,
                  decoration: const InputDecoration(
                    labelText: 'Category',
                    border: OutlineInputBorder()),
                  items: [
                    for (final c in store.categories)
                      DropdownMenuItem(value: c.id, child: Text(c.name)),
                  ],
                  onChanged: (v) => setD(() {
                    if (v != null && v != categoryId) categoryChanged = true;
                    categoryId = v ?? categoryId;
                  }),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: accountId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Account',
                    border: OutlineInputBorder()),
                  items: [
                    for (final a in store.accountsForPicker(
                      includeArchivedId: accountId,
                    ))
                      DropdownMenuItem(value: a.id, child: Text(a.name)),
                  ],
                  onChanged: (v) => setD(() {
                    accountId = v ?? accountId;
                    mode = modeForAccountType(store.accountOf(accountId).type);
                  }),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: projectId,
                  decoration: const InputDecoration(
                    labelText: 'Event',
                    border: OutlineInputBorder()),
                  items: [
                    const DropdownMenuItem(value: '', child: Text('No event')),
                    for (final p in store.projects)
                      DropdownMenuItem(value: p.id, child: Text(p.name)),
                  ],
                  onChanged: (v) => setD(() => projectId = v ?? ''),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final picked = await showAppDatePicker(
                            context: ctx,
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now().add(
                                const Duration(days: 365)),
                            initialDate: date,
                          );
                          if (picked != null && ctx.mounted) {
                            setD(() => date = picked);
                          }
                        },
                        icon: const Icon(Icons.calendar_today),
                        label: Text(dayStr(date)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final picked = await showTimePicker(
                            context: ctx,
                            initialTime: time,
                          );
                          if (picked != null && ctx.mounted) {
                            setD(() => time = picked);
                          }
                        },
                        icon: const Icon(Icons.schedule),
                        label: Text(time.format(ctx)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Spacing.lg),
                ReceiptField(
                  initial: originalReceipts,
                  onChanged: (paths) => storedReceipts = paths,
                  onCapturedChanged: (paths) => capturedReceipts = paths,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                Navigator.of(ctx).pop(false);
                await confirmDeleteTxn(context, store, txn);
              },
              child: const Text('Delete', style: TextStyle(color: Colors.red)),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(onPressed: submit, child: const Text('Save')),
          ],
        );
      },
    ),
  );
  if (saved != true) {
    // Cancelled/dismissed: captures were never attached, so drop them;
    // stored receipts are untouched (the entry keeps its original files).
    await cleanupCapturedPaths(capturedReceipts);
    return;
  }
  if (context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Saved')));
    final text = note.text.trim();
    if (categoryChanged &&
        text.length >= 2 &&
        store.categories.any((c) => c.id == categoryId)) {
      final name = store.categoryOf(categoryId).name;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Always put "$text" in $name?'),
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: 'Yes',
            onPressed: () => store.addCategoryRule(
              text: text,
              categoryId: categoryId,
              type: txn.type,
            ),
          ),
        ),
      );
    }
  }
}
