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
  // The Scaffold body already ends at the top of the bottom NavigationBar,
  // so only the floating Add pill needs clearing here (~88-96dp in total).
  return (wide ? 0 : systemBottom) + kAddPillHeight + 40;
}

/// Bottom gap for controls pinned under one-handed mode. The Scaffold body
/// already ends at the top of the bottom NavigationBar, so only a small gap
/// is needed here. Adding the nav-bar height would leave the controls
/// floating a whole bar above the tabs (and double-count the system inset).
double oneHandedBottomPadding(BuildContext context) {
  return Spacing.sm;
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
