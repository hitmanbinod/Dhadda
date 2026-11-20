import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../category_rules.dart';
import '../store.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import '../widgets/page.dart';

/// Ordered note-contains -> category rules, stored per-device only.
class CategoryRulesScreen extends StatefulWidget {
  const CategoryRulesScreen({super.key});

  @override
  State<CategoryRulesScreen> createState() => _CategoryRulesScreenState();
}

class _CategoryRulesScreenState extends State<CategoryRulesScreen> {
  final _test = TextEditingController();

  @override
  void dispose() {
    _test.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ExpenseStore>();
    final colors = AppColors.of(context);
    final gutter = pageInsets(context, vertical: 0).left;
    final matching = store.categoryRuleFor(
      _test.text,
      'expense',
    );

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
                    key: const Key('rules-back'),
                    tooltip: 'Back',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: Icon(Icons.arrow_back, color: colors.textPrimary),
                  ),
                  const SizedBox(width: Spacing.xs),
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        'Auto-category rules',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.largeTitle.copyWith(
                          color: colors.textPrimary,
                        ),
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
                    'The first matching rule wins. Drag to set priority.',
                    style: AppType.caption.copyWith(color: colors.textSecondary),
                  ),
                  const SizedBox(height: Spacing.md),
                  if (store.categoryRules.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: Spacing.xl),
                      child: Text(
                        'No rules yet. Add one to categorise notes '
                        'automatically.',
                        style: AppType.body.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    )
                  else
                    ReorderableListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      buildDefaultDragHandles: false,
                      itemCount: store.categoryRules.length,
                      onReorderItem: (oldIndex, newIndex) =>
                          store.reorderCategoryRule(oldIndex, newIndex),
                      itemBuilder: (context, index) {
                        final rule = store.categoryRules[index];
                        final orphaned =
                            !store.categories.any((c) => c.id == rule.categoryId);
                        final category = store.categoryOf(rule.categoryId);
                        return ListTile(
                          key: ValueKey(rule.id),
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
                          title: Text(
                            rule.text,
                            style: AppType.body.copyWith(
                              fontSize: 15,
                              color: colors.textPrimary,
                            ),
                          ),
                          subtitle: Text(
                            orphaned
                                ? 'Category deleted — rule disabled'
                                : '${category.name} · ${rule.type.name}',
                            style: AppType.caption.copyWith(
                              color: orphaned
                                  ? colors.expense
                                  : colors.textSecondary,
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Switch(
                                key: Key('rule-switch-${rule.id}'),
                                value: rule.enabled && !orphaned,
                                onChanged: orphaned
                                    ? null
                                    : (v) => store.updateCategoryRule(
                                          rule.id,
                                          rule.copyWith(enabled: v),
                                        ),
                              ),
                              IconButton(
                                tooltip: 'Edit rule',
                                icon: const Icon(Icons.edit_outlined),
                                onPressed: () => _editRule(context, store, rule),
                              ),
                              IconButton(
                                tooltip: 'Delete rule',
                                icon: Icon(
                                  Icons.delete_outline,
                                  color: colors.expense,
                                ),
                                onPressed: () =>
                                    store.deleteCategoryRule(rule.id),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  const SizedBox(height: Spacing.md),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.icon(
                      key: const Key('rules-add'),
                      onPressed: () => _editRule(context, store, null),
                      icon: const Icon(Icons.add),
                      label: const Text('Add rule'),
                    ),
                  ),
                  const SizedBox(height: Spacing.xl),
                  Semantics(
                    header: true,
                    child: Text(
                      'Test a note',
                      style: AppType.captionStrong.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(height: Spacing.xs),
                  TextField(
                    key: const Key('rules-test'),
                    controller: _test,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Type a note',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: Spacing.sm),
                  Text(
                    matching == null
                        ? 'No matching rule'
                        : 'Matches: ${store.categoryOf(matching.categoryId).name}',
                    style: AppType.body.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: Spacing.lg),
                  Text(
                    'Rules are saved on this phone only.',
                    style: AppType.caption.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editRule(
    BuildContext context,
    ExpenseStore store,
    CategoryRule? rule,
  ) async {
    final text = TextEditingController(text: rule?.text ?? '');
    String type = rule?.type.name ?? 'any';
    String categoryId = rule?.categoryId ?? '';
    if (categoryId.isEmpty && store.categories.isNotEmpty) {
      categoryId = store.categories.first.id;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(rule == null ? 'Add rule' : 'Edit rule'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: text,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Note contains',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: Spacing.md),
              DropdownButtonFormField<String>(
                initialValue: categoryId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Category',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final c in store.categories)
                    DropdownMenuItem(value: c.id, child: Text(c.name)),
                ],
                onChanged: (v) => setD(() => categoryId = v ?? categoryId),
              ),
              const SizedBox(height: Spacing.md),
              DropdownButtonFormField<String>(
                initialValue: type,
                decoration: const InputDecoration(
                  labelText: 'Applies to',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'any', child: Text('Any')),
                  DropdownMenuItem(value: 'expense', child: Text('Expense')),
                  DropdownMenuItem(value: 'income', child: Text('Income')),
                ],
                onChanged: (v) => setD(() => type = v ?? 'any'),
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
                if (text.text.trim().length < 2) return;
                Navigator.of(ctx).pop(true);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    if (rule == null) {
      await store.addCategoryRule(
        text: text.text,
        categoryId: categoryId,
        type: type,
      );
    } else {
      await store.updateCategoryRule(
        rule.id,
        rule.copyWith(
          text: normalizeRuleText(text.text),
          categoryId: categoryId,
          type: CategoryRuleType.values.firstWhere(
            (t) => t.name == type,
            orElse: () => CategoryRuleType.any,
          ),
        ),
      );
    }
  }
}
