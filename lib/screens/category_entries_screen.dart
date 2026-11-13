import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:provider/provider.dart';

import '../format.dart';
import '../store.dart';
import '../widgets/delete.dart';
import '../widgets/entry_actions.dart';

/// All history for one category: opened by tapping a category in the
/// Categories tab. Rows behave exactly like the Entries list - tap to
/// edit, slide to delete with undo.
class CategoryEntriesScreen extends StatelessWidget {
  final Category category;

  const CategoryEntriesScreen({super.key, required this.category});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ExpenseStore>();
    final txns = store.transactions
        .where((t) => t.categoryId == category.id)
        .toList();
    final spent = txns.fold(0.0, (s, t) => t.isExpense ? s + t.amount : s);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(category.iconData, color: category.colorValue, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text(category.name, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: _stat(
                          'Spent', money(spent), Colors.red),
                    ),
                    Expanded(
                      child: _stat('Entries', '${txns.length}', null),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: txns.isEmpty
                ? const Center(
                    child: Text('No entries in this category yet.'))
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: txns.length,
                    itemBuilder: (ctx, i) {
                      final t = txns[i];
                      return Slidable(
                        key: ValueKey(t.id),
                        endActionPane: ActionPane(
                          motion: const BehindMotion(),
                          extentRatio: 0.8,
                          children: [
                            SlidableAction(
                              onPressed: (_) =>
                                  deleteWithUndo(context, store, t),
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                              icon: Icons.delete,
                              label: 'Delete',
                            ),
                          ],
                        ),
                        child: ListTile(
                          onTap: () =>
                              showEntryActions(context, store, t),
                          onLongPress: () =>
                              showEntryActions(context, store, t),
                          title: Text(
                              t.note.isEmpty ? category.name : t.note),
                          subtitle: Text(
                              '${dayStr(t.dateTime)}  ·  ${t.mode.toUpperCase()}'),
                          trailing: Text(
                            '${t.isExpense ? '-' : '+'}${money(t.amount)}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: t.isExpense
                                  ? Colors.red
                                  : Colors.green,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value, Color? color) {
    return Column(
      children: [
        Text(label,
            style: const TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: color,
          ),
        ),
      ],
    );
  }
}
