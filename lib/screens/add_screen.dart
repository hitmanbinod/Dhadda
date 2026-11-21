import 'package:flutter/foundation.dart' hide Category;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../app_dates.dart';
import '../format.dart';
import '../receipts.dart';
import '../store.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import '../widgets/app_card.dart';
import '../widgets/page.dart';
import '../widgets/receipt_field.dart';

IconData _accountIcon(String type) => switch (type) {
      'bank' => Icons.account_balance_outlined,
      'card' => Icons.credit_card_outlined,
      'wallet' => Icons.account_balance_wallet_outlined,
      'other' => Icons.account_circle_outlined,
      _ => Icons.money_outlined,
    };

/// 3-tap entry: amount + category + date. Everything else optional.
class AddScreen extends StatefulWidget {
  final VoidCallback onSaved;

  /// Quick-add widgets can open the form with income preselected.
  final bool initialIsExpense;

  const AddScreen({
    super.key,
    required this.onSaved,
    this.initialIsExpense = true,
  });

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
  String _accountId = 'acct_cash';
  bool _reordering = false;
  bool _categoryChosen = false;
  String? _suggestedCategoryId;
  final String _txnId = const Uuid().v4();
  List<String> _incomingReceipts = [];
  late final AnimationController _jiggle = AnimationController(
      duration: const Duration(milliseconds: 280), vsync: this)
    ..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    _isExpense = widget.initialIsExpense;
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    _jiggle.dispose();
    super.dispose();
  }

  /// One chip, jiggling while the row is being arranged.
  Widget _catChip(Category c) {
    final colors = AppColors.of(context);
    final selected = _categoryId == c.id;
    final foreground = selected ? colors.onAccent : colors.textPrimary;
    final chip = ChoiceChip(
      label: Text(
        c.name,
        style: AppType.caption.copyWith(color: foreground),
      ),
      avatar: Icon(
        c.iconData,
        size: 18,
        color: selected ? colors.onAccent : c.colorValue,
      ),
      showCheckmark: false,
      selected: selected,
      onSelected: (_) => setState(() {
        _categoryId = c.id;
        _categoryChosen = true;
        _suggestedCategoryId = null;
      }),
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
    final colors = AppColors.of(context);
    final hPad = pageInsets(context).left;
    _categoryId ??= store.categories.isNotEmpty
        ? store.categories.first.id
        : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isExpense ? 'Add expense' : 'Add income'),
      ),
      backgroundColor: colors.background,
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                hPad,
                Spacing.md,
                hPad,
                Spacing.lg,
              ),
              children: [
                _typeTrack(colors),
                const SizedBox(height: Spacing.lg),
                _amountCard(colors, store),
                const SizedBox(height: Spacing.lg),
                _categorySection(context, colors, store),
                const SizedBox(height: Spacing.lg),
                _accountSection(colors, store),
                const SizedBox(height: Spacing.lg),
                _detailsCard(context, colors, store),
                const SizedBox(height: Spacing.lg),
                ReceiptField(
                  initial: const [],
                  onChanged: (_) {},
                  onCapturedChanged: (paths) => _incomingReceipts = paths,
                ),
                const SizedBox(height: Spacing.md),
              ],
            ),
          ),
          _saveBar(colors, hPad),
        ],
      ),
    );
  }

  /// Seamless pill track; the active inner pill follows the app accent.
  Widget _typeTrack(AppColors colors) {
    Widget segment(bool expense, String label, IconData icon) {
      final active = _isExpense == expense;
      return Semantics(
        button: true,
        selected: active,
        label: label,
        child: InkWell(
          onTap: () => setState(() => _isExpense = expense),
          borderRadius: Radii.pillRadius,
          child: AnimatedContainer(
            duration: Motion.of(context, Motion.fast),
            curve: Motion.ease,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active ? colors.accent : Colors.transparent,
              borderRadius: Radii.pillRadius,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: active ? colors.onAccent : colors.textSecondary,
                ),
                const SizedBox(width: Spacing.xs),
                Text(
                  label,
                  style: AppType.button.copyWith(
                    fontSize: 14,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    color: active ? colors.onAccent : colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      height: Sizes.segmentedHeight,
      padding: const EdgeInsets.all(Radii.segmentInset),
      decoration: BoxDecoration(
        color: colors.surface2,
        borderRadius: Radii.pillRadius,
      ),
      child: Row(
        children: [
          Expanded(child: segment(true, 'Expense', Icons.remove)),
          Expanded(child: segment(false, 'Income', Icons.add)),
        ],
      ),
    );
  }

  /// Large, quiet hero amount surface with a micro-label and currency prefix.
  Widget _amountCard(AppColors colors, ExpenseStore store) {
    return AppCard(
      radius: Radii.cardLargeRadius,
      padding: const EdgeInsets.fromLTRB(
        Spacing.lg,
        Spacing.md,
        Spacing.lg,
        Spacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Amount',
            style: AppType.caption.copyWith(
              fontSize: 12,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: Spacing.xs),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                store.currencySymbol,
                style: AppType.title.copyWith(
                  fontSize: 24,
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: TextField(
                  controller: _amount,
                  autofocus: defaultTargetPlatform != TargetPlatform.android &&
                      defaultTargetPlatform != TargetPlatform.iOS,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) => FocusScope.of(context).nextFocus(),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  style: AppType.heroAmount.copyWith(
                    fontSize: 34,
                    color: colors.textPrimary,
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    hintText: '0',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) => Semantics(
        header: true,
        child: Text(
          title,
          style: AppType.title.copyWith(color: AppColors.of(context).textPrimary),
        ),
      );

  /// Category header with a right-aligned New pill and an even 3-column grid.
  Widget _categorySection(
    BuildContext context,
    AppColors colors,
    ExpenseStore store,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _sectionTitle('Category'),
            const Spacer(),
            ActionChip(
              key: const Key('add-new-category'),
              avatar: const Icon(Icons.add, size: 16),
              label: const Text('New'),
              tooltip: 'Add your own category',
              visualDensity: VisualDensity.compact,
              onPressed: () => _newCategory(context, store),
            ),
          ],
        ),
        const SizedBox(height: Spacing.sm),
        if (_reordering) ...[
          Row(
            children: [
              Expanded(
                child: Text(
                  'Drag chips to arrange',
                  style: AppType.caption.copyWith(color: colors.textSecondary),
                ),
              ),
              TextButton(
                onPressed: () => setState(() => _reordering = false),
                child: const Text('Done'),
              ),
            ],
          ),
          const SizedBox(height: Spacing.xs),
          SizedBox(
            height: 56,
            child: ReorderableListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: store.categories.length,
              onReorderItem: (oldI, newI) async {
                await store.moveCategoryTo(store.categories[oldI].id, newI);
              },
              itemBuilder: (ctx, i) => Padding(
                key: ValueKey(store.categories[i].id),
                padding: const EdgeInsets.only(right: Spacing.sm),
                child: _catChip(store.categories[i]),
              ),
            ),
          ),
        ] else
          LayoutBuilder(
            builder: (context, constraints) {
              final width = (constraints.maxWidth - 2 * Spacing.sm) / 3;
              return Wrap(
                spacing: Spacing.sm,
                runSpacing: Spacing.sm,
                children: [
                  for (final c in store.categories)
                    SizedBox(
                      width: width,
                      height: 38,
                      child: _catPill(c, colors),
                    ),
                ],
              );
            },
          ),
        if (_suggestedCategoryId != null)
          Padding(
            padding: const EdgeInsets.only(top: Spacing.xs),
            child: Align(
              alignment: Alignment.centerLeft,
              child: ActionChip(
                key: const Key('add-category-suggestion'),
                avatar: const Icon(Icons.auto_awesome_outlined, size: 16),
                label: Text(
                  '${store.categoryOf(_suggestedCategoryId!).name}?',
                ),
                onPressed: () => setState(() {
                  _categoryId = _suggestedCategoryId;
                  _categoryChosen = true;
                  _suggestedCategoryId = null;
                }),
              ),
            ),
          ),
      ],
    );
  }

  Widget _catPill(Category c, AppColors colors) {
    final selected = _categoryId == c.id;
    final foreground = selected ? colors.onAccent : colors.textPrimary;
    return Material(
      color: selected ? colors.accent : colors.surface2,
      borderRadius: Radii.pillRadius,
      child: InkWell(
        onTap: () => setState(() {
          _categoryId = c.id;
          _categoryChosen = true;
          _suggestedCategoryId = null;
        }),
        onLongPress: () => setState(() => _reordering = true),
        borderRadius: Radii.pillRadius,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Spacing.sm),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                c.iconData,
                size: 16,
                color: selected ? colors.onAccent : c.colorValue,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  c.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.caption.copyWith(
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: foreground,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Four equal-width stacked tiles, so E-wallet never lands alone.
  Widget _accountSection(AppColors colors, ExpenseStore store) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle('Account'),
        const SizedBox(height: Spacing.sm),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = (constraints.maxWidth - 3 * Spacing.sm) / 4;
            return Wrap(
              spacing: Spacing.sm,
              runSpacing: Spacing.sm,
              children: [
                for (final a in store.activeAccounts)
                  SizedBox(width: width, child: _accountTile(a, colors)),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _accountTile(Account a, AppColors colors) {
    final selected = _accountId == a.id;
    final foreground = selected ? colors.onAccent : colors.textPrimary;
    final tint = a.color == 0 ? colors.field : Color(a.color);
    return Material(
      color: selected ? colors.accent : colors.surface2,
      borderRadius: Radii.iconRadius,
      child: InkWell(
        key: Key('add-account-${a.id}'),
        onTap: () => setState(() {
          _accountId = a.id;
          _mode = modeForAccountType(a.type);
        }),
        borderRadius: Radii.iconRadius,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            vertical: Spacing.sm,
            horizontal: 2,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected
                      ? colors.onAccent.withValues(alpha: 0.2)
                      : tint.withValues(alpha: 0.14),
                  borderRadius: Radii.iconRadius,
                ),
                child: Icon(
                  _accountIcon(a.type),
                  size: 16,
                  color: selected ? colors.onAccent : tint,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                a.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.caption.copyWith(
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: foreground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailBadge(IconData icon, AppColors colors) => Container(
        width: 28,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: colors.surface2,
          borderRadius: Radii.iconRadius,
        ),
        child: Icon(icon, size: 16, color: colors.textSecondary),
      );

  Widget _detailDivider(AppColors colors) => Padding(
        padding: const EdgeInsets.only(
          left: Spacing.lg + 28 + Spacing.md,
          right: Spacing.lg,
        ),
        child: Divider(height: 1, thickness: 1, color: colors.hairline),
      );

  /// Date + Time + Event + Note share one card with inset hairlines.
  Widget _detailsCard(
    BuildContext context,
    AppColors colors,
    ExpenseStore store,
  ) {
    return AppCard(
      radius: Radii.cardLargeRadius,
      padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Spacing.lg,
              vertical: Spacing.xs,
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 64,
                  child: _detailAction(
                    colors,
                    icon: Icons.calendar_today_outlined,
                    label: dayStr(_date),
                    onTap: () async {
                      final picked = await showAppDatePicker(
                        context: context,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now().add(
                          const Duration(days: 365),
                        ),
                        initialDate: _date,
                      );
                      if (picked != null && mounted) {
                        setState(() => _date = picked);
                      }
                    },
                  ),
                ),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  flex: 36,
                  child: _detailAction(
                    colors,
                    icon: Icons.schedule,
                    label: _time.format(context),
                    onTap: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: _time,
                      );
                      if (picked != null && mounted) {
                        setState(() => _time = picked);
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          _detailDivider(colors),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Spacing.lg,
              vertical: 2,
            ),
            child: Row(
              children: [
                _detailBadge(Icons.event_outlined, colors),
                const SizedBox(width: Spacing.md),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: _projectId,
                    decoration: const InputDecoration(
                      labelText: 'Event (optional)',
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: '',
                        child: Text('No event'),
                      ),
                      for (final p in store.projects)
                        DropdownMenuItem(value: p.id, child: Text(p.name)),
                      const DropdownMenuItem(
                        value: _kAddNew,
                        child: Text('+ Add new event'),
                      ),
                    ],
                    onChanged: _pickProject,
                  ),
                ),
              ],
            ),
          ),
          _detailDivider(colors),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Spacing.lg,
              vertical: 2,
            ),
            child: Row(
              children: [
                _detailBadge(Icons.note_outlined, colors),
                const SizedBox(width: Spacing.md),
                Expanded(
                  child: TextField(
                    controller: _note,
                    textInputAction: TextInputAction.done,
                    onChanged: _onNoteChanged,
                    onSubmitted: (_) => _save(),
                    style: AppType.body.copyWith(fontSize: 14),
                    decoration: const InputDecoration(
                      hintText: 'Note (optional)',
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailAction(
    AppColors colors, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: Radii.iconRadius,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
        child: Row(
          children: [
            _detailBadge(icon, colors),
            const SizedBox(width: Spacing.sm),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.body.copyWith(
                  fontSize: 13,
                  color: colors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _saveBar(AppColors colors, double hPad) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        hPad,
        Spacing.sm,
        hPad,
        Spacing.md + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: BoxDecoration(
        color: colors.background,
        border: Border(top: BorderSide(color: colors.hairline)),
      ),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton(
          key: const Key('add-save'),
          onPressed: _save,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Save'),
              Text(_isExpense ? ' expense' : ' income'),
            ],
          ),
        ),
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

  /// Category picked from the chip row - or created inline without
  /// leaving the Add screen.
  Future<void> _newCategory(
      BuildContext context, ExpenseStore store) async {
    final name = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New category'),
        content: TextField(
          controller: name,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          // Accept the keyboard's Done key: with the keyboard open, some
          // devices swallow the first tap on the dialog buttons.
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => Navigator.of(ctx).pop(true),
          decoration: const InputDecoration(
            labelText: 'Name (Gym, Baby, Car...)',
            border: OutlineInputBorder(),
          ),
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
    final trimmed = name.text.trim();
    if (ok != true || trimmed.isEmpty || !mounted) return;
    // Reuse an existing category instead of silently duplicating it.
    final existing = store.categories
        .cast<Category?>()
        .firstWhere(
          (c) => c!.name.toLowerCase() == trimmed.toLowerCase(),
          orElse: () => null,
        );
    if (existing != null) {
      setState(() {
        _categoryId = existing.id;
        _categoryChosen = true;
      });
      return;
    }
    final id = await store.addCategory(trimmed);
    if (!mounted) return;
    setState(() {
      _categoryId = id;
      _categoryChosen = true;
    });
  }

  void _onNoteChanged(String value) {
    if (_categoryChosen) {
      if (_suggestedCategoryId != null) {
        setState(() => _suggestedCategoryId = null);
      }
      return;
    }
    final rule = context.read<ExpenseStore>().categoryRuleFor(
          value,
          _isExpense ? 'expense' : 'income',
        );
    final next = rule?.categoryId;
    if (next != _suggestedCategoryId) setState(() => _suggestedCategoryId = next);
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
    final ok = await context.read<ExpenseStore>().addTransaction(
          type: _isExpense ? 'expense' : 'income',
          amount: amount,
          categoryId: _categoryId!,
          date: DateTime(_date.year, _date.month, _date.day,
              _time.hour, _time.minute),
          note: _note.text.trim(),
          mode: _mode,
          accountId: _accountId,
          projectId: _projectId,
          id: _txnId,
        );
    if (!ok) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Could not save — storage failed. Your entry was not added. '
              'Please try again.')));
      return;
    }
    if (_incomingReceipts.isNotEmpty) {
      final receipts = await ReceiptStore.create();
      await receipts.attach(_txnId, _incomingReceipts);
      _incomingReceipts = [];
    }
    _amount.clear();
    _note.clear();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Saved')));
    widget.onSaved();
  }
}