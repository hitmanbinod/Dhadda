import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../store.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import '../widgets/page.dart';

const _types = ['cash', 'bank', 'card', 'wallet', 'other'];

IconData _iconFor(String type) => switch (type) {
      'bank' => Icons.account_balance_outlined,
      'card' => Icons.credit_card_outlined,
      'wallet' => Icons.account_balance_wallet_outlined,
      'other' => Icons.account_circle_outlined,
      _ => Icons.money_outlined,
    };

/// Settings > Money > Accounts. Ordered, per-device account labels — no
/// balances are stored or shown here.
class AccountsScreen extends StatelessWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ExpenseStore>();
    final colors = AppColors.of(context);
    final gutter = pageInsets(context, vertical: 0).left;
    final sorted = store.activeAccounts;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                gutter - Spacing.sm,
                Spacing.sm,
                gutter,
                0,
              ),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Back',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: Icon(Icons.arrow_back, color: colors.textPrimary),
                  ),
                  const SizedBox(width: Spacing.xs),
                  Expanded(
                    child: Text(
                      'Accounts',
                      style: AppType.largeTitle.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: pageInsets(context),
                children: [
                  Text(
                    'Accounts label how you pay. They hold no balance.',
                    style: AppType.caption.copyWith(color: colors.textSecondary),
                  ),
                  const SizedBox(height: Spacing.md),
                  ReorderableListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    buildDefaultDragHandles: false,
                    itemCount: sorted.length,
                    onReorderItem: (oldIndex, newIndex) =>
                        store.reorderAccounts(oldIndex, newIndex),
                    itemBuilder: (context, index) {
                      final a = sorted[index];
                      return ListTile(
                        key: ValueKey(a.id),
                        leading: ReorderableDragStartListener(
                          index: index,
                          child: SizedBox(
                            width: Sizes.minTap,
                            height: Sizes.minTap,
                            child: Icon(
                              Icons.drag_handle,
                              color: colors.textSecondary,
                            ),
                          ),
                        ),
                        title: Text(a.name, style: AppType.title),
                        subtitle: Text(a.type, style: AppType.caption),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Edit',
                              icon: const Icon(Icons.edit_outlined),
                              onPressed: () => _edit(context, store, a),
                            ),
                            IconButton(
                              tooltip: 'Archive',
                              icon: const Icon(Icons.archive_outlined),
                              onPressed: () => store.archiveAccount(a.id),
                            ),
                            IconButton(
                              tooltip: 'Merge into another',
                              icon: const Icon(Icons.merge_type),
                              onPressed: () => _merge(context, store, a),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: Spacing.md),
                  FilledButton.icon(
                    onPressed: () => _edit(context, store, null),
                    icon: const Icon(Icons.add),
                    label: const Text('Add account'),
                  ),
                  const SizedBox(height: Spacing.lg),
                  Text(
                    'Archived accounts are hidden from pickers but their '
                    'entries stay in History and totals. An account with '
                    'entries can be archived or merged, not hard-deleted.',
                    style: AppType.caption.copyWith(color: colors.textSecondary),
                  ),
                  if (store.accounts.any((a) => a.archived)) ...[
                    const SizedBox(height: Spacing.md),
                    Text(
                      'Archived',
                      style: AppType.captionStrong.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                    for (final a in store.accounts.where((x) => x.archived))
                      ListTile(
                        title: Text(a.name),
                        subtitle: const Text('Hidden from pickers'),
                        trailing: TextButton(
                          onPressed: () =>
                              store.updateAccount(a.copyWith(archived: false)),
                          child: const Text('Restore'),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _edit(
    BuildContext context,
    ExpenseStore store,
    Account? account,
  ) async {
    final name = TextEditingController(text: account?.name ?? '');
    var type = account?.type ?? 'cash';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(account == null ? 'Add account' : 'Edit account'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: Spacing.md),
              DropdownButtonFormField<String>(
                initialValue: type,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Type',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final t in _types)
                    DropdownMenuItem(
                      value: t,
                      child: Row(
                        children: [
                          Icon(_iconFor(t), size: 18),
                          const SizedBox(width: Spacing.sm),
                          Text(t),
                        ],
                      ),
                    ),
                ],
                onChanged: (v) => setD(() => type = v ?? 'cash'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (name.text.trim().isEmpty) return;
                Navigator.of(ctx).pop(true);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !name.text.trim().isNotEmpty) return;
    if (account == null) {
      await store.addAccount(name.text, type);
    } else {
      await store.updateAccount(
        account.copyWith(name: name.text.trim(), type: type),
      );
    }
  }

  Future<void> _merge(
    BuildContext context,
    ExpenseStore store,
    Account source,
  ) async {
    final targets = store.activeAccounts.where((a) => a.id != source.id).toList();
    if (targets.isEmpty) return;
    String target = targets.first.id;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text('Merge ${source.name} into…'),
          content: DropdownButtonFormField<String>(
            initialValue: target,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Target account',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final a in targets)
                DropdownMenuItem(value: a.id, child: Text(a.name)),
            ],
            onChanged: (v) => setD(() => target = v ?? targets.first.id),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Merge'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) await store.mergeAccount(source.id, target);
  }
}
