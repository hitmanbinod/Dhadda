import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:provider/provider.dart';

import '../analytics.dart';
import '../app_dates.dart';
import '../calendar/period.dart';
import '../format.dart';
import '../home_layout.dart';
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
import 'edit_home_screen.dart';

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

  /// Opens History filtered to one day (the rhythm strip).
  final ValueChanged<DateTime>? onOpenDay;

  const HomeScreen({
    super.key,
    required this.onAdd,
    this.onSync,
    this.onOpenSync,
    this.onOpenSettings,
    this.onSeeAll,
    this.onOpenDay,
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
  DateTime _month = appCalendar.periodOf(DateTime.now()).start;
  String? _spotlightId;
  String? _calendarId;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ExpenseStore>();
    if (!store.loaded) {
      return const Center(child: CircularProgressIndicator());
    }

    final colors = AppColors.of(context);
    final now = DateTime.now();
    // Switching AD/BS re-anchors the pager on today's period in that system.
    if (_calendarId != null && _calendarId != appCalendar.id) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _month = appCalendar.periodOf(DateTime.now()).start);
        }
      });
    }
    _calendarId = appCalendar.id;
    final fallback = appCalendar.isBs && !appCalendar.supports(_month);
    final cal = fallback ? const GregorianCalendarSystem() : appCalendar;
    final period = cal.periodOf(_month);
    final isCurrentMonth = period.contains(now);
    final hidden = store.hideBalance;
    final layout = store.homeLayout;
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

    // The optional rhythm/today sections need one pass over this month's
    // expenses. Other layouts keep the original single-pass analytics only.
    final days = period.daysInPeriod;
    final needsDaily = layout.any(
      (s) =>
          s.visible &&
          (s.section == HomeSection.rhythm ||
              s.section == HomeSection.todayRing),
    );
    final daily = List<double>.filled(days, 0);
    if (needsDaily) {
      for (final t in store.transactions) {
        if (!t.isExpense) continue;
        final d = t.dateTime;
        if (!period.contains(d)) continue;
        daily[period.dayIndex(d)] += t.amount;
      }
    }
    final todaySpend = isCurrentMonth ? daily[period.dayIndex(now)] : 0.0;
    final budgetTotal = budgets.fold<double>(0, (sum, c) => sum + c.budget);
    final dailyAllowance = budgetTotal > 0 ? budgetTotal / days : 0.0;
    final projected = projectPeriodEndSpend(spend, period);

    return LayoutBuilder(
      builder: (context, constraints) {
        // Local 20dp phone margin, centred and capped at 880dp. Computed
        // from the body's width (not the window) so the NavigationRail
        // does not shift the column on desktop.
        final hPad = math.max(
          Spacing.screen,
          (constraints.maxWidth - kPageMaxWidth) / 2,
        );

        final slivers = <Widget>[
          SliverPadding(
            padding: EdgeInsets.fromLTRB(hPad, Spacing.sm, hPad, 0),
            sliver: SliverToBoxAdapter(child: _header(context, store, colors)),
          ),
          if (fallback)
            SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: hPad),
              sliver: SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: Spacing.sm),
                  child: Text(
                    'Outside the BS table — showing Gregorian dates here.',
                    style: AppType.caption.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
        ];
        HomeSection? previous;

        void gap(double height) {
          if (height <= 0) return;
          slivers.add(SliverToBoxAdapter(child: SizedBox(height: height)));
        }

        void cardSection(Widget child) {
          slivers.add(
            SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: hPad),
              sliver: SliverToBoxAdapter(child: child),
            ),
          );
        }

        for (final setting in layout) {
          if (!setting.visible) continue;
          final section = setting.section;
          // Content-driven sections disappear cleanly when empty.
          if (section == HomeSection.budgets && budgets.isEmpty) continue;
          if (section == HomeSection.events && monthEvents.isEmpty) continue;

          if (section == HomeSection.stats) {
            if (previous != HomeSection.balance) gap(Spacing.xl);
          } else if (section != HomeSection.balance) {
            gap(Spacing.xl);
          }

          switch (section) {
            case HomeSection.balance:
              cardSection(_balanceHero(store, colors, balance));
              break;
            case HomeSection.stats:
              cardSection(
                _stats(
                  colors,
                  spend: spend,
                  income: income,
                  lent: store.pendingLoansTotal,
                  masked: hidden,
                ),
              );
              break;
            case HomeSection.categories:
              cardSection(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SectionHeader('By category'),
                    const SizedBox(height: Spacing.sm),
                    _categoriesCard(
                      context,
                      colors,
                      slices: slices,
                      spotlight: spotlight,
                      spend: spend,
                    ),
                  ],
                ),
              );
              break;
            case HomeSection.budgets:
              cardSection(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
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
                            masked: hidden,
                          ),
                      ],
                    ),
                  ],
                ),
              );
              break;
            case HomeSection.events:
              cardSection(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
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
                ),
              );
              break;
            case HomeSection.recent:
              slivers.add(
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(hPad, 0, hPad, Spacing.sm),
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
              );
              if (recent.isEmpty) {
                slivers.add(
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
                  ),
                );
              } else {
                slivers.add(
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
                          child: _recentRow(context, colors, store, recent[i]),
                        );
                      },
                    ),
                  ),
                );
              }
              break;
            case HomeSection.todayRing:
              cardSection(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SectionHeader('Today'),
                    const SizedBox(height: Spacing.sm),
                    _todayCard(
                      colors,
                      spendToday: todaySpend,
                      dailyAllowance: dailyAllowance,
                      currentMonth: isCurrentMonth,
                    ),
                  ],
                ),
              );
              break;
            case HomeSection.rhythm:
              cardSection(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SectionHeader('Daily rhythm'),
                    const SizedBox(height: Spacing.sm),
                    _rhythmCard(
                      context,
                      colors,
                      daily: daily,
                      month: _month,
                      spend: spend,
                      currentMonth: isCurrentMonth,
                    ),
                  ],
                ),
              );
              break;
            case HomeSection.forecast:
              cardSection(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SectionHeader('Forecast'),
                    const SizedBox(height: Spacing.sm),
                    _forecastCard(
                      colors,
                      month: _month,
                      spend: spend,
                      budgetTotal: budgetTotal,
                      projected: projected,
                      currentMonth: isCurrentMonth,
                    ),
                  ],
                ),
              );
              break;
          }
          previous = section;
        }

        slivers.add(
          SliverPadding(
            padding: EdgeInsets.fromLTRB(hPad, Spacing.xl, hPad, 0),
            sliver: SliverToBoxAdapter(
              child: Center(
                child: TextButton(
                  key: const Key('home-edit-layout'),
                  onPressed: _openEditHome,
                  child: const Text('Edit Home'),
                ),
              ),
            ),
          ),
        );
        slivers.add(
          SliverToBoxAdapter(
            child: SizedBox(height: tabScrollBottomPadding(context)),
          ),
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
                  slivers: slivers,
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

  void _openEditHome() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const EditHomeScreen()));
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
        Semantics(
          button: true,
          label: 'Choose month. Swipe left or right to browse months.',
          child: GestureDetector(
            key: const Key('home-month-title'),
            behavior: HitTestBehavior.opaque,
            onTap: _pickMonth,
            onHorizontalDragStart: _onMonthDragStart,
            onHorizontalDragUpdate: _onMonthDragUpdate,
            onHorizontalDragEnd: _onMonthDragEnd,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: _monthTitle(colors),
              ),
            ),
          ),
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
        key: const Key('home-month-label'),
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
      key: const Key('home-month-label'),
    );
  }

  Widget _balanceHero(ExpenseStore store, AppColors colors, double balance) {
    final hidden = store.hideBalance;
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
          Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      hidden ? hiddenMoney() : money(balance),
                      maxLines: 1,
                      style: AppType.heroAmount.copyWith(
                        color: hidden || balance >= 0
                            ? colors.textPrimary
                            : colors.expense,
                      ),
                    ),
                  ),
                ),
              ),
              IconButton(
                key: const Key('home-balance-eye'),
                tooltip: hidden ? 'Show balance' : 'Hide balance',
                onPressed: () {
                  Haptics.selection();
                  store.setHideBalance(!hidden);
                },
                icon: Icon(
                  hidden
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 22,
                  color: colors.textSecondary,
                ),
              ),
            ],
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
    required bool masked,
  }) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: Row(
        children: [
          _statCell(colors, 'Spent', spend, colors.expense, masked: masked),
          _statDivider(colors),
          _statCell(colors, 'Income', income, colors.income, masked: masked),
          _statDivider(colors),
          _statCell(
            colors,
            'Lent out',
            lent,
            colors.textPrimary,
            masked: masked,
          ),
        ],
      ),
    );
  }

  Widget _statCell(
    AppColors colors,
    String label,
    double value,
    Color color, {
    required bool masked,
  }) {
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
                masked ? hiddenMoney() : money(value),
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

  /// Today's spend against the daily slice of the total category budget.
  /// Quiet when there is no budget: the caption still names today's spend.
  Widget _todayCard(
    AppColors colors, {
    required double spendToday,
    required double dailyAllowance,
    required bool currentMonth,
  }) {
    if (!currentMonth) {
      return AppCard(
        key: const Key('home-today-card'),
        child: Row(
          children: [
            Icon(Icons.today_outlined, size: 22, color: colors.textSecondary),
            const SizedBox(width: Spacing.md),
            Expanded(
              child: Text(
                'Today only appears in the current month.',
                style: AppType.body.copyWith(
                  fontSize: 14,
                  color: colors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final hasBudget = dailyAllowance > 0;
    final ratio = hasBudget
        ? (spendToday / dailyAllowance).clamp(0.0, 1.0)
        : 0.0;
    final over = hasBudget && spendToday > dailyAllowance;
    final barColor = over ? colors.expense : colors.accent;
    final percent = hasBudget ? (spendToday / dailyAllowance * 100).round() : 0;
    final footnote = !hasBudget
        ? 'Today ${money(spendToday)}'
        : over
        ? '${money(spendToday - dailyAllowance)} over today'
        : '${money(dailyAllowance - spendToday)} left today';

    return AppCard(
      key: const Key('home-today-card'),
      child: Row(
        children: [
          Semantics(
            label: hasBudget
                ? 'Today ${money(spendToday)} of '
                      '${money(dailyAllowance)} daily allowance'
                : 'Today ${money(spendToday)}',
            child: ExcludeSemantics(
              child: SizedBox(
                width: 64,
                height: 64,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CustomPaint(
                      painter: _RingPainter(
                        progress: ratio,
                        color: barColor,
                        track: colors.track,
                      ),
                    ),
                    Center(
                      child: hasBudget
                          ? Text(
                              '$percent%',
                              style: AppType.captionStrong.copyWith(
                                fontSize: 12,
                                color: over
                                    ? colors.expense
                                    : colors.textPrimary,
                              ),
                            )
                          : Icon(
                              Icons.today_outlined,
                              size: 20,
                              color: colors.textSecondary,
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: Spacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Today',
                  style: AppType.caption.copyWith(color: colors.textSecondary),
                ),
                const SizedBox(height: 2),
                Text(
                  money(spendToday),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.sectionTitle.copyWith(
                    fontSize: 24,
                    fontFeatures: AppType.tabular,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  footnote,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.caption.copyWith(
                    fontSize: 12,
                    color: over ? colors.expense : colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// One thin bar per day. Heights use the 90th percentile so rent does not
  /// flatten the rest; coral marks days above twice the daily average.
  Widget _rhythmCard(
    BuildContext context,
    AppColors colors, {
    required List<double> daily,
    required DateTime month,
    required double spend,
    required bool currentMonth,
  }) {
    final days = daily.length;
    final now = DateTime.now();
    final todayIndex = currentMonth ? now.day - 1 : -1;
    final elapsed = currentMonth ? todayIndex + 1 : days;
    final average = elapsed > 0 ? spend / elapsed : 0.0;
    final positives = daily.where((v) => v > 0).toList()..sort();
    final p90 = positives.isEmpty
        ? 0.0
        : positives[((positives.length * 0.9).ceil() - 1).clamp(
            0,
            positives.length - 1,
          )];

    return AppCard(
      key: const Key('home-rhythm-card'),
      padding: const EdgeInsets.fromLTRB(
        Spacing.lg,
        Spacing.md,
        Spacing.lg,
        Spacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              return Semantics(
                label:
                    'Daily spending for ${monthStr(month)}. '
                    'Tap a bar to open that day in History.',
                child: GestureDetector(
                  key: const Key('home-rhythm-chart'),
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (details) {
                    if (widget.onOpenDay == null || constraints.maxWidth <= 0) {
                      return;
                    }
                    final index =
                        (details.localPosition.dx / constraints.maxWidth * days)
                            .floor()
                            .clamp(0, days - 1);
                    Haptics.selection();
                    widget.onOpenDay!(
                      DateTime(month.year, month.month, index + 1),
                    );
                  },
                  child: SizedBox(
                    height: 64,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (var i = 0; i < days; i++)
                          Expanded(
                            child: Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: days > 20 ? 1 : 2,
                              ),
                              child: Align(
                                alignment: Alignment.bottomCenter,
                                child: Container(
                                  height: _rhythmHeight(
                                    daily[i],
                                    p90,
                                    future: todayIndex >= 0 && i > todayIndex,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _rhythmColor(
                                      colors,
                                      daily[i],
                                      future: todayIndex >= 0 && i > todayIndex,
                                      today: i == todayIndex,
                                      over:
                                          average > 0 && daily[i] > average * 2,
                                    ),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: Spacing.sm),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Tap a day to open History',
                  style: AppType.caption.copyWith(
                    fontSize: 12,
                    color: colors.textSecondary,
                  ),
                ),
              ),
              Text(
                '1 – $days',
                style: AppType.caption.copyWith(
                  fontSize: 12,
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  double _rhythmHeight(double value, double p90, {required bool future}) {
    if (future || value <= 0 || p90 <= 0) return 3;
    return (value / p90).clamp(0.0, 1.0) * 52 + 4;
  }

  Color _rhythmColor(
    AppColors colors,
    double value, {
    required bool future,
    required bool today,
    required bool over,
  }) {
    if (future || value <= 0) return colors.track;
    if (over) return colors.expense;
    if (today) return colors.accent;
    return colors.textSecondary.withValues(alpha: 0.35);
  }

  /// Compact month-end projection; quiet before day five and on past months.
  Widget _forecastCard(
    AppColors colors, {
    required DateTime month,
    required double spend,
    required double budgetTotal,
    required double? projected,
    required bool currentMonth,
  }) {
    if (!currentMonth) {
      final now = DateTime.now();
      final past =
          month.year < now.year ||
          (month.year == now.year && month.month < now.month);
      return AppCard(
        key: const Key('home-forecast-card'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              past ? 'Month total' : 'Forecast',
              style: AppType.caption.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: Spacing.xs),
            Text(
              past ? money(spend) : 'Starts when the month does.',
              style: past
                  ? AppType.sectionTitle.copyWith(
                      fontSize: 24,
                      fontFeatures: AppType.tabular,
                      color: colors.textPrimary,
                    )
                  : AppType.body.copyWith(
                      fontSize: 14,
                      color: colors.textSecondary,
                    ),
            ),
            if (past) ...[
              const SizedBox(height: 2),
              Text(
                'Closed month',
                style: AppType.caption.copyWith(
                  fontSize: 12,
                  color: colors.textSecondary,
                ),
              ),
            ],
          ],
        ),
      );
    }

    if (projected == null) {
      return AppCard(
        key: const Key('home-forecast-card'),
        child: Text(
          'A forecast appears after five days.',
          style: AppType.body.copyWith(
            fontSize: 14,
            color: colors.textSecondary,
          ),
        ),
      );
    }

    final over = budgetTotal > 0 && projected > budgetTotal;
    final delta = (projected - budgetTotal).abs();
    final active = appCalendar.periodOf(month);
    final daysLeft =
        active.daysInPeriod - (active.dayIndex(DateTime.now()) + 1);
    final footnote = budgetTotal <= 0
        ? '$daysLeft days left at today’s pace'
        : over
        ? '${money(delta)} over budget at this pace'
        : '${money(delta)} under budget at this pace';

    return AppCard(
      key: const Key('home-forecast-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Projected month end',
            style: AppType.caption.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: Spacing.xs),
          Text(
            money(projected),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppType.sectionTitle.copyWith(
              fontSize: 24,
              fontFeatures: AppType.tabular,
              color: over ? colors.expense : colors.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            footnote,
            style: AppType.caption.copyWith(
              fontSize: 12,
              color: over ? colors.expense : colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _budgetRow(
    BuildContext context,
    AppColors colors,
    Category category,
    double used, {
    required bool masked,
  }) {
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
                          ? 'Over by ${masked ? hiddenMoney() : money(used - category.budget)}'
                          : '${masked ? hiddenMoney() : money(used)} of '
                                '${masked ? hiddenMoney() : money(category.budget)}',
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
                      '${store.accountName(txn.effectiveAccountId)}',
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

  /// Distance-based month paging: a slow swipe works as well as a fling,
  /// and a short tap still reaches the calendar.
  double _monthDragDx = 0;
  bool _monthSwiped = false;

  void _onMonthDragStart(DragStartDetails details) {
    _monthDragDx = 0;
    _monthSwiped = false;
  }

  void _onMonthDragUpdate(DragUpdateDetails details) {
    if (_monthSwiped) return;
    _monthDragDx += details.delta.dx;
    if (_monthDragDx.abs() < 56) return;
    _monthSwiped = true;
    Haptics.selection();
    setState(() {
      final cal = appCalendar.isBs && !appCalendar.supports(_month)
          ? const GregorianCalendarSystem()
          : appCalendar;
      final current = cal.periodOf(_month);
      _month = _monthDragDx < 0
          ? cal.next(current).start
          : cal.previous(current).start;
    });
  }

  void _onMonthDragEnd(DragEndDetails details) {
    _monthDragDx = 0;
    _monthSwiped = false;
  }

  /// Tapping the month pops a calendar to jump timelines directly.
  Future<void> _pickMonth() async {
    final picked = await showAppDatePicker(
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

/// A quiet two-arc ring for the Today card. The progress is already clamped
/// to 0..1; the track stays visible when there is no budget.
class _RingPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color track;

  const _RingPainter({
    required this.progress,
    required this.color,
    required this.track,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - 6) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final trackPaint = Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, trackPaint);
    if (progress <= 0) return;
    final arcPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, -math.pi / 2, progress * 2 * math.pi, false, arcPaint);
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.color != color ||
      oldDelegate.track != track;
}
