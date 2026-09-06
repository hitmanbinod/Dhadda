import 'package:flutter/foundation.dart' hide Category;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../format.dart';
import '../store.dart';
import '../widgets/page.dart';

/// 3-tap entry: amount + category + date. Everything else optional.
class AddScreen extends StatefulWidget {
  final VoidCallback onSaved;
  const AddScreen({super.key, required this.onSaved});

  @override
  State<AddScreen> createState() => _AddScreenState();
}

class _AddScreenState extends State<AddScreen>
    with SingleTickerProviderStateMixin {
  bool _isExpense = true;
  final _amount = TextEditingController();
  final _note = TextEditingController();
  String? _categoryId;
  String _projectId = '';
  static const _kAddNew = '__add_new_event__';
  DateTime _date = DateTime.now();
  TimeOfDay _time = TimeOfDay.now();
  String _mode = 'cash';
  bool _reordering = false;
  late final AnimationController _jiggle = AnimationController(
      duration: const Duration(milliseconds: 280), vsync: this)
    ..repeat(reverse: true);

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    _jiggle.dispose();
    super.dispose();
  }

  /// One chip, jiggling while the row is being arranged.
  Widget _catChip(Category c) {
    final chip = ChoiceChip(
      label: Text(c.name),
      avatar: Icon(c.iconData, size: 18),
      showCheckmark: false,
      selected: _categoryId == c.id,
      onSelected: (_) => setState(() => _categoryId = c.id),
    );
    if (!_reordering) return chip;
    return RotationTransition(
      turns:
          Tween<double>(begin: -0.012, end: 0.012).animate(_jiggle),
      child: chip,
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ExpenseStore>();
    _categoryId ??= store.categories.isNotEmpty
        ? store.categories.first.id
        : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Add expense')),
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: ListView(
      padding: pageInsets(context),
      children: [
        SegmentedButton<bool>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(
                value: true,
                label: Text('Expense'),
                icon: Icon(Icons.remove)),
            ButtonSegment(
                value: false,
                label: Text('Income'),
                icon: Icon(Icons.add)),
          ],
          selected: {_isExpense},
          onSelectionChanged: (s) =>
              setState(() => _isExpense = s.first),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _amount,
          autofocus: defaultTargetPlatform !=
                  TargetPlatform.android &&
              defaultTargetPlatform != TargetPlatform.iOS,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          textInputAction: TextInputAction.next,
          onSubmitted: (_) => FocusScope.of(context).nextFocus(),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
          ],
          style: Theme.of(context).textTheme.headlineMedium,
          decoration: InputDecoration(
            labelText: 'Amount',
            border: const OutlineInputBorder(),
            prefixText: '${store.currencySymbol} ',
          ),
        ),
        const SizedBox(height: 16),
        if (_reordering) ...[
          Row(
            children: [
              Expanded(
                child: Text('Drag chips to arrange',
                    style:
                        Theme.of(context).textTheme.bodySmall),
              ),
              TextButton(
                onPressed: () =>
                    setState(() => _reordering = false),
                child: const Text('Done'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 56,
            child: ReorderableListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: store.categories.length,
              onReorderItem: (oldI, newI) async {
                await store.moveCategoryTo(
                    store.categories[oldI].id, newI);
              },
              itemBuilder: (ctx, i) {
                final c = store.categories[i];
                return Padding(
                  key: ValueKey(c.id),
                  padding: const EdgeInsets.only(right: 8),
                  child: _catChip(c),
                );
              },
            ),
          ),
        ] else ...[
          Text('Category',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in store.categories)
                GestureDetector(
                  onLongPress: () =>
                      setState(() => _reordering = true),
                  child: _catChip(c),
                ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(isExpanded: true,
          initialValue: _projectId,
          decoration: const InputDecoration(
              labelText: 'Event (optional)',
              border: OutlineInputBorder()),
          items: [
            const DropdownMenuItem(
                value: '', child: Text('No event')),
            for (final p in store.projects)
              DropdownMenuItem(
                  value: p.id, child: Text(p.name)),
            const DropdownMenuItem(
                value: _kAddNew,
                child: Text('+ Add new event')),
          ],
          onChanged: _pickProject,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now()
                        .add(const Duration(days: 365)),
                    initialDate: _date,
                  );
                  if (picked != null && mounted) {
                    setState(() => _date = picked);
                  }
                },
                icon: const Icon(Icons.calendar_today),
                label: Text(dayStr(_date)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  final picked = await showTimePicker(
                    context: context,
                    initialTime: _time,
                  );
                  if (picked != null && mounted) {
                    setState(() => _time = picked);
                  }
                },
                icon: const Icon(Icons.schedule),
                label: Text(_time.format(context)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(isExpanded: true,
          initialValue: _mode,
          decoration: const InputDecoration(
              labelText: 'Paid via',
              border: OutlineInputBorder()),
          items: const [
            DropdownMenuItem(
                value: 'cash', child: Text('Cash')),
            DropdownMenuItem(
                value: 'bank', child: Text('Bank')),
            DropdownMenuItem(
                value: 'card', child: Text('Card')),
            DropdownMenuItem(
                value: 'ewallet',
                child: Text('E-wallet')),
          ],
          onChanged: (v) =>
              setState(() => _mode = v ?? 'cash'),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _note,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _save(),
          decoration: const InputDecoration(
            labelText: 'Note (optional)',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.note),
          ),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.check),
          label: const Padding(
            padding: EdgeInsets.all(12),
            child: Text('Save'),
          ),
        ),
      ],
      ),
    );
  }

  /// Event picked from the dropdown - or created inline without
  /// leaving the Add screen.
  Future<void> _pickProject(String? v) async {
    if (v == null) return;
    if (v != _kAddNew) {
      setState(() => _projectId = v);
      return;
    }
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
                autofocus: true,
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
    if (ok == true && name.text.trim().isNotEmpty && mounted) {
      final id = await context
          .read<ExpenseStore>()
          .addProject(name.text.trim(), note.text.trim());
      setState(() => _projectId = id);
    }
  }

  Future<void> _save() async {
    final amount = parseAmount(_amount.text);
    if (amount == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Enter a valid amount (numbers only)')));
      return;
    }
    if (_categoryId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pick a category')));
      return;
    }
    await context.read<ExpenseStore>().addTransaction(
          type: _isExpense ? 'expense' : 'income',
          amount: amount,
          categoryId: _categoryId!,
          date: DateTime(_date.year, _date.month, _date.day,
              _time.hour, _time.minute),
          note: _note.text.trim(),
          mode: _mode,
          projectId: _projectId,
        );
    _amount.clear();
    _note.clear();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Saved')));
    widget.onSaved();
  }
}