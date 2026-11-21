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

/// Soft tint for an account icon/dot. Zero colour falls back to the accent.
Color accountTint(AppColors colors, Account a) =>
    a.color == 0 ? colors.accent : Color(a.color);

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
    final archived = store.accounts.where((a) => a.archived).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final lastActive = sorted.length <= 1;

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
                  if (sorted.isEmpty)
                    Semantics(
                      label: 'No active accounts. Add one below.',
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: Spacing.lg),
                        child: Text(
                          'No active accounts. Add one below.',
                          style: AppType.body.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                      ),
                    )
                  else
                    ReorderableListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      buildDefaultDragHandles: false,
                      itemCount: sorted.length,
                      onReorderItem: (oldIndex, newIndex) =>
                          store.reorderAccounts(oldIndex, newIndex),
                      itemBuilder: (context, index) {
                        final a = sorted[index];
                        final entries = store.accountEntryCount(a.id);
                        return Semantics(
                          key: ValueKey(a.id),
                          label: '${a.name}, ${a.type}, $entries entries',
                          child: ListTile(
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
                            title: Row(
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  margin: const EdgeInsets.only(right: 8),
                                  decoration: BoxDecoration(
                                    color: accountTint(colors, a),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                Expanded(
                                  child: Text(a.name, style: AppType.title),
                                ),
                              ],
                            ),
                            subtitle: Text(
                              '$a.type · $entries ${entries == 1 ? 'entry' : 'entries'}',
                              style: AppType.caption,
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'Edit',
                                  icon: const Icon(Icons.edit_outlined),
                                  onPressed: () => _edit(context, store, a),
                                ),
                                IconButton(
                                  key: Key('account-delete-${a.id}'),
                                  tooltip: 'Delete',
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () => _delete(context, store, a),
                                ),
                                IconButton(
                                  tooltip: 'Archive',
                                  icon: const Icon(Icons.archive_outlined),
                                  onPressed: lastActive
                                      ? () => _say(
                                          context,
                                          'Keep at least one active account.',
                                        )
                                      : () => store.archiveAccount(a.id),
                                ),
                                IconButton(
                                  tooltip: 'Merge into another',
                                  icon: const Icon(Icons.merge_type),
                                  onPressed: () => _merge(context, store, a),
                                ),
                              ],
                            ),
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
                    'An account with entries cannot be hard-deleted — archive '
                    'or merge it instead. The last active account is kept.',
                    style: AppType.caption.copyWith(color: colors.textSecondary),
                  ),
                  if (archived.isNotEmpty) ...[
                    const SizedBox(height: Spacing.md),
                    Semantics(
                      header: true,
                      child: Text(
                        'Archived',
                        style: AppType.captionStrong.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                    for (final a in archived)
                      Semantics(
                        label: '${a.name}, archived',
                        child: ListTile(
                          key: ValueKey('archived-${a.id}'),
                          leading: Icon(Icons.archive_outlined,
                              color: colors.textSecondary),
                          title: Text(a.name),
                          subtitle: Text(
                            '${store.accountEntryCount(a.id)} entries · hidden from pickers',
                            style: AppType.caption,
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TextButton(
                                onPressed: () => store.updateAccount(
                                  a.copyWith(archived: false),
                                ),
                                child: const Text('Unarchive'),
                              ),
                              TextButton(
                                onPressed: () => _merge(context, store, a),
                                child: const Text('Merge'),
                              ),
                            ],
                          ),
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

  void _say(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _delete(
    BuildContext context,
    ExpenseStore store,
    Account a,
  ) async {
    final entries = store.accountEntryCount(a.id);
    if (entries > 0) {
      _say(
        context,
        'Has $entries ${entries == 1 ? 'entry' : 'entries'}: '
        'archive it or merge it into another account.',
      );
      return;
    }
    if (store.activeAccounts.length <= 1) {
      _say(context, 'The last active account cannot be deleted.');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${a.name}?'),
        content: const Text('This account has no entries. It will be removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('account-delete-confirm'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) {
      final done = await store.deleteAccount(a.id);
      if (!done && context.mounted) {
        _say(context, 'This account can no longer be deleted.');
      }
    }
  }

  Future<void> _edit(
    BuildContext context,
    ExpenseStore store,
    Account? account,
  ) async {
    final colors = AppColors.of(context);
    final name = TextEditingController(text: account?.name ?? '');
    var type = account?.type ?? 'cash';
    var color = account?.color ?? 0;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(account == null ? 'Add account' : 'Edit account'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
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
                const SizedBox(height: Spacing.md),
                Semantics(
                  header: true,
                  child: Text(
                    'Colour (optional)',
                    style: AppType.caption.copyWith(color: colors.textSecondary),
                  ),
                ),
                const SizedBox(height: Spacing.xs),
                Wrap(
                  spacing: Spacing.sm,
                  runSpacing: Spacing.sm,
                  children: [
                    for (final v in kColorChoices)
                      GestureDetector(
                        key: Key('account-color-$v'),
                        onTap: () => setD(() => color = v),
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: Color(v),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: color == v
                                  ? Theme.of(ctx).colorScheme.onSurface
                                  : Colors.transparent,
                              width: 3,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: Spacing.xs),
                TextButton(
                  onPressed: () => setD(() => color = 0),
                  child: const Text('Use default'),
                ),
              ],
            ),
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
    if (ok != true || name.text.trim().isEmpty) return;
    if (account == null) {
      await store.addAccount(name.text, type, color: color);
    } else {
      await store.updateAccount(
        account.copyWith(name: name.text.trim(), type: type, color: color),
      );
    }
  }

  Future<void> _merge(
    BuildContext context,
    ExpenseStore store,
    Account source,
  ) async {
    final targets = store.activeAccounts.where((a) => a.id != source.id).toList();
    if (targets.isEmpty) {
      _say(context, 'There is no other active account to merge into.');
      return;
    }
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
