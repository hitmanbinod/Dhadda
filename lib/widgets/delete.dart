import 'package:flutter/material.dart';

import '../format.dart';
import '../store.dart';

/// Long-press delete with a confirm step showing what goes away.
Future<void> confirmDeleteTxn(
    BuildContext context, ExpenseStore store, Txn txn) async {
  final messenger = ScaffoldMessenger.of(context);
  final cat = store.categoryOf(txn.categoryId);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Delete this entry?'),
      content: Text(
          '${txn.note.isEmpty ? cat.name : txn.note}\n${money(txn.amount)} - ${dayStr(txn.dateTime)}'),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep')),
        FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete')),
      ],
    ),
  );
  if (ok == true) {
    await store.deleteTransaction(txn.id);
    messenger.showSnackBar(_deletedSnack(store, txn));
  }
}

/// Deletes an entry and offers Undo in the snackbar.
Future<void> deleteWithUndo(
    BuildContext context, ExpenseStore store, Txn txn) async {
  final messenger = ScaffoldMessenger.of(context);
  await store.deleteTransaction(txn.id);
  messenger.showSnackBar(_deletedSnack(store, txn));
}

SnackBar _deletedSnack(ExpenseStore store, Txn txn) {
  final cat = store.categoryOf(txn.categoryId);
  return SnackBar(
    content: Text(
        'Deleted ${txn.note.isEmpty ? cat.name : txn.note}'),
    action: SnackBarAction(
      label: 'Undo',
      onPressed: () => store.restoreTransaction(txn),
    ),
  );
}
