import 'package:flutter/material.dart';

import '../format.dart';
import '../receipts.dart';
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
    showDeletedSnack(store, txn, messenger);
  }
}

/// Deletes an entry and offers Undo in the snackbar.
Future<void> deleteWithUndo(
    BuildContext context, ExpenseStore store, Txn txn) async {
  final messenger = ScaffoldMessenger.of(context);
  await store.deleteTransaction(txn.id);
  showDeletedSnack(store, txn, messenger);
}

/// Shows the Undo snackbar. When it closes without an undo, the deletion is
/// final and the entry's receipts are removed (the cleanup is idempotent and
/// a restored live entry's files are never touched).
void showDeletedSnack(
  ExpenseStore store,
  Txn txn,
  ScaffoldMessengerState messenger,
) {
  final cat = store.categoryOf(txn.categoryId);
  var undone = false;
  final snack = SnackBar(
    content: Text('Deleted ${txn.note.isEmpty ? cat.name : txn.note}'),
    action: SnackBarAction(
      label: 'Undo',
      onPressed: () {
        undone = true;
        store.restoreTransaction(txn);
      },
    ),
  );
  messenger.showSnackBar(snack).closed.whenComplete(() {
    if (!undone) _cleanDeletedReceipts(txn.id);
  });
}

Future<void> _cleanDeletedReceipts(String id) async {
  try {
    await (await ReceiptStore.create()).removeEntry(id);
  } catch (_) {}
}
