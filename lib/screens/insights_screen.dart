import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../analytics.dart';
import '../app_dates.dart';
import '../format.dart';
import '../insights.dart';
import '../store.dart';
import '../theme/haptics.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import '../widgets/app_card.dart';
import '../widgets/category_tile.dart';
import '../widgets/empty_state.dart';
import '../widgets/entry_actions.dart';
import '../widgets/page.dart'
    show kPageMaxWidth, oneHandedBottomPadding, tabScrollBottomPadding;
import '../widgets/profile_avatar.dart';
import '../widgets/section_header.dart';
import '../widgets/segmented_tabs.dart';

/// Insights: a calm read on the trailing month, 3, 6 or 12 months.
/// All maths comes from [ExpenseStore.insights], which memoizes by data
/// revision and period; this screen only formats and arranges it.
class InsightsScreen extends StatefulWidget {
  final VoidCallback? onOpenSettings;

  /// Opens History filtered to the tapped account ("How you pay" legend).
  final ValueChanged<String>? onOpenAccount;

  const InsightsScreen({
    super.key,
    this.onOpenSettings,
    this.onOpenAccount,
  });

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  InsightPeriod _period = InsightPeriod.month;
  List<InsightPeriod> _periods = InsightPeriod.values;

  void _setPeriod(int index) {
    if (index < 0 || index >= _periods.length) return;
    final next = _periods[index];
    if (next == _period) return;
    setState(() => _period = next);
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ExpenseStore>();
    final colors = AppColors.of(context);
    final now = DateTime.now();
    _periods = [
      for (final p in InsightPeriod.values)
        if (p != InsightPeriod.fiscal || appFiscalSupported(now)) p,
    ];
    final data = store.insights(_period);
    final pay = store.howYouPay(_period);
    final projected = projectInsightsEndSpend(data);
    final top = data.topExpenses;

    return LayoutBuilder(
      builder: (context, constraints) {
        final hPad = math.max(
          Spacing.screen,
          (constraints.maxWidth - kPageMaxWidth) / 2,
        );
        return CustomScrollView(
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(hPad, Spacing.sm, hPad, 0),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _header(colors, store),
                    const SizedBox(height: Spacing.lg),
                    if (!store.oneHanded) _periodTabs(colors),
                    if (_period == InsightPeriod.fiscal)
                      Padding(
                        padding: const EdgeInsets.only(top: Spacing.sm),
                        child: Text(
                          appFiscalRange(appCalendar.fiscalYearOf(now)),
                          style: AppType.caption.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                      ),
                    const SizedBox(height: Spacing.lg),
                    if (data.txnCount == 0)
                      AppCard(
                        child: EmptyState(
                          icon: Icons.query_stats,
                          message: 'No activity in this period.',
                        ),
                      )
                    else ...[
                      _summaryCard(colors, data),
                      if (projected != null) ...[
                        const SizedBox(height: Spacing.lg),
                        _forecastCard(colors, projected),
                      ],
                      if (data.spend > 0) ...[
                        const SizedBox(height: Spacing.xl),
                        const SectionHeader('Where it went'),
                        const SizedBox(height: Spacing.sm),
                        _categoryCard(context, colors, store, data),
                        if (pay.total > 0 && pay.slices.isNotEmpty) ...[
                          const SizedBox(height: Spacing.xl),
                          const SectionHeader('How you pay'),
                          const SizedBox(height: Spacing.sm),
                          _howYouPayCard(colors, pay),
                        ],
                        const SizedBox(height: Spacing.xl),
                        const SectionHeader('Monthly rhythm'),
                        const SizedBox(height: Spacing.sm),
                        _trendCard(colors, data),
                      ] else ...[
                        const SizedBox(height: Spacing.lg),
                        AppCard(
                          child: EmptyState(
                            icon: Icons.pie_chart_outline,
                            message: 'No spending in this period.',
                          ),
                        ),
                      ],
                    ],
                    const SizedBox(height: Spacing.xl),
                    SectionHeader(
                      'Money on loan',
                      trailing: Text(
                        'Now',
                        style: AppType.caption.copyWith(
                          fontSize: 12,
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(height: Spacing.sm),
                    _loanCard(colors, store),
                    const SizedBox(height: Spacing.xs),
                    Text(
                      'Not counted as spending.',
                      style: AppType.caption.copyWith(
                        fontSize: 12,
                        color: colors.textSecondary,
                      ),
                    ),
                    if (top.isNotEmpty) ...[
                      const SizedBox(height: Spacing.xl),
                      const SectionHeader('Largest expenses'),
                      const SizedBox(height: Spacing.sm),
                    ],
                  ],
                ),
              ),
            ),
            if (top.isNotEmpty)
              SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: hPad),
                sliver: SliverList.builder(
                  itemCount: top.length,
                  itemBuilder: (context, i) {
                    return _expenseSurface(
                      colors,
                      first: i == 0,
                      last: i == top.length - 1,
                      child: _expenseRow(context, colors, store, top[i]),
                    );
                  },
                ),
              ),
            if (store.oneHanded)
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  hPad,
                  Spacing.sm,
                  hPad,
                  oneHandedBottomPadding(context),
                ),
                sliver: SliverToBoxAdapter(child: _periodTabs(colors)),
              )
            else
              SliverToBoxAdapter(
                child: SizedBox(height: tabScrollBottomPadding(context)),
              ),
          ],
        );
      },
    );
  }

  Widget _periodTabs(AppColors colors) {
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SegmentedTabs(
          labels: [for (final p in _periods) p.label],
          selectedIndex: _period.index,
          onChanged: _setPeriod,
        ),
      ),
    );
  }

  Widget _header(AppColors colors, ExpenseStore store) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Insights',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.largeTitle.copyWith(color: colors.textPrimary),
              ),
              const SizedBox(height: 2),
              Text(
                'Your money at a glance',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.caption.copyWith(color: colors.textSecondary),
              ),
            ],
          ),
        ),
        SettingsAvatarButton(
          name: store.userName,
          style: store.avatarStyle,
          onTap: widget.onOpenSettings,
        ),
      ],
    );
  }

  Widget _summaryCard(AppColors colors, InsightsAnalytics data) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _period.spentLabel,
            style: AppType.caption.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: Spacing.xs),
          Align(
            alignment: Alignment.centerLeft,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                money(data.spend),
                maxLines: 1,
                style: AppType.heroAmount.copyWith(color: colors.expense),
              ),
            ),
          ),
          const SizedBox(height: Spacing.sm),
          _comparison(colors, data),
          const SizedBox(height: Spacing.lg),
          Divider(height: 1, thickness: 1, color: colors.hairline),
          const SizedBox(height: Spacing.md),
          Row(
            children: [
              _miniStat(colors, 'Income', data.income, colors.income),
              _miniDivider(colors),
              _miniStat(
                colors,
                'Net',
                data.net,
                data.net < 0 ? colors.expense : colors.income,
              ),
              _miniDivider(colors),
              _miniStat(
                colors,
                'Daily average',
                data.averagePerDay,
                colors.textPrimary,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Small, quiet projection for the period that is still running.
  Widget _forecastCard(AppColors colors, double projected) {
    return AppCard(
      key: const Key('insights-forecast-card'),
      child: Row(
        children: [
          Icon(Icons.trending_up, size: 20, color: colors.accent),
          const SizedBox(width: Spacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Month-end forecast',
                  style: AppType.caption.copyWith(color: colors.textSecondary),
                ),
                const SizedBox(height: 2),
                Text(
                  money(projected),
                  maxLines: 1,
                  style: AppType.statValue.copyWith(fontSize: 20),
                ),
                Text(
                  'At the current daily pace',
                  style: AppType.caption.copyWith(
                    fontSize: 12,
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Account split of spend: one stacked bar plus a tappable inline legend.
  Widget _howYouPayCard(AppColors colors, HowYouPay pay) {
    final summary = pay.slices
        .take(3)
        .map((s) => '${s.label} ${_percent(s.amount, pay.total)}')
        .join(', ');
    return AppCard(
      key: const Key('insights-how-you-pay'),
      padding: const EdgeInsets.fromLTRB(
        Spacing.lg,
        Spacing.md,
        Spacing.lg,
        Spacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            label: 'How you pay. ${money(pay.total)} spent. $summary.',
            child: _payBar(colors, pay),
          ),
          const SizedBox(height: Spacing.md),
          for (final slice in pay.slices)
            _payLegendRow(colors, slice, pay.total),
        ],
      ),
    );
  }

  Widget _payBar(AppColors colors, HowYouPay pay) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: 8,
        child: Row(
          children: [
            for (var i = 0; i < pay.slices.length; i++) ...[
              if (i > 0) const SizedBox(width: 3),
              Expanded(
                flex: math.max(
                  1,
                  (pay.slices[i].amount / pay.total * 10000).round(),
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: _payColor(colors, pay.slices[i]),
                    borderRadius: BorderRadius.horizontal(
                      left: i == 0 ? const Radius.circular(4) : Radius.zero,
                      right: i == pay.slices.length - 1
                          ? const Radius.circular(4)
                          : Radius.zero,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Color _payColor(AppColors colors, PaymentSlice slice) =>
      slice.color == 0 ? colors.accent : Color(slice.color);

  Widget _payLegendRow(AppColors colors, PaymentSlice slice, double total) {
    final canOpen = slice.id != kOtherAccountsId && widget.onOpenAccount != null;
    return Semantics(
      button: canOpen,
      label: canOpen ? 'Show ${slice.label} entries in History' : null,
      child: InkWell(
        key: Key('insights-pay-${slice.id}'),
        onTap: canOpen
            ? () {
                Haptics.selection();
                widget.onOpenAccount!(slice.id);
              }
            : null,
        borderRadius: BorderRadius.circular(Radii.icon),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: _payColor(colors, slice),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  slice.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.body.copyWith(
                    fontSize: 14,
                    color: colors.textPrimary,
                  ),
                ),
              ),
              Text(
                _percent(slice.amount, total),
                style: AppType.caption.copyWith(
                  fontSize: 12,
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(width: Spacing.md),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 110),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    money(slice.amount),
                    maxLines: 1,
                    style: AppType.amount.copyWith(fontSize: 14),
                  ),
                ),
              ),
              if (canOpen) ...[
                const SizedBox(width: Spacing.xs),
                Icon(Icons.chevron_right, size: 16, color: colors.textSecondary),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _comparison(AppColors colors, InsightsAnalytics data) {
    if (data.spend <= 0) {
      return Text(
        'Nothing spent in this period.',
        style: AppType.caption.copyWith(color: colors.textSecondary),
      );
    }
    final change = data.spendChange;
    if (change == null) {
      return Text(
        'No previous spending to compare.',
        style: AppType.caption.copyWith(color: colors.textSecondary),
      );
    }
    final pct = change * 100;
    if (pct.abs() < 1) {
      return Text(
        'About the same as ${_period.compareLabel}.',
        style: AppType.caption.copyWith(color: colors.textSecondary),
      );
    }
    final less = pct < 0;
    final color = less ? colors.income : colors.expense;
    return Row(
      children: [
        Icon(
          less ? Icons.trending_down : Icons.trending_up,
          size: 16,
          color: color,
        ),
        const SizedBox(width: Spacing.xs),
        Flexible(
          child: Text(
            '${pct.abs().round()}% ${less ? 'less' : 'more'} '
            'than ${_period.compareLabel}',
            maxLines: 2,
            style: AppType.caption.copyWith(color: color),
          ),
        ),
      ],
    );
  }

  Widget _miniStat(AppColors colors, String label, double value, Color color) {
    return Expanded(
      child: Column(
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppType.caption.copyWith(
              fontSize: 11,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              money(value),
              maxLines: 1,
              style: AppType.statValue.copyWith(fontSize: 15, color: color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniDivider(AppColors colors) {
    return Container(width: 1, height: 28, color: colors.hairline);
  }

  Widget _categoryCard(
    BuildContext context,
    AppColors colors,
    ExpenseStore store,
    InsightsAnalytics data,
  ) {
    final entries = data.byCategory.entries.toList()
      ..sort((a, b) {
        final byValue = b.value.compareTo(a.value);
        return byValue != 0 ? byValue : a.key.compareTo(b.key);
      });

    final slices = <_RingSlice>[
      for (final e in entries.take(5))
        _RingSlice(
          label: store.categoryOf(e.key).name,
          value: e.value,
          color: store.categoryOf(e.key).colorValue,
        ),
    ];
    if (entries.length > 5) {
      final rest = entries.skip(5).fold<double>(0, (sum, e) => sum + e.value);
      slices.add(
        _RingSlice(
          label: '${entries.length - 5} smaller categories',
          value: rest,
          color: colors.textSecondary.withValues(alpha: 0.45),
        ),
      );
    }

    return AppCard(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 520;
          final ring = _ring(colors, data, slices);
          final legend = Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final slice in slices) _legendRow(colors, slice, data.spend),
            ],
          );
          if (!wide) {
            return Column(
              children: [
                ring,
                const SizedBox(height: Spacing.lg),
                legend,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ring,
              const SizedBox(width: Spacing.xl),
              Expanded(child: legend),
            ],
          );
        },
      ),
    );
  }

  Widget _ring(
    AppColors colors,
    InsightsAnalytics data,
    List<_RingSlice> slices,
  ) {
    final summary = slices
        .take(3)
        .map((s) => '${s.label} ${_percent(s.value, data.spend)}')
        .join(', ');
    return Semantics(
      label: 'Spending by category. ${money(data.spend)} spent. $summary.',
      child: ExcludeSemantics(
        child: SizedBox(
          width: 168,
          height: 168,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _RingPainter(slices: slices, track: colors.track),
                ),
              ),
              SizedBox(
                width: 106,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        money(data.spend),
                        maxLines: 1,
                        style: AppType.statValue.copyWith(fontSize: 20),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'spent',
                      style: AppType.caption.copyWith(
                        fontSize: 11,
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
    );
  }

  Widget _legendRow(AppColors colors, _RingSlice slice, double total) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
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
              slice.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.body.copyWith(
                fontSize: 14,
                color: colors.textPrimary,
              ),
            ),
          ),
          Text(
            _percent(slice.value, total),
            style: AppType.caption.copyWith(
              fontSize: 12,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(width: Spacing.md),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 110),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                money(slice.value),
                maxLines: 1,
                style: AppType.amount.copyWith(fontSize: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _trendCard(AppColors colors, InsightsAnalytics data) {
    final maxValue = data.trend.fold<double>(
      0,
      (max, month) => math.max(max, math.max(month.spend, month.income)),
    );
    var highest = data.trend.first;
    for (final month in data.trend) {
      if (month.spend > highest.spend) highest = month;
    }

    return AppCard(
      padding: const EdgeInsets.fromLTRB(
        Spacing.lg,
        Spacing.md,
        Spacing.lg,
        Spacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Income vs spending',
                  style: AppType.caption.copyWith(color: colors.textSecondary),
                ),
              ),
              Text(
                _period.trendMonths == 12 ? 'Last 12 months' : 'Last 6 months',
                style: AppType.caption.copyWith(color: colors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: Spacing.md),
          SizedBox(
            height: 128,
            child: Align(
              alignment: Alignment.center,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: _trendBars(colors, data, maxValue),
              ),
            ),
          ),
          const SizedBox(height: Spacing.sm),
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: colors.expense,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: Spacing.xs),
              Text(
                'Spent',
                style: AppType.caption.copyWith(
                  fontSize: 11,
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(width: Spacing.md),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: colors.income,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: Spacing.xs),
              Text(
                'Earned',
                style: AppType.caption.copyWith(
                  fontSize: 11,
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: Spacing.xs),
          Text(
            'Highest: ${money(highest.spend)} '
            '\u00B7 ${appTrendMonthShort(highest.month)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppType.caption.copyWith(
              fontSize: 12,
              color: colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _trendBars(AppColors colors, InsightsAnalytics data, double maxValue) {
    final currentIndex = data.trend.length - 1;
    return LayoutBuilder(
      builder: (context, constraints) {
        final barWidth = (constraints.maxWidth / data.trend.length * 0.20)
            .clamp(5.0, 12.0)
            .toDouble();

        Widget bar(double value, Color color) => Container(
          width: barWidth,
          height: maxValue <= 0
              ? 2.0
              : math.max(2.0, value / maxValue * 88),
          decoration: BoxDecoration(
            color: color,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(3),
            ),
          ),
        );

        return Semantics(
          container: true,
          label: 'Income versus spending by month',
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < data.trend.length; i++)
                Expanded(
                  child: Semantics(
                    label:
                        '${appTrendMonthFull(data.trend[i].month)}: '
                        'spent ${money(data.trend[i].spend)}, '
                        'earned ${money(data.trend[i].income)}',
                    child: ExcludeSemantics(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Align(
                              alignment: Alignment.bottomCenter,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  bar(
                                    data.trend[i].spend,
                                    i == currentIndex
                                        ? colors.expense
                                        : colors.expense
                                            .withValues(alpha: 0.35),
                                  ),
                                  const SizedBox(width: 3),
                                  bar(
                                    data.trend[i].income,
                                    i == currentIndex
                                        ? colors.income
                                        : colors.income
                                            .withValues(alpha: 0.35),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: Spacing.sm),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              appTrendMonthShort(data.trend[i].month),
                              maxLines: 1,
                              style: AppType.caption.copyWith(
                                fontSize: 10,
                                fontWeight: i == currentIndex
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: i == currentIndex
                                    ? colors.accent
                                    : colors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _loanCard(AppColors colors, ExpenseStore store) {
    return AppCard.group(
      children: [
        _loanRow(colors, 'To receive', store.pendingLoansTotal),
        _loanRow(colors, 'To return', store.pendingBorrowedTotal),
      ],
    );
  }

  Widget _loanRow(AppColors colors, String label, double value) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.lg,
        vertical: Spacing.md,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: AppType.body.copyWith(
                fontSize: 15,
                color: colors.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: Spacing.sm),
          Text(
            money(value),
            maxLines: 1,
            style: AppType.statValue.copyWith(fontSize: 15),
          ),
        ],
      ),
    );
  }

  Widget _expenseSurface(
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

  Widget _expenseRow(
    BuildContext context,
    AppColors colors,
    ExpenseStore store,
    Txn txn,
  ) {
    final category = store.categoryOf(txn.categoryId);
    return InkWell(
      key: Key('insights-expense-${txn.id}'),
      onTap: () => showEntryActions(context, store, txn),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Spacing.md,
          Spacing.sm,
          Spacing.md,
          Spacing.sm,
        ),
        child: Row(
          children: [
            CategoryTile(category: category),
            const SizedBox(width: Spacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    txn.note.isEmpty ? category.name : txn.note,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.title.copyWith(fontSize: 15),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${dayStr(txn.dateTime)} \u00B7 ${category.name}',
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
                child: Text(
                  money(txn.amount),
                  maxLines: 1,
                  style: AppType.amount.copyWith(
                    fontSize: 14,
                    color: colors.expense,
                  ),
                ),
              ),
            ),
          ],
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
}

class _RingSlice {
  final String label;
  final double value;
  final Color color;

  const _RingSlice({
    required this.label,
    required this.value,
    required this.color,
  });
}

class _RingPainter extends CustomPainter {
  static const _thickness = 14.0;
  static const _gap = 0.018;

  final List<_RingSlice> slices;
  final Color track;

  const _RingPainter({required this.slices, required this.track});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - _thickness / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = track
        ..style = PaintingStyle.stroke
        ..strokeWidth = _thickness,
    );

    final total = slices.fold<double>(0, (sum, slice) => sum + slice.value);
    if (total <= 0) return;

    final gap = slices.length > 1 ? _gap : 0.0;
    var start = -math.pi / 2;
    for (final slice in slices) {
      final sweep = slice.value / total * math.pi * 2;
      if (sweep > gap) {
        canvas.drawArc(
          rect,
          start + gap / 2,
          sweep - gap,
          false,
          Paint()
            ..color = slice.color
            ..style = PaintingStyle.stroke
            ..strokeWidth = _thickness,
        );
      }
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) {
    return oldDelegate.track != track || oldDelegate.slices != slices;
  }
}
