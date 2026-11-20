import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:provider/provider.dart';

import '../app_dates.dart';
import '../receipts.dart';
import '../format.dart';
import '../store.dart';
import '../sync/file_sync.dart';
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
import '../widgets/event_share.dart';
import '../widgets/page.dart'
    show kPageMaxWidth, oneHandedBottomPadding, tabScrollBottomPadding;
import '../widgets/profile_avatar.dart';
import '../widgets/section_header.dart';
import '../widgets/segmented_tabs.dart';
import 'category_entries_screen.dart';

/// "Today"/"Yesterday" for recent days, otherwise a short weekday + date.
String _dayLabel(DateTime d) {
  final now = DateTime.now();
  if (DateUtils.isSameDay(d, now)) return 'Today';
  if (DateUtils.isSameDay(d, DateTime(now.year, now.month, now.day - 1))) {
    return 'Yesterday';
  }
  return appDayHead(d, sameYear: d.year == now.year);
}

/// Searchable history with type/category filters + CSV export.
/// A request to open History filtered to one day (the Home rhythm strip).
/// A notifier rather than an initial value because the shell keeps History
/// mounted in an IndexedStack across tab switches.
class HistoryDayRequest extends ChangeNotifier {
  DateTime? _day;
  DateTime? get day => _day;

  void open(DateTime day) {
    _day = DateTime(day.year, day.month, day.day);
    notifyListeners();
  }
}

class HistoryScreen extends StatefulWidget {
  /// Opens the Sync screen. Provided by the shell; standalone uses omit it.
  final VoidCallback? onOpenSync;

  /// Opens Settings from the small avatar in the title row.
  final VoidCallback? onOpenSettings;

  /// Fired when Home's rhythm strip asks for one day.
  final HistoryDayRequest? dayRequest;

  const HistoryScreen({
    super.key,
    this.onOpenSync,
    this.onOpenSettings,
    this.dayRequest,
  });

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  static const _views = ['entries', 'cats', 'projects'];

  String _view = 'entries'; // entries | cats | projects
  String _query = '';
  String _type = 'all'; // all | expense | income
  String _cat = 'all';
  DateTime? _dayFilter;
  Timer? _debounce;
  bool _hasSearchText = false;

