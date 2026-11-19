import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:provider/provider.dart';

import '../format.dart';
import '../store.dart';
import '../theme/haptics.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import '../widgets/amount_text.dart';
import '../widgets/app_card.dart';
import '../widgets/category_tile.dart';
import '../widgets/delete.dart';
import '../widgets/empty_state.dart';
import '../widgets/entry_actions.dart';
import '../widgets/event_branch_group.dart';
import '../widgets/page.dart' show kPageMaxWidth, tabScrollBottomPadding;
import '../widgets/profile_avatar.dart';
import '../widgets/section_header.dart';

/// Dashboard: month totals, category distribution, budgets, recent entries.
class HomeScreen extends StatefulWidget {
  final VoidCallback onAdd;
  final Future<String> Function()? onSync;

  /// Opens the Sync screen. Falls back to a direct sync when absent
  /// (tests and embedded uses that do not own a link engine).
  final VoidCallback? onOpenSync;

  /// Opens Settings from the profile header.
  final VoidCallback? onOpenSettings;

  /// Switches the shell to History.
  final VoidCallback? onSeeAll;

  const HomeScreen({
    super.key,
    required this.onAdd,
    this.onSync,
    this.onOpenSync,
    this.onOpenSettings,
    this.onSeeAll,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

/// One slice of the month's spending: a category, or the grouped tail.
class _Slice {
  final String id;
  final String name;
  final IconData icon;
  final Color color;
  final double value;

  const _Slice({
    required this.id,
    required this.name,
    required this.icon,
    required this.color,
    required this.value,
  });
}

class _HomeScreenState extends State<HomeScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  String? _spotlightId;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ExpenseStore>();
    if (!store.loaded) {
      return const Center(child: CircularProgressIndicator());
    }

    final colors = AppColors.of(context);
    final analytics = store.monthly(_month);
    final spend = analytics.spend;
    final income = analytics.income;
    final balance = income - spend;
    final byCat = analytics.byCategory;

    // Largest categories first, with the tail grouped so the bar and the
    // rows stay readable no matter how many categories exist.
    final sorted = byCat.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = sorted.take(6).toList();
    final others = sorted.skip(6).fold(0.0, (sum, e) => sum + e.value);
    final slices = <_Slice>[
      for (final e in top)
        _Slice(
          id: e.key,
          name: store.categoryOf(e.key).name,
          icon: store.categoryOf(e.key).iconData,
          color: store.categoryOf(e.key).colorValue,
          value: e.value,
        ),
      if (others > 0)
        _Slice(
          id: '__others__',
          name: 'Others',
          icon: Icons.more_horiz,
          color: colors.textSecondary,
          value: others,
        ),
    ];
    final _Slice? spotlight = slices.isEmpty
        ? null
        : slices.firstWhere(
            (s) => s.id == _spotlightId,
            orElse: () => slices.first,
          );

    // This month's event activity: each event's entries collected under
    // one collapsible branch (transactions are newest-first globally, so
    // groups appear newest-event first).
    final monthEvents = <Project, List<Txn>>{};
    for (final t in store.transactions) {
      if (t.projectId.isEmpty) continue;
      final d = t.dateTime;
      if (d.year != _month.year || d.month != _month.month) continue;
      final p = store.projectOf(t.projectId);
      if (p.id.isEmpty) continue;
      (monthEvents[p] ??= []).add(t);
    }

    final budgets = store.categories
        .where((c) => c.budget > 0)
        .toList(growable: false);
    // Event-tagged entries live in the Events branches, so Recent shows
    // only untagged activity.
    final recent = store.transactions
        .where((t) => t.projectId.isEmpty)
        .take(8)
        .toList(growable: false);

    return LayoutBuilder(
      builder: (context, constraints) {
        // Local 20dp phone margin, centred and capped at 880dp. Computed
        // from the body's width (not the window) so the NavigationRail
        // does not shift the column on desktop.
        final hPad = math.max(
          Spacing.screen,
          (constraints.maxWidth - kPageMaxWidth) / 2,
        );

        return AnnotatedRegion<SystemUiOverlayStyle>(
          value:
              (Theme.of(context).brightness == Brightness.dark
                      ? SystemUiOverlayStyle.light
                      : SystemUiOverlayStyle.dark)
                  .copyWith(statusBarColor: Colors.transparent),
          child: Stack(
            children: [
              RefreshIndicator(
                onRefresh: _doSync,
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(hPad, Spacing.sm, hPad, 0),
                      sliver: SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _header(context, store, colors),
                            _balanceHero(colors, balance),
                            _stats(
                              colors,
                              spend: spend,
                              income: income,
                              lent: store.pendingLoansTotal,
                            ),
                            const SizedBox(height: Spacing.xl),
                            const SectionHeader('By category'),
                            const SizedBox(height: Spacing.sm),
                            _categoriesCard(
                              context,
                              colors,
                              slices: slices,
                              spotlight: spotlight,
                              spend: spend,
                            ),
                            if (budgets.isNotEmpty) ...[
                              const SizedBox(height: Spacing.xl),
                              const SectionHeader('Budgets'),
                              const SizedBox(height: Spacing.sm),
                              AppCard.group(
                                children: [
                                  for (final c in budgets)
                                    _budgetRow(
                                      context,
                                      colors,
                                      c,
                                      byCat[c.id] ?? 0,
                                    ),
                                ],
                              ),
                            ],
                            if (monthEvents.isNotEmpty) ...[
                              const SizedBox(height: Spacing.xl),
                              const SectionHeader('Events'),
                              const SizedBox(height: Spacing.sm),
                              AppCard(
                                padding: const EdgeInsets.fromLTRB(
                                  Spacing.md,
                                  Spacing.xs,
                                  Spacing.md,
                                  Spacing.sm,
                                ),
                                child: Column(
                                  children: [
                                    for (final e in monthEvents.entries)
                                      EventBranchGroup(
                                        key: ValueKey('home-${e.key.id}'),
                                        store: store,
                                        project: e.key,
                                        txns: e.value,
                                        initiallyExpanded: false,
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(
                        hPad,
                        Spacing.xl,
                        hPad,
                        Spacing.sm,
                      ),
                      sliver: SliverToBoxAdapter(
                        child: SectionHeader(
                          'Recent',
                          trailing: TextButton(
                            onPressed: widget.onSeeAll,
                            child: const Text('See all'),
                          ),
                        ),
                      ),
                    ),
                    if (recent.isEmpty)
                      SliverPadding(
                        padding: EdgeInsets.symmetric(horizontal: hPad),
                        sliver: SliverToBoxAdapter(
                          child: AppCard(
                            child: EmptyState(
                              icon: Icons.receipt_long_outlined,
                              message: 'No entries yet.',
                              actionLabel: 'Add expense',
                              onAction: widget.onAdd,
                            ),
                          ),
                        ),
                      )
                    else
                      SliverPadding(
                        padding: EdgeInsets.symmetric(horizontal: hPad),
                        // Rows are built on demand and share one grouped
                        // card: first/last rows round the outer corners.
                        sliver: SliverList.builder(
                          itemCount: recent.length,
                          itemBuilder: (context, i) {
                            final first = i == 0;
                            final last = i == recent.length - 1;
                            return _recentSurface(
                              colors,
                              first: first,
                              last: last,
                              child: _recentRow(
                                context,
                                colors,
                                store,
                                recent[i],
                              ),
                            );
                          },
                        ),
                      ),
                    SliverToBoxAdapter(
                      child: SizedBox(height: tabScrollBottomPadding(context)),
                    ),
                  ],
                ),
              ),
              Positioned(
                right: hPad,
                bottom: Spacing.xl,
                child: _addPill(context, colors),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Profile row first, then the large month title with its pager and
  /// calendar jump. Tapping the avatar/name opens Settings.
  Widget _header(BuildContext context, ExpenseStore store, AppColors colors) {
    final name = store.userName.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Semantics(
                button: true,
                label: 'Open settings',
                child: InkWell(
                  key: const Key('home-profile'),
                  onTap: widget.onOpenSettings,
                  borderRadius: Radii.cardRadius,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
                    child: Row(
                      children: [
                        ProfileAvatar(name: name),
                        const SizedBox(width: Spacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name.isEmpty ? 'Set your name' : name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppType.title.copyWith(
                                  color: colors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 1),
                              Text(
                                homeGreeting('', DateTime.now()),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
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
                ),
              ),
            ),
            const SizedBox(width: Spacing.xs),
            _headerIcon(
              colors,
              Icons.sync,
              'Sync',
              widget.onOpenSync ?? () => _doSync(),
            ),
          ],
        ),
        const SizedBox(height: Spacing.md),
        Row(
          children: [
            Expanded(
              child: Semantics(
                button: true,
                label: 'Jump to month',
                child: InkWell(
                  onTap: _pickMonth,
                  borderRadius: BorderRadius.circular(Radii.icon),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: _monthTitle(colors),
                          ),
                        ),
                        const SizedBox(width: Spacing.xs),
                        Icon(
                          Icons.expand_more,
                          size: 20,
                          color: colors.textSecondary,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            _headerIcon(
              colors,
              Icons.chevron_left,
              'Previous month',
              () => setState(
                () => _month = DateTime(_month.year, _month.month - 1),
              ),
            ),
            _headerIcon(
              colors,
              Icons.chevron_right,
              'Next month',
              () => setState(
                () => _month = DateTime(_month.year, _month.month + 1),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _headerIcon(
    AppColors colors,
    IconData icon,
    String tooltip,
    VoidCallback onPressed,
  ) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      icon: Icon(icon, size: 20, color: colors.textSecondary),
    );
  }

  Widget _monthTitle(AppColors colors) {
    final label = monthStr(_month);
    final split = label.lastIndexOf(' ');
    final style = AppType.largeTitle.copyWith(color: colors.textPrimary);
    if (split <= 0) {
      return Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: label.substring(0, split)),
          TextSpan(
            text: label.substring(split),
            style: TextStyle(color: colors.textSecondary),
          ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
  }

  Widget _balanceHero(AppColors colors, double balance) {
    return Padding(
      padding: const EdgeInsets.only(top: Spacing.xl, bottom: Spacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Balance',
            style: AppType.caption.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: Spacing.xs),
          Align(
            alignment: Alignment.centerLeft,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                money(balance),
                maxLines: 1,
                style: AppType.heroAmount.copyWith(
                  color: balance < 0 ? colors.expense : colors.textPrimary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// One card, three equal columns: Spent, Income, Lent out.
  Widget _stats(
    AppColors colors, {
    required double spend,
    required double income,
    required double lent,
  }) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: Row(
        children: [
          _statCell(colors, 'Spent', spend, colors.expense),
          _statDivider(colors),
          _statCell(colors, 'Income', income, colors.income),
          _statDivider(colors),
          _statCell(colors, 'Lent out', lent, colors.textPrimary),
        ],
      ),
    );
  }

  Widget _statCell(AppColors colors, String label, double value, Color color) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.sm,
          vertical: Spacing.md,
        ),
        child: Column(
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.caption.copyWith(
                fontSize: 12,
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: Spacing.xs + 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                money(value),
                maxLines: 1,
                style: AppType.statValue.copyWith(color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statDivider(AppColors colors) {
    return Container(width: 1, height: 36, color: colors.hairline);
  }

  Widget _categoriesCard(
    BuildContext context,
    AppColors colors, {
    required List<_Slice> slices,
    required _Slice? spotlight,
    required double spend,
  }) {
    if (slices.isEmpty || spotlight == null) {
      return AppCard(
        child: EmptyState(
          icon: Icons.pie_chart_outline,
          message: 'No expenses this month yet.',
          padding: const EdgeInsets.symmetric(vertical: Spacing.lg),
        ),
      );
    }

    return AppCard(
      padding: const EdgeInsets.fromLTRB(
        Spacing.lg,
        Spacing.md,
        Spacing.lg,
        Spacing.md,
      ),
      child: Column(
        children: [
          Row(
            key: const Key('home-cat-spotlight'),
            children: [
              _sliceTile(spotlight),
              const SizedBox(width: Spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      spotlight.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.title.copyWith(fontSize: 15),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_percent(spotlight.value, spend)} of month spend',
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
              Text(
                money(spotlight.value),
                maxLines: 1,
                style: AppType.statValue.copyWith(fontSize: 16),
              ),
            ],
          ),
          const SizedBox(height: Spacing.lg),
          _stackedBar(slices, spend),
          const SizedBox(height: Spacing.md),
          for (final slice in slices)
            _categoryRow(
              context,
              colors,
              slice,
              spend: spend,
              selected: slice.id == spotlight.id,
            ),
        ],
      ),
    );
  }

  Widget _sliceTile(_Slice slice) {
    return Container(
      width: Sizes.iconTile,
      height: Sizes.iconTile,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: slice.color.withValues(alpha: 0.14),
        borderRadius: Radii.iconRadius,
      ),
      child: Icon(slice.icon, size: Sizes.iconGlyph, color: slice.color),
    );
  }

  Widget _stackedBar(List<_Slice> slices, double spend) {
    if (spend <= 0) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        return Semantics(
          label: 'Spending by category',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => _selectFromBar(
              d.localPosition.dx,
              constraints.maxWidth,
              slices,
              spend,
            ),
            onLongPressStart: (d) => _selectFromBar(
              d.localPosition.dx,
              constraints.maxWidth,
              slices,
              spend,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                height: 12,
                child: Row(
                  children: [
                    for (final slice in slices)
                      Expanded(
                        flex: math.max(
                          1,
                          (slice.value / spend * 10000).round(),
                        ),
                        child: ColoredBox(color: slice.color),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _selectFromBar(
    double dx,
    double width,
    List<_Slice> slices,
    double spend,
  ) {
    if (width <= 0 || spend <= 0) return;
    final x = (dx / width).clamp(0.0, 1.0);
    var accumulated = 0.0;
    for (final slice in slices) {
      accumulated += slice.value / spend;
      if (x <= accumulated) {
        _setSpotlight(slice.id);
        return;
      }
    }
    _setSpotlight(slices.last.id);
  }

  void _setSpotlight(String id) {
    if (_spotlightId == id) return;
    Haptics.selection();
    setState(() => _spotlightId = id);
  }

  Widget _categoryRow(
    BuildContext context,
    AppColors colors,
    _Slice slice, {
    required double spend,
    required bool selected,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: InkWell(
        key: Key('home-cat-${slice.id}'),
        onTap: () => _setSpotlight(slice.id),
        onLongPress: () => _setSpotlight(slice.id),
        borderRadius: BorderRadius.circular(Radii.icon),
        child: AnimatedContainer(
          duration: Motion.of(context, Motion.fast),
          curve: Motion.ease,
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.sm,
            vertical: 7,
          ),
          decoration: BoxDecoration(
            color: selected ? colors.field : Colors.transparent,
            borderRadius: BorderRadius.circular(Radii.icon),
          ),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: slice.color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  slice.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.body.copyWith(
                    fontSize: 14,
                    color: colors.textPrimary,
                  ),
                ),
              ),
              Text(
                _percent(slice.value, spend),
                style: AppType.caption.copyWith(
                  fontSize: 12,
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(width: Spacing.md),
              Text(
                money(slice.value),
                maxLines: 1,
                style: AppType.amount.copyWith(fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _percent(double value, double total) {
    if (total <= 0) return '0%';
    final pct = value / total * 100;
    if (pct > 0 && pct < 1) return '<1%';
    return '${pct.round()}%';
  }

  Widget _budgetRow(
    BuildContext context,
    AppColors colors,
    Category category,
    double used,
  ) {
    final over = used > category.budget;
    final ratio = category.budget <= 0
        ? 0.0
        : (used / category.budget).clamp(0.0, 1.0);
    final pct = category.budget <= 0
        ? 0
        : (used / category.budget * 100).round();
    final barColor = over ? colors.expense : category.colorValue;

    return Padding(
      key: Key('home-budget-${category.id}'),
      padding: const EdgeInsets.fromLTRB(
        Spacing.lg,
        Spacing.md,
        Spacing.lg,
        Spacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CategoryTile(category: category, size: 32, iconSize: 17),
              const SizedBox(width: Spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      category.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.title.copyWith(fontSize: 14),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      over
                          ? 'Over by ${money(used - category.budget)}'
                          : '${money(used)} of ${money(category.budget)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.caption.copyWith(
                        color: over ? colors.expense : colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Spacing.sm),
              Text(
                '$pct%',
                style: AppType.captionStrong.copyWith(
                  fontSize: 12,
                  color: over ? colors.expense : colors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: Spacing.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 6,
              backgroundColor: colors.track,
              color: barColor,
            ),
          ),
        ],
      ),
    );
  }

  /// Rounded, grouped surface for one Recent row. The first and last row
  /// round the outer corners, so the lazily built list reads as one card.
  Widget _recentSurface(
    AppColors colors, {
    required bool first,
    required bool last,
    required Widget child,
  }) {
    const radius = Radius.circular(Radii.card);
    final border = BorderSide(color: colors.cardBorder);
    return Container(
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
          child,
          if (!last) Divider(height: 1, thickness: 1, color: colors.hairline),
        ],
      ),
    );
  }

  Widget _recentRow(
    BuildContext context,
    AppColors colors,
    ExpenseStore store,
    Txn txn,
  ) {
    final c = store.categoryOf(txn.categoryId);
    return Slidable(
      key: ValueKey('home-recent-${txn.id}'),
      endActionPane: ActionPane(
        motion: const BehindMotion(),
        extentRatio: 0.32,
        children: [
          SlidableAction(
            onPressed: (_) {
              Haptics.tap();
              deleteWithUndo(context, store, txn);
            },
            backgroundColor: colors.expense,
            foregroundColor: colors.onAccent,
            icon: Icons.delete_outline,
            label: 'Delete',
          ),
        ],
      ),
      child: InkWell(
        onTap: () => showEntryActions(context, store, txn),
        onLongPress: () => showEntryActions(context, store, txn),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Spacing.md,
            Spacing.sm,
            Spacing.md,
            Spacing.sm,
          ),
          child: Row(
            children: [
              CategoryTile(category: c),
              const SizedBox(width: Spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      txn.note.isEmpty ? c.name : txn.note,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.title.copyWith(fontSize: 15),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${dayStr(txn.dateTime)} · ${c.name} · '
                      '${txn.mode.toUpperCase()}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.caption.copyWith(
                        fontSize: 12,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Spacing.sm),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 120),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: AmountText(
                    txn.amount,
                    type: txn.type,
                    style: AppType.amount.copyWith(fontSize: 14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 50dp floating Add pill, aligned with the right edge of the column.
  Widget _addPill(BuildContext context, AppColors colors) {
    return Semantics(
      button: true,
      label: 'Add expense',
      child: Material(
        color: colors.accent,
        borderRadius: Radii.pillRadius,
        elevation: 6,
        shadowColor: Colors.black.withValues(alpha: 0.35),
        child: InkWell(
          key: const Key('home-add'),
          borderRadius: Radii.pillRadius,
          onTap: () {
            Haptics.tap();
            widget.onAdd();
          },
          child: SizedBox(
            height: 50,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.xl),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add, size: 20, color: colors.onAccent),
                  const SizedBox(width: Spacing.sm),
                  Text(
                    'Add',
                    style: AppType.button.copyWith(color: colors.onAccent),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Tapping the month pops a calendar to jump timelines directly.
  Future<void> _pickMonth() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDate: _month,
      helpText: 'Jump to month',
    );
    if (picked != null && mounted) {
      setState(() => _month = DateTime(picked.year, picked.month));
    }
  }

  /// Pull-to-refresh anywhere on Home forces a sync cycle.
  Future<void> _doSync() async {
    final fn = widget.onSync;
    if (fn == null) return;
    final msg = await fn();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }
}
