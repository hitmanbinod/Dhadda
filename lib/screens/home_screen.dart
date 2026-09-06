import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../format.dart';
import '../store.dart';
import '../widgets/entry_actions.dart';
import '../widgets/page.dart';

/// Dashboard: month totals, category chart, budgets, recent entries.
class HomeScreen extends StatefulWidget {
  final VoidCallback onAdd;
  final Future<String> Function()? onSync;
  const HomeScreen({super.key, required this.onAdd, this.onSync});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  int _touched = -1;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ExpenseStore>();
    if (!store.loaded) {
      return const Center(child: CircularProgressIndicator());
    }
    final spend = store.monthSpend(_month);
    final income = store.monthIncome(_month);
    final balance = income - spend;
    final byCat = store.spendByCategory(_month);
    final sorted = byCat.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = sorted.take(6).toList();
    final others =
        sorted.skip(6).fold(0.0, (sum, e) => sum + e.value);
    String? touchedName;
    double touchedValue = 0;
    if (_touched >= 0 && _touched < top.length) {
      touchedName = store.categoryOf(top[_touched].key).name;
      touchedValue = top[_touched].value;
    } else if (_touched == top.length && others > 0) {
      touchedName = 'Others';
      touchedValue = others;
    }

    return RefreshIndicator(
      onRefresh: _doSync,
      child: ListView(
      padding: pageInsets(context),
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'Previous month',
              onPressed: () => setState(() =>
                  _month = DateTime(_month.year, _month.month - 1)),
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: TextButton.icon(
                onPressed: _pickMonth,
                icon: const Icon(Icons.calendar_month),
                label: Text(monthStr(_month),
                    style:
                        Theme.of(context).textTheme.titleLarge),
              ),
            ),
            IconButton(
              tooltip: 'Next month',
              onPressed: () => setState(() =>
                  _month = DateTime(_month.year, _month.month + 1)),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (ctx, constraints) {
            final wide = constraints.maxWidth > 700;
            return GridView.count(
              crossAxisCount: wide ? 4 : 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: wide ? 1.7 : 1.9,
              children: [
                _stat(context, 'Spent', money(spend), Colors.red),
                _stat(context, 'Income', money(income),
                    Colors.green),
                _stat(context, 'Balance', money(balance),
                    balance < 0 ? Colors.red : Colors.blue),
                _stat(context, 'Lent out',
                    money(store.pendingLoansTotal), Colors.orange),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: widget.onAdd,
          icon: const Icon(Icons.add),
          label: const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child:
                Text('Add expense', style: TextStyle(fontSize: 16)),
          ),
          style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52)),
        ),
        const SizedBox(height: 20),
        Text('By category',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (top.isEmpty)
          const Card(
              child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No expenses this month yet.')))
        else
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  SizedBox(
                    height: 200,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        PieChart(
                          PieChartData(
                            sectionsSpace: 2,
                            centerSpaceRadius: 44,
                            pieTouchData: PieTouchData(
                              touchCallback: (event, resp) {
                                final idx = resp?.touchedSection
                                        ?.touchedSectionIndex ??
                                    -1;
                                if (event is FlLongPressStart ||
                                    event is FlLongPressMoveUpdate ||
                                    event is FlTapUpEvent) {
                                  if (idx != _touched) {
                                    setState(
                                        () => _touched = idx);
                                  }
                                } else if (event
                                    is FlLongPressEnd) {
                                  if (_touched != -1) {
                                    setState(
                                        () => _touched = -1);
                                  }
                                }
                              },
                            ),
                            sections: [
                              for (var i = 0;
                                  i < top.length;
                                  i++)
                                PieChartSectionData(
                                  value: top[i].value,
                                  color: store
                                      .categoryOf(top[i].key)
                                      .colorValue,
                                  title:
                                      '${(top[i].value / (spend == 0 ? 1 : spend) * 100).round()}%',
                                  radius:
                                      i == _touched ? 80 : 64,
                                  titleStyle: TextStyle(
                                      fontSize: i == _touched
                                          ? 15
                                          : 12,
                                      fontWeight:
                                          FontWeight.bold,
                                      color: Colors.white),
                                ),
                              if (others > 0)
                                PieChartSectionData(
                                  value: others,
                                  color: Colors.grey,
                                  title:
                                      '${(others / (spend == 0 ? 1 : spend) * 100).round()}%',
                                  radius: top.length == _touched
                                      ? 80
                                      : 64,
                                  titleStyle: TextStyle(
                                      fontSize:
                                          top.length == _touched
                                              ? 15
                                              : 12,
                                      fontWeight:
                                          FontWeight.bold,
                                      color: Colors.white),
                                ),
                            ],
                          ),
                        ),
                        if (touchedName != null)
                          IgnorePointer(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(touchedName,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(
                                            fontWeight:
                                                FontWeight
                                                    .bold)),
                                Text(money(touchedValue),
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Center(
                    child: Text('Long-press a slice for details',
                        style:
                            Theme.of(context).textTheme.bodySmall),
                  ),
                  const SizedBox(height: 8),
                  for (final e in top)
                    Padding(
                      padding:
                          const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          Icon(store.categoryOf(e.key).iconData,
                              size: 18,
                              color:
                                  store.categoryOf(e.key).colorValue),
                          const SizedBox(width: 8),
                          Expanded(
                              child: Text(
                                  store.categoryOf(e.key).name)),
                          Text(money(e.value),
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 20),
        Text('Budgets', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        ...store.categories.where((c) => c.budget > 0).map((c) {
          final used = byCat[c.id] ?? 0;
          final pct = (used / c.budget).clamp(0.0, 1.0);
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(c.name)),
                      Text('${money(used)} / ${money(c.budget)}',
                          style: TextStyle(
                              color: used > c.budget
                                  ? Colors.red
                                  : null)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  LinearProgressIndicator(
                    value: pct,
                    color: used > c.budget ? Colors.red : null,
                  ),
                ],
              ),
            ),
          );
        }),
        const SizedBox(height: 20),
        Text('Recent',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        ...store.transactions.take(8).map((t) {
          final c = store.categoryOf(t.categoryId);
          return ListTile(
            onLongPress: () =>
                showEntryActions(context, store, t),
            onTap: () =>
                showEntryActions(context, store, t),
            leading: CircleAvatar(
              backgroundColor: c.colorValue.withValues(alpha: 0.15),
              child: Icon(c.iconData, color: c.colorValue, size: 20),
            ),
            title: Text(t.note.isEmpty ? c.name : t.note),
            subtitle: Text(
                '${dayStr(t.dateTime)}  -  ${t.mode.toUpperCase()}'),
            trailing: Text(
              '${t.isExpense ? '-' : '+'}${money(t.amount)}',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: t.isExpense ? Colors.red : Colors.green),
            ),
          );
        }),
      ],
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
  Future<void> _doSync() async {    final fn = widget.onSync;
    if (fn == null) return;
    final msg = await fn();
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Widget _stat(
      BuildContext context, String label, String value, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value,
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(color: color)),
              ),
          ],
        ),
      ),
    );
  }
}