  /// Entries-list scroll position. Drives the slow collapse of the
  /// title + search + filters: scrolling down hands their space to history.
  final ScrollController _listCtrl = ScrollController();
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _dayFilter = widget.dayRequest?.day;
    widget.dayRequest?.addListener(_applyDayRequest);
  }

  @override
  void didUpdateWidget(covariant HistoryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dayRequest != widget.dayRequest) {
      oldWidget.dayRequest?.removeListener(_applyDayRequest);
      widget.dayRequest?.addListener(_applyDayRequest);
    }
  }

  /// A rhythm-bar tap lands here: clear search/filters first so the day is
  /// never hidden behind an old query, then show exactly that day.
  void _applyDayRequest() {
    final day = widget.dayRequest?.day;
    if (day == null || !mounted) return;
    _debounce?.cancel();
    setState(() {
      _view = 'entries';
      _query = '';
      _searchCtrl.clear();
      _hasSearchText = false;
      _type = 'all';
      _cat = 'all';
      _dayFilter = DateTime(day.year, day.month, day.day);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _listCtrl.hasClients) _listCtrl.jumpTo(0);
    });
  }

  @override
  void dispose() {
    widget.dayRequest?.removeListener(_applyDayRequest);
    _debounce?.cancel();
    _listCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  /// 0 (fully shown) to 1 (fully hidden) across the first ~220 px of
  /// list scroll. Linear on purpose: the top area melts away steadily
  /// with the finger, not in a snap.
  double _collapseT() {
    if (_view != 'entries') return 0;
    final off = _listCtrl.hasClients ? _listCtrl.offset : 0.0;
    return (off / 220).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ExpenseStore>();
    final colors = AppColors.of(context);
    final filtered = _view == 'entries' ? _filtered(store) : const <Txn>[];

    return LayoutBuilder(
      builder: (context, constraints) {
        // Local 20dp phone margin, centred and capped at 880dp, measured
        // from the body width so the shell's NavigationRail does not shift
        // the column on desktop.
        final hPad = math.max(
          Spacing.screen,
          (constraints.maxWidth - kPageMaxWidth) / 2,
        );

        return Padding(
          padding: EdgeInsets.symmetric(horizontal: hPad),
          child: Column(
            children: [
              _collapsible(_titleBlock(colors, store, filtered)),
              if (!store.oneHanded) _segmented(),
              if (_view == 'entries') ...[
                _collapsible(_searchAndFilters(colors, store)),
                Expanded(
                  child: _viewTransition(_entriesBody(colors, store, filtered)),
                ),
              ] else
                Expanded(
                  child: _viewTransition(
                    _view == 'cats'
                        ? _categoriesBody(colors, store)
                        : _projectsBody(colors, store),
                  ),
                ),
              if (store.oneHanded)
                Padding(
                  padding: EdgeInsets.only(
                    top: Spacing.sm,
                    bottom: oneHandedBottomPadding(context),
                  ),
                  child: _segmented(),
                ),
            ],
          ),
        );
      },
    );
  }

  // ---------- header ----------

  /// Large title block. Collapses with the search area on scroll, so only
  /// the segmented tabs stay pinned while a long history is being read.
  Widget _titleBlock(AppColors colors, ExpenseStore store, List<Txn> filtered) {
    return Padding(
      padding: const EdgeInsets.only(top: Spacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'History',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.largeTitle.copyWith(color: colors.textPrimary),
                ),
                const SizedBox(height: 2),
                Text(
                  _subtitle(store, filtered),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.caption.copyWith(color: colors.textSecondary),
                ),
              ],
            ),
          ),
          if (widget.onOpenSync != null)
            _headerAction(colors, Icons.sync, 'Sync', widget.onOpenSync),
          if (_view == 'entries') ...[
            _headerAction(
              colors,
              Icons.calendar_today_outlined,
              'Jump to date',
              () => _pickDay(context),
            ),
            _headerAction(
              colors,
              Icons.file_download_outlined,
              'Export CSV',
              filtered.isEmpty
                  ? null
                  : () => _exportCsv(context, store, filtered),
            ),
          ],
          SettingsAvatarButton(
            name: store.userName,
            onTap: widget.onOpenSettings,
          ),
        ],
      ),
    );
  }

  Widget _headerAction(
    AppColors colors,
    IconData icon,
    String tooltip,
    VoidCallback? onPressed,
  ) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      iconSize: 20,
      icon: Icon(
        icon,
        color: onPressed == null
            ? colors.textSecondary.withValues(alpha: 0.35)
            : colors.textSecondary,
      ),
    );
  }

  String _subtitle(ExpenseStore store, List<Txn> filtered) {
    if (_view == 'cats') {
      final n = store.categories.length;
      return '$n ${n == 1 ? 'category' : 'categories'}';
    }
    if (_view == 'projects') {
      final n = store.projects.length;
      return '$n ${n == 1 ? 'event' : 'events'}';
    }
    final total = store.transactions.length;
    final n = filtered.length;
    final filtering =
        _query.isNotEmpty ||
        _type != 'all' ||
        _cat != 'all' ||
        _dayFilter != null;
    if (filtering) {
      return '$n of $total ${total == 1 ? 'entry' : 'entries'}';
    }
    return '$n ${n == 1 ? 'entry' : 'entries'}';
  }

  Widget _segmented() {
    return Padding(
      padding: const EdgeInsets.only(top: Spacing.md, bottom: Spacing.md),
      child: SegmentedTabs(
        labels: const ['Entries', 'Categories', 'Events'],
        selectedIndex: _views.indexOf(_view),
        onChanged: (i) => _setView(_views[i]),
      ),
    );
  }

  void _setView(String view) {
    if (_view == view) return;
    FocusScope.of(context).unfocus();
    if (_listCtrl.hasClients) _listCtrl.jumpTo(0);
    setState(() => _view = view);
  }

  /// Fades and shrinks a header block away as the list scrolls.
  Widget _collapsible(Widget child) {
    return AnimatedBuilder(
      animation: _listCtrl,
      child: child,
      builder: (context, child) {
        final t = _collapseT();
        if (t <= 0) return child!;
        return IgnorePointer(
          ignoring: t > 0.5,
          child: Opacity(
            opacity: 1 - t,
            // ClipRect matters: Align's heightFactor shrinks the box but
            // the child keeps painting past it, which would ghost the
            // header behind the list rows.
            child: ClipRect(
              child: Align(
                alignment: Alignment.topCenter,
                heightFactor: 1 - t,
                child: child,
              ),
            ),
          ),
        );
      },
    );
  }

  // ---------- search + filters ----------

  Widget _searchAndFilters(AppColors colors, ExpenseStore store) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const Key('history-search'),
            controller: _searchCtrl,
            style: AppType.body.copyWith(
              fontSize: 14,
              color: colors.textPrimary,
            ),
            textInputAction: TextInputAction.search,
            onChanged: _onSearchChanged,
            decoration: InputDecoration(
              hintText: 'Search notes, categories, modes',
              hintStyle: AppType.body.copyWith(
                fontSize: 14,
                color: colors.textSecondary,
              ),
              prefixIcon: Icon(
                Icons.search,
                size: 20,
                color: colors.textSecondary,
              ),
              prefixIconConstraints: const BoxConstraints(
                minWidth: 44,
                minHeight: 44,
              ),
              suffixIcon: _hasSearchText
                  ? IconButton(
                      tooltip: 'Clear search',
                      onPressed: _clearQuery,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 44,
                        minHeight: 44,
                      ),
                      icon: Icon(
                        Icons.close,
                        size: 18,
                        color: colors.textSecondary,
                      ),
                    )
                  : null,
              suffixIconConstraints: const BoxConstraints(
                minWidth: 44,
                minHeight: 44,
              ),
              filled: true,
              fillColor: colors.field,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: Spacing.md,
                vertical: Spacing.md,
              ),
              border: const OutlineInputBorder(
                borderRadius: Radii.fieldRadius,
                borderSide: BorderSide.none,
              ),
              enabledBorder: const OutlineInputBorder(
                borderRadius: Radii.fieldRadius,
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: Radii.fieldRadius,
                borderSide: BorderSide(
                  color: colors.accent.withValues(alpha: 0.55),
                ),
              ),
            ),
          ),
          const SizedBox(height: Spacing.sm),
          _filterRow(colors, store),
        ],
      ),
    );
  }

  void _onSearchChanged(String value) {
    final hasText = value.isNotEmpty;
    if (hasText != _hasSearchText) {
      setState(() => _hasSearchText = hasText);
    }
    // Debounced: keeps long histories smooth while typing.
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _query = value);
    });
  }

  void _clearQuery() {
    _debounce?.cancel();
    _searchCtrl.clear();
    setState(() {
      _query = '';
      _hasSearchText = false;
    });
  }

  void _clearAll() {
    _debounce?.cancel();
    _searchCtrl.clear();
    FocusScope.of(context).unfocus();
    setState(() {
      _query = '';
      _hasSearchText = false;
      _type = 'all';
      _cat = 'all';
      _dayFilter = null;
    });
  }

  Widget _filterRow(AppColors colors, ExpenseStore store) {
    final hasFilters = _type != 'all' || _cat != 'all' || _dayFilter != null;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _FilterPill(
            label: 'All',
            selected: _type == 'all' && _cat == 'all',
            onTap: () {
              Haptics.selection();
              setState(() {
                _type = 'all';
                _cat = 'all';
              });
            },
          ),
          const SizedBox(width: Spacing.sm),
          _FilterPill(
            label: 'Expense',
            selected: _type == 'expense',
            onTap: () {
              Haptics.selection();
              setState(() => _type = 'expense');
            },
          ),
          const SizedBox(width: Spacing.sm),
          _FilterPill(
            label: 'Income',
            selected: _type == 'income',
            onTap: () {
              Haptics.selection();
              setState(() => _type = 'income');
            },
          ),
          const SizedBox(width: Spacing.sm),
          PopupMenuButton<String>(
            tooltip: 'Filter by category',
            padding: EdgeInsets.zero,
            initialValue: _cat,
            onSelected: (value) {
              Haptics.selection();
              setState(() => _cat = value);
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'all', child: Text('All categories')),
              for (final c in store.categories)
                PopupMenuItem(value: c.id, child: Text(c.name)),
            ],
            child: _FilterPill(
              label: _cat == 'all' ? 'Category' : store.categoryOf(_cat).name,
              icon: Icons.category_outlined,
              trailingIcon: Icons.expand_more,
              selected: _cat != 'all',
            ),
          ),
          if (_dayFilter != null) ...[
            const SizedBox(width: Spacing.sm),
            _FilterPill(
              label: dayStr(_dayFilter!),
              icon: Icons.event_outlined,
              trailingIcon: Icons.close,
              selected: true,
              semanticsLabel: 'Clear date filter',
              onTap: () {
                Haptics.selection();
                setState(() => _dayFilter = null);
              },
            ),
          ],
          if (hasFilters || _query.isNotEmpty) ...[
            const SizedBox(width: Spacing.xs),
            TextButton(
              onPressed: _clearAll,
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 34),
                padding: const EdgeInsets.symmetric(horizontal: Spacing.sm),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: AppType.caption.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: const Text('Clear'),
            ),
          ],
        ],
      ),
    );
  }

  // ---------- entries ----------

  List<Txn> _filtered(ExpenseStore store) {
    final q = _query.toLowerCase();
    return store.transactions
        .where((t) {
          if (_type != 'all' && t.type != _type) return false;
          if (_cat != 'all' && t.categoryId != _cat) return false;
          if (_dayFilter != null) {
            final d = t.dateTime;
            final f = _dayFilter!;
            if (d.year != f.year || d.month != f.month || d.day != f.day) {
              return false;
            }
          }
          if (q.isNotEmpty) {
            final c = store.categoryOf(t.categoryId).name.toLowerCase();
            final account = store.accountName(t.effectiveAccountId);
            if (!t.note.toLowerCase().contains(q) &&
                !c.contains(q) &&
                !t.mode.contains(q) &&
                !account.toLowerCase().contains(q)) {
              return false;
            }
          }
          return true;
        })
        .toList(growable: false);
  }

  /// Event-tagged entries collect under one collapsible branch per event,
  /// placed at that event's newest entry position; untagged entries stay
  /// chronological.
  List<Object> _displayItems(ExpenseStore store, List<Txn> filtered) {
    final byProject = <String, List<Txn>>{};
    for (final t in filtered) {
      if (t.projectId.isEmpty) continue;
      (byProject[t.projectId] ??= []).add(t);
    }

    final display = <Object>[];
    final seen = <String>{};
    for (final t in filtered) {
      if (t.projectId.isEmpty) {
        display.add(t);
        continue;
      }
      final p = store.projectOf(t.projectId);
      if (p.id.isEmpty) {
        display.add(t);
        continue;
      }
      if (seen.add(t.projectId)) {
        display.add((p, byProject[t.projectId]!));
      }
    }
    return display;
  }

  /// Buckets display items by the day of their newest entry. Map insertion
  /// order follows the store's newest-first transaction order, so days stay
  /// newest first without a second sort.
  List<_DayGroup> _dayGroups(ExpenseStore store, List<Txn> filtered) {
    final byDay = <String, _DayGroup>{};
    for (final item in _displayItems(store, filtered)) {
      final d = item is Txn
          ? item.dateTime
          : (item as (Project, List<Txn>)).$2.first.dateTime;
      final key = '${d.year}-${d.month}-${d.day}';
      final group = byDay.putIfAbsent(
        key,
        () => _DayGroup(DateTime(d.year, d.month, d.day)),
      );
      group.items.add(item);
    }
    return byDay.values.toList(growable: false);
  }

  Widget _entriesBody(
    AppColors colors,
    ExpenseStore store,
    List<Txn> filtered,
  ) {
    if (filtered.isEmpty) return _entriesEmpty(store);

    final days = _dayGroups(store, filtered);
    return ListView.builder(
      key: const PageStorageKey('history-entries'),
      controller: _listCtrl,
      padding: EdgeInsets.only(
        top: Spacing.xs,
        bottom: tabScrollBottomPadding(context),
      ),
      itemCount: days.length,
      itemBuilder: (context, i) =>
          _daySection(colors, store, days[i], first: i == 0),
    );
  }

  Widget _entriesEmpty(ExpenseStore store) {
    final filtering =
        _query.isNotEmpty ||
        _type != 'all' ||
        _cat != 'all' ||
        _dayFilter != null;
    if (store.transactions.isEmpty && !filtering) {
      return const EmptyState(
        icon: Icons.receipt_long_outlined,
        message: 'No entries yet. Add one from Home.',
        padding: EdgeInsets.symmetric(vertical: Spacing.xxl),
      );
    }
    return EmptyState(
      icon: Icons.search_off,
      message: 'Nothing found.',
      actionLabel: 'Clear filters',
      onAction: _clearAll,
      padding: const EdgeInsets.symmetric(vertical: Spacing.xxl),
    );
  }

  Widget _daySection(
    AppColors colors,
    ExpenseStore store,
    _DayGroup day, {
    required bool first,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            Spacing.xs,
            first ? Spacing.xs : Spacing.xl,
            Spacing.xs,
            Spacing.sm,
          ),
          child: Text(
            _dayLabel(day.date),
            style: AppType.captionStrong.copyWith(
              fontSize: 12,
              letterSpacing: 0.5,
              color: colors.textSecondary,
            ),
          ),
        ),
        AppCard.group(
          children: [
            for (final item in day.items)
              if (item is Txn)
                _entryRow(colors, store, item)
              else
                _eventGroup(store, item as (Project, List<Txn>)),
          ],
        ),
      ],
    );
  }

  Widget _eventGroup(ExpenseStore store, (Project, List<Txn>) group) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.xs,
        vertical: Spacing.xs,
      ),
      child: EventBranchGroup(
        key: ValueKey('evt-${group.$1.id}'),
        store: store,
        project: group.$1,
        txns: group.$2,
      ),
    );
  }

  Widget _entryRow(AppColors colors, ExpenseStore store, Txn txn) {
    final c = store.categoryOf(txn.categoryId);
    final title = txn.note.isEmpty ? c.name : txn.note;
    final account = store.accountName(txn.effectiveAccountId);
    final subtitle = txn.note.isEmpty ? account : '${c.name} · $account';
    final receiptMark = FutureBuilder<bool>(
      future: ReceiptStore.create().then((s) => s.hasFor(txn.id)),
      builder: (context, snap) => snap.data == true
          ? Padding(
              padding: const EdgeInsets.only(left: Spacing.xs),
              child: Icon(Icons.attach_file, size: 14, color: colors.textSecondary),
            )
          : const SizedBox.shrink(),
    );

    return Slidable(
      key: ValueKey(txn.id),
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
            Spacing.lg,
            Spacing.md,
            Spacing.lg,
            Spacing.md,
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
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.title.copyWith(fontSize: 15),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppType.caption.copyWith(
                              fontSize: 12,
                              color: colors.textSecondary,
                            ),
                          ),
                        ),
                        receiptMark,
                      ],
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

  // ---------- categories ----------

  Widget _categoriesBody(AppColors colors, ExpenseStore store) {
    final month = store.monthly(DateTime.now()).byCategory;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: Spacing.xs),
          child: SectionHeader(
            'Categories & budgets',
            trailing: TextButton.icon(
              onPressed: () => _addCategoryDialog(context, store),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('New'),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 2, bottom: Spacing.md),
          child: Text(
            'Tap a category for its history. Drag the handle to reorder.',
            style: AppType.caption.copyWith(color: colors.textSecondary),
          ),
        ),
        Expanded(
          child: store.categories.isEmpty
              ? EmptyState(
                  icon: Icons.category_outlined,
                  message: 'No categories yet.',
                  actionLabel: 'Add category',
                  onAction: () => _addCategoryDialog(context, store),
                )
              : ReorderableListView.builder(
                  buildDefaultDragHandles: false,
                  padding: EdgeInsets.only(
                    bottom: tabScrollBottomPadding(context),
                  ),
                  itemCount: store.categories.length,
                  onReorderItem: (oldI, newI) async {
                    await store.moveCategoryTo(store.categories[oldI].id, newI);
                  },
                  proxyDecorator: (child, index, animation) {
                    return AnimatedBuilder(
                      animation: animation,
                      builder: (context, _) {
                        final lift = Curves.easeOut.transform(animation.value);
                        return Transform.scale(
                          scale: 1 + 0.015 * lift,
                          child: Material(
                            color: Colors.transparent,
                            child: child,
                          ),
                        );
                      },
                      child: child,
                    );
                  },
                  itemBuilder: (context, i) {
                    final c = store.categories[i];
                    return _categoryCard(
                      colors,
                      store,
                      c,
                      spent: month[c.id] ?? 0,
                      index: i,
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _categoryCard(
    AppColors colors,
    ExpenseStore store,
    Category category, {
    required double spent,
    required int index,
  }) {
    final over = category.budget > 0 && spent > category.budget;
    final budget = category.budget > 0
        ? 'Budget ${money(category.budget)}'
        : 'No budget';
    return Padding(
      key: ValueKey(category.id),
      padding: const EdgeInsets.only(bottom: Spacing.sm),
      child: AppCard(
        padding: EdgeInsets.zero,
        child: InkWell(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => CategoryEntriesScreen(category: category),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              Spacing.md,
              Spacing.sm,
              Spacing.xs,
              Spacing.sm,
            ),
            child: Row(
              children: [
                CategoryTile(category: category, size: 34, iconSize: 18),
                const SizedBox(width: Spacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        category.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.title.copyWith(fontSize: 15),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${money(spent)} spent · $budget',
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
                IconButton(
                  tooltip: 'Customize',
                  onPressed: () => _customizeCategory(context, store, category),
                  icon: Icon(
                    Icons.edit_outlined,
                    size: 18,
                    color: colors.textSecondary,
                  ),
                ),
                ReorderableDragStartListener(
                  index: index,
                  child: Padding(
                    padding: const EdgeInsets.all(Spacing.md),
                    child: Icon(
                      Icons.drag_handle,
                      size: 20,
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------- events ----------

  Widget _projectsBody(AppColors colors, ExpenseStore store) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: Spacing.xs),
          child: SectionHeader(
            'Events',
            trailing: TextButton.icon(
              onPressed: () => _addProjectDialog(context, store),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('New'),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 2, bottom: Spacing.md),
          child: Text(
            'Shared spending for trips, outings and flatmates.',
            style: AppType.caption.copyWith(color: colors.textSecondary),
          ),
        ),
        Expanded(
          child: store.projects.isEmpty
              ? EmptyState(
                  icon: Icons.event_outlined,
                  message: 'No events yet.',
                  actionLabel: 'New event',
                  onAction: () => _addProjectDialog(context, store),
                )
              : ListView.builder(
                  padding: EdgeInsets.only(
                    bottom: tabScrollBottomPadding(context),
                  ),
                  itemCount: store.projects.length,
                  itemBuilder: (context, i) {
                    final p = store.projects[i];
                    final txns = store.projectTxns(p.id).toList()
                      ..sort((a, b) => b.date.compareTo(a.date));
                    return _eventCard(colors, store, p, txns);
                  },
                ),
        ),
      ],
    );
  }

  Widget _eventCard(
    AppColors colors,
    ExpenseStore store,
    Project project,
    List<Txn> txns,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.md),
      child: AppCard(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            EventBranchGroup(
              key: ValueKey('events-${project.id}'),
              store: store,
              project: project,
              txns: txns,
              initiallyExpanded: false,
            ),
            Divider(height: 1, thickness: 1, color: colors.hairline),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Spacing.sm,
                vertical: Spacing.xs,
              ),
              child: OverflowBar(
                alignment: MainAxisAlignment.end,
                spacing: Spacing.xs,
                overflowSpacing: 0,
                children: [
                  TextButton.icon(
                    onPressed: () => shareEventReport(context, store, project),
                    icon: const Icon(Icons.ios_share, size: 17),
                    label: const Text('Share'),
                  ),
                  TextButton.icon(
                    onPressed: () => _customizeProject(context, store, project),
                    icon: const Icon(Icons.edit_outlined, size: 17),
                    label: const Text('Edit'),
                  ),
                  TextButton.icon(
                    onPressed: () => _confirmDeleteProject(
                      context,
                      store,
                      project.id,
                      project.name,
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: colors.expense,
                    ),
                    icon: const Icon(Icons.delete_outline, size: 17),
                    label: const Text('Delete event'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- shared motion ----------

  /// A fresh view fades and rises into place when the tabs change. Keyed by
  /// view, so it never keeps the outgoing list (and its ScrollController)
  /// alive behind the new one.
  Widget _viewTransition(Widget child) {
    final duration = Motion.of(context, Motion.base);
    if (duration == Duration.zero) return child;
    return TweenAnimationBuilder<double>(
      key: ValueKey(_view),
      tween: Tween(begin: 0, end: 1),
      duration: duration,
      curve: Motion.ease,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, (1 - t) * 6),
          child: child,
        ),
      ),
      child: child,
    );
  }

  // ---------- actions ----------

  Future<void> _pickDay(BuildContext context) async {
    final picked = await showAppDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDate: _dayFilter ?? DateTime.now(),
    );
    if (picked != null && mounted) {
      setState(() => _dayFilter = picked);
    }
  }

  Future<void> _addProjectDialog(
    BuildContext context,
    ExpenseStore store,
  ) async {
    final name = TextEditingController();
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New event'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(
                labelText: 'Name (Trekking, Outing...)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: note,
              decoration: const InputDecoration(
                labelText: 'Note (optional)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (ok == true && name.text.trim().isNotEmpty) {
      await store.addProject(name.text.trim(), note.text.trim());
    }
  }

  Future<void> _customizeProject(
    BuildContext context,
    ExpenseStore store,
    Project p,
  ) async {
    final name = TextEditingController(text: p.name);
    final note = TextEditingController(text: p.note);
    var icon = p.icon;
    var color = p.color;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text('Edit ${p.name}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: note,
                  decoration: const InputDecoration(
                    labelText: 'Note (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                const Text('Icon'),
                const SizedBox(height: 4),
                GridView.count(
                  crossAxisCount: 6,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    for (final i in kIconChoices)
                      GestureDetector(
                        onTap: () => setD(() => icon = i.codePoint),
                        child: CircleAvatar(
                          backgroundColor: i.codePoint == icon
                              ? Theme.of(ctx).colorScheme.primaryContainer
                              : Colors.transparent,
                          child: Icon(
                            i,
                            color: i.codePoint == icon
                                ? Theme.of(ctx).colorScheme.onPrimaryContainer
                                : null,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text('Colour'),
                const SizedBox(height: 4),
                GridView.count(
                  crossAxisCount: 6,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  children: [
                    for (final v in kColorChoices)
                      GestureDetector(
                        onTap: () => setD(() => color = v),
                        child: Container(
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
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (ok == true && context.mounted) {
      await store.updateProject(
        p.id,
        name: name.text,
        note: note.text,
        icon: icon,
        color: color,
      );
    }
  }

  Future<void> _confirmDeleteProject(
    BuildContext context,
    ExpenseStore store,
    String id,
    String name,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "$name"?'),
        content: const Text('Its entries stay in History, just untagged.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) await store.deleteProject(id);
  }

  /// Rename, budget, icon and color for a category - plus delete
  /// (its entries move to Other; Other itself cannot go).
  Future<void> _customizeCategory(
    BuildContext context,
    ExpenseStore store,
    Category c,
  ) async {
    final name = TextEditingController(text: c.name);
    final budget = TextEditingController(
      text: c.budget > 0 ? c.budget.toStringAsFixed(0) : '',
    );
    var icon = c.icon;
    var color = c.color;
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text('Edit ${c.name}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: budget,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Monthly budget (0 = none)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                const Text('Icon'),
                const SizedBox(height: 4),
                GridView.count(
                  crossAxisCount: 6,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    for (final i in kIconChoices)
                      GestureDetector(
                        onTap: () => setD(() => icon = i.codePoint),
                        child: CircleAvatar(
                          backgroundColor: i.codePoint == icon
                              ? Theme.of(ctx).colorScheme.primaryContainer
                              : Colors.transparent,
                          child: Icon(
                            i,
                            color: i.codePoint == icon
                                ? Theme.of(ctx).colorScheme.onPrimaryContainer
                                : null,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text('Colour'),
                const SizedBox(height: 4),
                GridView.count(
                  crossAxisCount: 6,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  children: [
                    for (final v in kColorChoices)
                      GestureDetector(
                        onTap: () => setD(() => color = v),
                        child: Container(
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
              ],
            ),
          ),
          actions: [
            if (c.id != 'other')
              TextButton(
                onPressed: () => Navigator.of(ctx).pop('delete'),
                child: Text(
                  'Delete',
                  style: TextStyle(color: Theme.of(ctx).colorScheme.error),
                ),
              ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop('save'),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (action == null || !context.mounted) return;
    if (action == 'delete') {
      final used = store.transactions.where((t) => t.categoryId == c.id).length;
      final yes = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Delete "${c.name}"?'),
          content: Text(
            used == 0
                ? 'It is not used anywhere.'
                : '$used entr${used == 1 ? 'y moves' : 'ies move'} to Other.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Keep'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
      if (yes == true && context.mounted) {
        await store.deleteCategory(c.id);
      }
      return;
    }
    final b = double.tryParse(budget.text.trim().replaceAll(',', '')) ?? 0;
    await store.updateCategory(
      c.id,
      name: name.text,
      icon: icon,
      color: color,
      budget: b < 0 ? 0 : b,
    );
  }

  Future<void> _addCategoryDialog(
    BuildContext context,
    ExpenseStore store,
  ) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New category'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (ok == true && ctrl.text.trim().isNotEmpty) {
      await store.addCategory(ctrl.text.trim());
    }
  }

  Future<void> _exportCsv(
    BuildContext context,
    ExpenseStore store,
    List<Txn> txns,
  ) async {
    final csv = FileSync.buildCsv(
      (id) => store.categoryOf(id).name,
      txns,
      accountName: (t) => store.accountName(t.effectiveAccountId),
    );
    final now = DateTime.now();
    await FileSync.exportJson(
      context,
      csv,
      'expense-${now.year}-${now.month}.csv',
    );
  }
}

/// One day's rows in the entries list.
class _DayGroup {
  final DateTime date;
  final List<Object> items = [];

  _DayGroup(this.date);
}

/// Quiet rounded filter chip used by the History filter row.
class _FilterPill extends StatelessWidget {
  final String label;
  final IconData? icon;
  final IconData? trailingIcon;
  final bool selected;
  final VoidCallback? onTap;
  final String? semanticsLabel;

  const _FilterPill({
    required this.label,
    this.icon,
    this.trailingIcon,
    this.selected = false,
    this.onTap,
    this.semanticsLabel,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final fg = selected ? colors.textPrimary : colors.textSecondary;
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: 7),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: fg),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            maxLines: 1,
            style: AppType.caption.copyWith(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: fg,
            ),
          ),
          if (trailingIcon != null) ...[
            const SizedBox(width: 4),
            Icon(trailingIcon, size: 15, color: fg),
          ],
        ],
      ),
    );

    final pill = Material(
      color: selected ? colors.selectedFill : Colors.transparent,
      shape: StadiumBorder(
        side: BorderSide(color: selected ? colors.cardBorder : colors.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: onTap == null ? content : InkWell(onTap: onTap, child: content),
    );
    if (semanticsLabel == null) return pill;
    return Semantics(
      button: true,
      selected: selected,
      label: semanticsLabel,
      child: pill,
    );
  }
}
