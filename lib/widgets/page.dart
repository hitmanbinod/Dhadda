import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';

/// Caps content width on wide (desktop) screens so rows don't stretch
/// edge-to-edge, while phones keep comfortable 16dp margins.
const double kPageMaxWidth = 960.0;
const double kPageMargin = 16.0;

/// Height of the floating Add pill and the Material 3 NavigationBar.
const double kAddPillHeight = 50.0;
const double kNavBarHeight = 80.0;

/// Bottom breathing room for tab scroll views. It keeps the floating Add
/// pill (and the phone navigation bar plus its system inset) from covering
/// the last tappable row. Wide layouts swap the bar for a rail.
double tabScrollBottomPadding(BuildContext context) {
  final wide = MediaQuery.widthOf(context) > 900;
  final systemBottom = MediaQuery.paddingOf(context).bottom;
  return (wide ? 0 : kNavBarHeight + systemBottom) + kAddPillHeight + 16;
}

/// Bottom inset for controls pinned under one-handed mode. The floating Add
/// pill only exists on Home, so these bars sit immediately above the bottom
/// navigation bar (including the system gesture inset) with a small gap.
double oneHandedBottomPadding(BuildContext context) {
  final wide = MediaQuery.widthOf(context) > 900;
  if (wide) return Spacing.sm;
  return kNavBarHeight + MediaQuery.paddingOf(context).bottom + Spacing.xs;
}

/// Full padding for scrollable pages (ListView etc).
EdgeInsets pageInsets(BuildContext context, {double vertical = 16}) {
  final w = MediaQuery.widthOf(context);
  final gutter = w > kPageMaxWidth + kPageMargin * 2
      ? (w - kPageMaxWidth) / 2
      : kPageMargin;
  return EdgeInsets.fromLTRB(gutter, vertical, gutter, vertical);
}

/// Extra horizontal margin for pages whose children already carry
/// their own 16dp padding (avoids doubling it on desktop).
double pageGutter(BuildContext context) {
  final w = MediaQuery.widthOf(context);
  return w > kPageMaxWidth + kPageMargin * 2 ? (w - kPageMaxWidth) / 2 : 0;
}
