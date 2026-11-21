import 'package:flutter/material.dart';

import '../format.dart';
import '../store.dart';
import '../theme/tokens.dart';
import 'entry_actions.dart';

/// One event's entries as a collapsible branch: a header row (icon, name,
/// entries count, spent total, chevron) that collapses/expands the branch
/// rows hanging off a quiet spine. Used on Home, in the History entries
/// list and in the Events tab so the same event always looks the same.
class EventBranchGroup extends StatefulWidget {
  final ExpenseStore store;
  final Project project;

  /// This event's entries, newest first (already filtered by the caller).
  final List<Txn> txns;
  final bool initiallyExpanded;

  const EventBranchGroup({
    super.key,
    required this.store,
    required this.project,
    required this.txns,
    this.initiallyExpanded = true,
  });

  @override
  State<EventBranchGroup> createState() => _EventBranchGroupState();
}

class _EventBranchGroupState extends State<EventBranchGroup> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final p = widget.project;
    final spent = widget.txns.fold(0.0, (s, t) => t.isExpense ? s + t.amount : s);
    final accent = p.colorValue;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 8, 6),
            child: Row(
              children: [
                Container(
                  width: Sizes.iconTile,
                  height: Sizes.iconTile,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.15),
                    borderRadius: Radii.iconRadius,
                  ),
                  child: Icon(p.iconData, color: accent, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '${widget.txns.length} entries · Spent ${money(spent)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                AnimatedRotation(
                  turns: _expanded ? 0 : -0.25,
                  duration: const Duration(milliseconds: 180),
                  child: Icon(Icons.expand_more,
                      size: 22, color: Theme.of(context).hintColor),
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          // The rows leave the tree when collapsed (a CrossFade would
          // keep them mounted, hiding nothing for real).
          child: _expanded
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
                  child: Column(
                    children: [
                      for (var i = 0; i < widget.txns.length; i++)
                        _branchRow(widget.txns[i],
                            first: i == 0,
                            last: i == widget.txns.length - 1),
                    ],
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }

  Widget _branchRow(Txn t, {required bool first, required bool last}) {
    final store = widget.store;
    final c = store.categoryOf(t.categoryId);
    return InkWell(
      onTap: () => showEntryActions(context, store, t),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            SizedBox(
              width: 30,
              height: 52,
              child: CustomPaint(
                painter: _BranchPainter(
                  color: widget.project.colorValue.withValues(alpha: 0.45),
                  first: first,
                  last: last,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child:
                  Icon(c.iconData, size: 18, color: c.colorValue),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.note.isEmpty ? c.name : t.note,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${dayStr(t.dateTime)}  ·  '
                    '${store.accountName(t.effectiveAccountId)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${t.isExpense ? '-' : '+'}${money(t.amount)}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: t.isExpense ? Colors.red : Colors.green,
              ),
            ),
            const SizedBox(width: 16),
          ],
        ),
      ),
    );
  }
}

/// Draws the event-branch spine: a vertical line threads through the
/// group (starting/ending at the first/last row's middle) and each row
/// gets a dot + horizontal tick, like branches off a trunk.
class _BranchPainter extends CustomPainter {
  final Color color;
  final bool first;
  final bool last;

  _BranchPainter(
      {required this.color, required this.first, required this.last});

  @override
  void paint(Canvas canvas, Size size) {
    final spineX = size.width * 0.35;
    final midY = size.height / 2;
    final line = Paint()
      ..color = color
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(spineX, first ? midY : 0),
        Offset(spineX, last ? midY : size.height), line);
    canvas.drawLine(Offset(spineX, midY), Offset(size.width - 2, midY), line);
    canvas.drawCircle(Offset(spineX, midY), 3, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_BranchPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.first != first ||
      oldDelegate.last != last;
}
