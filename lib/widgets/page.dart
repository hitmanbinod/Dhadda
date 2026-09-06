import 'package:flutter/widgets.dart';

/// Caps content width on wide (desktop) screens so rows don't stretch
/// edge-to-edge, while phones keep comfortable 16dp margins.
const double kPageMaxWidth = 880.0;
const double kPageMargin = 16.0;

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
  return w > kPageMaxWidth + kPageMargin * 2
      ? (w - kPageMaxWidth) / 2
      : 0;
}