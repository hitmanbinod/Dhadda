import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../home_layout.dart';
import '../store.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import '../widgets/page.dart';

/// Pushed Home editor: drag to reorder, switch sections on or off. Every
/// change goes straight to the store, so the Home behind it updates live.
class EditHomeScreen extends StatelessWidget {
  const EditHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ExpenseStore>();
    final colors = AppColors.of(context);
    final gutter = pageInsets(context, vertical: 0).left;
    final layout = store.homeLayout;

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
                    key: const Key('edit-home-back'),
                    tooltip: 'Back',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: Icon(Icons.arrow_back, color: colors.textPrimary),
                  ),
                  const SizedBox(width: Spacing.xs),
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        'Edit Home',
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
            Padding(
              padding: EdgeInsets.fromLTRB(gutter, Spacing.xs, gutter, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Drag to reorder. Changes apply to Home immediately.',
                  style: AppType.caption.copyWith(color: colors.textSecondary),
                ),
              ),
            ),
            const SizedBox(height: Spacing.md),
            Expanded(
              child: ReorderableListView.builder(
                padding: EdgeInsets.fromLTRB(gutter, 0, gutter, Spacing.sm),
                buildDefaultDragHandles: false,
                itemCount: layout.length,
                proxyDecorator: (child, index, animation) => Material(
                  color: Colors.transparent,
                  elevation: 4,
                  borderRadius: Radii.cardRadius,
                  shadowColor: Colors.black.withValues(alpha: 0.3),
                  child: child,
                ),
                onReorderItem: (oldIndex, newIndex) => store.setHomeLayout(
                  moveHomeSectionInLayout(layout, oldIndex, newIndex),
                ),
                itemBuilder: (context, index) {
                  final setting = layout[index];
                  return _row(
                    context,
                    colors,
                    store,
                    setting,
                    index: index,
                    first: index == 0,
                    last: index == layout.length - 1,
                  );
                },
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                gutter,
                Spacing.sm,
                gutter,
                Spacing.lg,
              ),
              child: SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  key: const Key('edit-home-reset'),
                  onPressed: () {
                    store.resetHomeLayout();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Home reset to default.')),
                    );
                  },
                  icon: const Icon(Icons.restart_alt, size: 20),
                  label: const Text('Reset to default'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(
    BuildContext context,
    AppColors colors,
    ExpenseStore store,
    HomeSectionSetting setting, {
    required int index,
    required bool first,
    required bool last,
  }) {
    const radius = Radius.circular(Radii.card);
    final border = BorderSide(color: colors.cardBorder);
    final locked = setting.section.locked;
    return Container(
      key: ValueKey('edit-home-${setting.section.id}'),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.vertical(
          top: first ? radius : Radius.zero,
          bottom: last ? radius : Radius.zero,
        ),
        border: Border(
          left: border,
          right: border,
          top: first ? border : BorderSide.none,
          bottom: last ? border : BorderSide.none,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Spacing.xs,
              Spacing.sm,
              Spacing.sm,
              Spacing.sm,
            ),
            child: Row(
              children: [
                if (locked)
                  Semantics(
                    label: 'Balance is always shown first',
                    child: SizedBox(
                      width: Sizes.minTap,
                      height: Sizes.minTap,
                      child: Icon(
                        Icons.lock_outline,
                        size: 20,
                        color: colors.textSecondary,
                      ),
                    ),
                  )
                else
                  Semantics(
                    label: 'Reorder ${setting.section.title}',
                    button: true,
                    child: ReorderableDragStartListener(
                      index: index,
                      child: SizedBox(
                        width: Sizes.minTap,
                        height: Sizes.minTap,
                        child: Icon(
                          Icons.drag_handle,
                          size: 22,
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                const SizedBox(width: Spacing.xs),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        setting.section.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.title.copyWith(
                          fontSize: 15,
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        setting.section.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.caption.copyWith(
                          fontSize: 12,
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Spacing.xs),
                Switch(
                  key: Key('edit-home-switch-${setting.section.id}'),
                  value: locked ? true : setting.visible,
                  onChanged: locked
                      ? null
                      : (value) {
                          final next = [...store.homeLayout];
                          next[index] = next[index].copyWith(visible: value);
                          store.setHomeLayout(next);
                        },
                ),
              ],
            ),
          ),
          if (!last) Divider(height: 1, thickness: 1, color: colors.hairline),
        ],
      ),
    );
  }
}
