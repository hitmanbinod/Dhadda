import 'package:flutter/material.dart';

import '../widgets/page.dart';

/// Shown instead of the app when the database file would not open.
///
/// The point is honesty: an empty expense tracker is indistinguishable from
/// deleted data, so the user is told what happened, that a copy of the file
/// was kept, and given an explicit choice. [onRetry] re-runs the load against a
/// fresh file (the honest first try after an interrupted upgrade);
/// [onStartEmpty] proceeds with whatever the load produces.
class DatabaseProblemScreen extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  final VoidCallback onStartEmpty;

  const DatabaseProblemScreen({
    super.key,
    required this.message,
    required this.onRetry,
    required this.onStartEmpty,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: pageInsets(context, vertical: 48),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 48,
                      color: theme.colorScheme.error,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Your data could not be opened',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Nothing has been deleted. Trying again usually fixes a '
                      'file left behind by an interrupted upgrade.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: onRetry,
                      child: const Text('Try again'),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: onStartEmpty,
                      child: const Text('Start with an empty tracker'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}