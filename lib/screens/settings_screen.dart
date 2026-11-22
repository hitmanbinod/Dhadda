import 'package:flutter/material.dart';

import '../sync/lan_host.dart';
import '../sync/link_sync.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import '../widgets/page.dart';
import 'menu_screen.dart';

/// Pushed Settings route. The existing menu content is kept intact below a
/// large title and a back button; its visual restyle comes later.
class SettingsScreen extends StatelessWidget {
  final LinkEngine engine;
  final LanHostController? host;

  const SettingsScreen({
    super.key,
    required this.engine,
    this.host,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final gutter = pageInsets(context, vertical: 0).left;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                gutter - Spacing.sm,
                Spacing.sm,
                gutter,
                0,
              ),
              child: Row(
                children: [
                  IconButton(
                    key: const Key('settings-back'),
                    tooltip: 'Back',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: Icon(Icons.arrow_back, color: colors.textPrimary),
                  ),
                  const SizedBox(width: Spacing.xs),
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        'Settings',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.largeTitle.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: MenuScreen(engine: engine, host: host ?? lanHost),
            ),
          ],
        ),
      ),
    );
  }
}
