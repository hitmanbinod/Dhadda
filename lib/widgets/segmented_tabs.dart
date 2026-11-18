import 'package:flutter/material.dart';

import '../theme/haptics.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

/// iOS-style segmented control: a quiet track, one raised selected pill.
/// Each segment has a full 48dp tap target; selected labels are w600.
class SegmentedTabs extends StatelessWidget {
  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onChanged;
  final EdgeInsetsGeometry padding;

  const SegmentedTabs({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onChanged,
    this.padding = EdgeInsets.zero,
  }) : assert(labels.length > 1);

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final duration = Motion.of(context, Motion.fast);

    return Padding(
      padding: padding,
      child: Container(
        height: Sizes.segmentedHeight,
        decoration: BoxDecoration(
          color: colors.field,
          borderRadius: Radii.segmentedRadius,
        ),
        child: Row(
          children: [
            for (var i = 0; i < labels.length; i++)
              Expanded(
                child: Semantics(
                  button: true,
                  selected: i == selectedIndex,
                  label: labels[i],
                  child: InkWell(
                    borderRadius: BorderRadius.circular(Radii.segment),
                    onTap: () {
                      if (i == selectedIndex) return;
                      Haptics.selection();
                      onChanged(i);
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(Radii.segmentInset),
                      child: AnimatedContainer(
                        duration: duration,
                        curve: Motion.ease,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: i == selectedIndex
                              ? colors.selectedFill
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(Radii.segment),
                        ),
                        child: ExcludeSemantics(
                          child: AnimatedDefaultTextStyle(
                            duration: duration,
                            curve: Motion.ease,
                            style: AppType.caption.copyWith(
                              color: i == selectedIndex
                                  ? colors.textPrimary
                                  : colors.textSecondary,
                              fontWeight: i == selectedIndex
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                            ),
                            child: Text(
                              labels[i],
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
