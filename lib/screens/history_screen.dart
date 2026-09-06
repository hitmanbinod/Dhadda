import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:provider/provider.dart';

import '../format.dart';
import '../store.dart';
import '../sync/file_sync.dart';
import '../widgets/delete.dart';
import '../widgets/entry_actions.dart';
import '../widgets/glass.dart';
import '../widgets/page.dart';

/// Searchable history with type/category filters + CSV export.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  String _view = 'entries'; // entries | cats | projects
  String _query = '';
  DateTime? _dayFilter;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
  String _type = 'all'; // all | expense | income
  String _cat = 'all';

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ExpenseStore>();
    if (_view != 'entries') {
      return Padding(
        padding:
            EdgeInsets.symmetric(horizontal: pageGutter(context)),
        child: Column(
          children: [
            _segmented(),
            Expanded(
              child: _view == 'cats'
                  ? _categoriesBody(store)
                  : _projectsBody(store),
            ),
          ],
        ),
      );
    }
    final txns = store.transactions.where((t) {
      if (_type != 'all' && t.type != _type) return false;
      if (_cat != 'all' && t.categoryId != _cat) return false;
      if (_dayFilter != null) {
        final d = t.dateTime;
        final f = _dayFilter!;
        if (d.year != f.year || d.month != f.month || d.day != f.day) {
          return false;
        }
      }
      if (_query.isNotEmpty) {
        final q = _query.toLowerCase();
        final c = store.categoryOf(t.categoryId).name.toLowerCase();
        if (!t.note.toLowerCase().contains(q) &&
            !c.contains(q) &&
            !t.mode.contains(q)) {
          return false;
        }
      }
      return true;
    }).toList();

    return Padding(
      padding:
          EdgeInsets.symmetric(horizontal: pageGutter(context)),
      child: Stack(
        children: [
          Column(
            children: [
              _segmented(),
              Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: TextField(
            decoration: const InputDecoration(
              labelText: 'Search note, category, mode',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
            onChanged: (v) {
              // Debounced: keeps long histories smooth while typing.
              _debounce?.cancel();
              _debounce =
                  Timer(const Duration(milliseconds: 300), () {
                if (mounted) setState(() => _query = v);
              });
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: LayoutBuilder(
            builder: (ctx, constraints) {
              final typeField = GlassBox(
                child: DropdownButtonFormField<String>(isExpanded: true,
                  initialValue: _type,
                  decoration: const InputDecoration(
                      labelText: 'Type',
                      border: InputBorder.none),
                items: const [
                  DropdownMenuItem(
                      value: 'all', child: Text('All')),
                  DropdownMenuItem(
                      value: 'expense', child: Text('Expense')),
                  DropdownMenuItem(
                      value: 'income', child: Text('Income')),
                ],
                onChanged: (v) =>
                    setState(() => _type = v ?? 'all'),
                ),
              );
              final catField = GlassBox(
                child: DropdownButtonFormField<String>(isExpanded: true,
                  initialValue: _cat,
                  decoration: const InputDecoration(
                      labelText: 'Category',
                      border: InputBorder.none),
                items: [
                  const DropdownMenuItem(
                      value: 'all', child: Text('All')),
                  for (final c in store.categories)
                    DropdownMenuItem(
                        value: c.id, child: Text(c.name)),
                ],
                onChanged: (v) =>
                    setState(() => _cat = v ?? 'all'),
                ),
              );
              final export = FilledButton.tonalIcon(
                onPressed: txns.isEmpty
                    ? null
                    : () => _exportCsv(context, store, txns),
                icon: const Icon(Icons.download),
                label: const Text('CSV'),
              );
              // Narrow phones stack the fields; wide screens
              // keep one row with the export button field-aligned.
              if (constraints.maxWidth < 520) {
                return Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.stretch,
                  children: [
                    typeField,
                    const SizedBox(height: 8),
                    catField,
                    const SizedBox(height: 8),
                    export,
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: typeField),
                  const SizedBox(width: 12),
                  Expanded(child: catField),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 56,
                    child: Center(child: export),
                  ),
                ],
              );
            },
          ),
        ),
        Expanded(
          child: txns.isEmpty
              ? const Center(child: Text('Nothing found.'))
              : ListView.builder(
                  itemCount: txns.length,
                  itemBuilder: (ctx, i) {
                    final t = txns[i];
                    final c = store.categoryOf(t.categoryId);
                    return Slidable(
                      key: ValueKey(t.id),
                      endActionPane: ActionPane(
                        motion: const BehindMotion(),
                        // Slide to reveal the delete tab (~80% wide).
                        // Nothing deletes until the tab is pressed.
                        extentRatio: 0.8,
                        children: [
                          SlidableAction(
                            onPressed: (_) => deleteWithUndo(
                                context, store, t),
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                            icon: Icons.delete,
                            label: 'Delete',
                          ),
                        ],
                      ),
                      child: ListTile(
                        onLongPress: () =>
                            showEntryActions(context, store, t),
                        onTap: () =>
                            showEntryActions(context, store, t),
                        leading: CircleAvatar(
                          backgroundColor: c.colorValue
                              .withValues(alpha: 0.15),
                          child: Icon(c.iconData,
                              color: c.colorValue, size: 20),
                        ),
                        title:
                            Text(t.note.isEmpty ? c.name : t.note),
                        subtitle: Text(
                            '${dayStr(t.dateTime)}  -  ${c.name}  -  ${t.mode.toUpperCase()}${t.projectId.isEmpty ? '' : '  -  ${store.projectOf(t.projectId).name}'}'),
                        trailing: Text(
                          '${t.isExpense ? '-' : '+'}${money(t.amount)}',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: t.isExpense
                                  ? Colors.red
                                  : Colors.green),
                        ),
                      ),
                    );
                  },
           ),
         ),
       ],
          ),
          if (_dayFilter != null)
            Positioned(
              left: 0,
              bottom: 16,
              child: InputChip(
                label: Text(dayStr(_dayFilter!)),
                deleteIcon:
                    const Icon(Icons.close, size: 18),
                onDeleted: () =>
                    setState(() => _dayFilter = null),
              ),
            ),
          Positioned(
            right: 0,
            bottom: 16,
            child: FloatingActionButton.small(
              tooltip: 'Jump to date',
              onPressed: () => _pickDay(context),
              child: const Icon(Icons.calendar_month),
            ),
          ),
        ],
      ),
    );
  }

  /// Horizontally scrolling chips: SegmentedButton overflows and clips
  /// its labels on narrow phones, chips never do.
  Future<void> _pickDay(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDate: _dayFilter ?? DateTime.now(),
    );
    if (picked != null && mounted) {
      setState(() => _dayFilter = picked);
    }
  }

  Widget _segmented() {
    const items = [
      ('entries', 'Entries', Icons.receipt_long),
      ('cats', 'Categories', Icons.category),
      ('projects', 'Events', Icons.event),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final (v, label, icon) in items)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(label),
                  avatar: Icon(icon, size: 18),
                  showCheckmark: false,
                  selected: _view == v,
                  onSelected: (_) =>
                      setState(() => _view = v),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _categoriesBody(ExpenseStore store) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: Text('Categories & budgets',
                    style:
                        Theme.of(context).textTheme.titleMedium),
              ),
              IconButton(
                  tooltip: 'Add category',
                  onPressed: () =>
                      _addCategoryDialog(context, store),
                  icon: const Icon(Icons.add)),
            ],
          ),
        ),
        Padding(
          padding:
              const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
                'Hold the handle and drag to arrange.',
                style: Theme.of(context).textTheme.bodySmall),
          ),
        ),
        Expanded(
          child: ReorderableListView.builder(
            padding:
                const EdgeInsets.fromLTRB(16, 0, 16, 16),
            itemCount: store.categories.length,
            onReorderItem: (oldI, newI) async {
              await store.moveCategoryTo(
                  store.categories[oldI].id, newI);
            },
            itemBuilder: (ctx, i) {
              final c = store.categories[i];
              return ListTile(
                key: ValueKey(c.id),
                onTap: () =>
                    _customizeCategory(context, store, c),
                leading:
                    Icon(c.iconData, color: c.colorValue),
                title: Text(c.name),
                subtitle: Text(c.budget > 0
                    ? 'Budget ${c.budget.toStringAsFixed(0)}'
                    : 'No budget Â· tap to customize'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                        tooltip: 'Customize',
                        icon: const Icon(Icons.edit),
                        onPressed: () => _customizeCategory(
                            context, store, c)),
                    ReorderableDragStartListener(
                      index: i,
                      child: const Padding(
                        padding: EdgeInsets.all(12),
                        child: Icon(Icons.drag_handle),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _projectsBody(ExpenseStore store) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Events',
                  style:
                      Theme.of(context).textTheme.titleMedium),
            ),
            FilledButton.icon(
              onPressed: () =>
                  _addProjectDialog(context, store),
              icon: const Icon(Icons.add),
              label: const Text('Event'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
            'Group shared spending here - trips, outings, flatmates.'),
        const SizedBox(height: 8),
        if (store.projects.isEmpty)
          const Card(
              child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                      'No events yet. Group shared spending here - trips, outings, flatmates.'))),
        for (final p in store.projects)
          Card(
            margin: const EdgeInsets.symmetric(vertical: 6),
            child: ExpansionTile(
              leading: CircleAvatar(
                backgroundColor: p.colorValue
                    .withValues(alpha: 0.15),
                child: Icon(p.iconData,
                    color: p.colorValue),
              ),
              title: Text(p.name,
                  style:
                      const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(
                  '${money(store.projectSpend(p.id))} - ${store.projectTxns(p.id).length} entries'),
              children: [
                if (p.note.isNotEmpty)
                  ListTile(
                      dense: true,
                      leading:
                          const Icon(Icons.note, size: 18),
                      title: Text(p.note)),
                for (final t in store.projectTxns(p.id).take(8))
                  ListTile(
                    dense: true,
                    leading: Icon(
                        store
                            .categoryOf(t.categoryId)
                            .iconData,
                        size: 18,
                        color: store
                            .categoryOf(t.categoryId)
                            .colorValue),
                    title: Text(t.note.isEmpty
                        ? store
                            .categoryOf(t.categoryId)
                            .name
                        : t.note),
                    subtitle: Text(dayStr(t.dateTime)),
                    trailing: Text(
                      '${t.isExpense ? '-' : '+'}${money(t.amount)}',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: t.isExpense
                              ? Colors.red
                              : Colors.green),
                    ),
                  ),
                OverflowBar(
                  children: [
                    TextButton.icon(
                      onPressed: () => _customizeProject(
                          context, store, p),
                      icon: const Icon(Icons.edit),
                      label: const Text('Edit'),
                    ),
                    TextButton.icon(
                      onPressed: () => _confirmDeleteProject(
                          context, store, p.id, p.name),
                      icon: const Icon(Icons.delete,
                          color: Colors.red),
                      label: const Text('Delete event',
                          style: TextStyle(color: Colors.red)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _addProjectDialog(
      BuildContext context, ExpenseStore store) async {
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
                    border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(
                controller: note,
                decoration: const InputDecoration(
                    labelText: 'Note (optional)',
                    border: OutlineInputBorder())),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Add')),
        ],
      ),
    );
    if (ok == true && name.text.trim().isNotEmpty) {
      await store.addProject(name.text.trim(), note.text.trim());
    }
  }

  Future<void> _customizeProject(BuildContext context,
      ExpenseStore store, Project p) async {
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
                    textCapitalization:
                        TextCapitalization.words,
                    decoration: const InputDecoration(
                        labelText: 'Name',
                        border: OutlineInputBorder())),
                const SizedBox(height: 12),
                TextField(
                    controller: note,
                    decoration: const InputDecoration(
                        labelText: 'Note (optional)',
                        border: OutlineInputBorder())),
                const SizedBox(height: 12),
                const Text('Icon'),
                const SizedBox(height: 4),
                GridView.count(
                  crossAxisCount: 6,
                  shrinkWrap: true,
                  physics:
                      const NeverScrollableScrollPhysics(),
                  children: [
                    for (final i in kIconChoices)
                      GestureDetector(
                        onTap: () =>
                            setD(() => icon = i.codePoint),
                        child: CircleAvatar(
                          backgroundColor:
                              i.codePoint == icon
                                  ? Theme.of(ctx)
                                      .colorScheme
                                      .primaryContainer
                                  : Colors.transparent,
                          child: Icon(i,
                              color: i.codePoint == icon
                                  ? Theme.of(ctx)
                                      .colorScheme
                                      .onPrimaryContainer
                                  : null),
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
                  physics:
                      const NeverScrollableScrollPhysics(),
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
                                  ? Theme.of(ctx)
                                      .colorScheme
                                      .onSurface
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
                onPressed: () =>
                    Navigator.of(ctx).pop(false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () =>
                    Navigator.of(ctx).pop(true),
                child: const Text('Save')),
          ],
        ),
      ),
    );
    if (ok == true && context.mounted) {
      await store.updateProject(p.id,
          name: name.text, note: note.text, icon: icon, color: color);
    }
  }

  Future<void> _confirmDeleteProject(BuildContext context,
      ExpenseStore store, String id, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "$name"?'),
        content: const Text(
            'Its entries stay in History, just untagged.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Keep')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) await store.deleteProject(id);
  }

  /// Rename, budget, icon and color for a category - plus delete
  /// (its entries move to Other; Other itself cannot go).
  Future<void> _customizeCategory(BuildContext context,
      ExpenseStore store, Category c) async {
    final name = TextEditingController(text: c.name);
    final budget = TextEditingController(
        text: c.budget > 0 ? c.budget.toStringAsFixed(0) : '');
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
                    textCapitalization:
                        TextCapitalization.words,
                    decoration: const InputDecoration(
                        labelText: 'Name',
                        border: OutlineInputBorder())),
                const SizedBox(height: 12),
                TextField(
                    controller: budget,
                    keyboardType:
                        const TextInputType.numberWithOptions(
                            decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                          RegExp(r'[0-9.,]')),
                    ],
                    decoration: const InputDecoration(
                        labelText: 'Monthly budget (0 = none)',
                        border: OutlineInputBorder())),
                const SizedBox(height: 12),
                const Text('Icon'),
                const SizedBox(height: 4),
                GridView.count(
                  crossAxisCount: 6,
                  shrinkWrap: true,
                  physics:
                      const NeverScrollableScrollPhysics(),
                  children: [
                    for (final i in kIconChoices)
                      GestureDetector(
                        onTap: () =>
                            setD(() => icon = i.codePoint),
                        child: CircleAvatar(
                          backgroundColor:
                              i.codePoint == icon
                                  ? Theme.of(ctx)
                                      .colorScheme
                                      .primaryContainer
                                  : Colors.transparent,
                          child: Icon(i,
                              color: i.codePoint == icon
                                  ? Theme.of(ctx)
                                      .colorScheme
                                      .onPrimaryContainer
                                  : null),
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
                  physics:
                      const NeverScrollableScrollPhysics(),
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
                                  ? Theme.of(ctx)
                                      .colorScheme
                                      .onSurface
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
                  onPressed: () =>
                      Navigator.of(ctx).pop('delete'),
                  child: const Text('Delete',
                      style: TextStyle(color: Colors.red))),
            TextButton(
                onPressed: () =>
                    Navigator.of(ctx).pop(null),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () =>
                    Navigator.of(ctx).pop('save'),
                child: const Text('Save')),
          ],
        ),
      ),
    );
    if (action == null || !context.mounted) return;
    if (action == 'delete') {
      final used = store.transactions
          .where((t) => t.categoryId == c.id)
          .length;
      final yes = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Delete "${c.name}"?'),
          content: Text(used == 0
              ? 'It is not used anywhere.'
              : '$used entr${used == 1 ? 'y moves' : 'ies move'} to Other.'),
          actions: [
            TextButton(
                onPressed: () =>
                    Navigator.of(ctx).pop(false),
                child: const Text('Keep')),
            FilledButton(
                onPressed: () =>
                    Navigator.of(ctx).pop(true),
                child: const Text('Delete')),
          ],
        ),
      );
      if (yes == true && context.mounted) {
        await store.deleteCategory(c.id);
      }
      return;
    }
    final b = double.tryParse(
            budget.text.trim().replaceAll(',', '')) ??
        0;
    await store.updateCategory(c.id,
        name: name.text, icon: icon, color: color, budget: b < 0 ? 0 : b);
  }

  Future<void> _addCategoryDialog(
      BuildContext context, ExpenseStore store) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New category'),
        content: TextField(
            controller: ctrl,
            decoration:
                const InputDecoration(labelText: 'Name')),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Add')),
        ],
      ),
    );
    if (ok == true && ctrl.text.trim().isNotEmpty) {
      await store.addCategory(ctrl.text.trim());
    }
  }

  Future<void> _exportCsv(
      BuildContext context, ExpenseStore store, List<Txn> txns) async {
    final csv = FileSync.buildCsv((id) => store.categoryOf(id).name, txns);
    final now = DateTime.now();
    await FileSync.exportJson(
        context, csv, 'expense-${now.year}-${now.month}.csv');
  }
}