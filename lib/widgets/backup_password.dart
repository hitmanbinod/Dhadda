// Password prompt for encrypted backups (Phase 3, additive).
// The password is never stored: it lives in these controllers only,
// goes straight into the KDF, and is discarded with the dialog.
import 'package:flutter/material.dart';

/// Asks for a backup password. When [confirm] is true (export), asks twice
/// and only enables the action on a non-empty match. Returns the password,
/// or null when cancelled/invalid. Shows no strength meter on purpose: any
/// memorable passphrase beats the 4-digit app PIN by orders of magnitude.
Future<String?> askBackupPassword(BuildContext context,
    {required bool confirm}) async {
  final first = TextEditingController();
  final second = TextEditingController();
  var mismatch = false;
  final pw = await showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) {
        final ok = first.text.isNotEmpty &&
            (!confirm || first.text == second.text);
        return AlertDialog(
          title: Text(confirm ? 'Encrypt backup' : 'Decrypt backup'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Use a real passphrase (not your 4-digit app PIN). '
                'Lose it and the backup cannot be opened.',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: first,
                obscureText: true,
                autofocus: true,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Backup password',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setD(() => mismatch = false),
              ),
              if (confirm) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: second,
                  obscureText: true,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: 'Repeat password',
                    border: const OutlineInputBorder(),
                    errorText: mismatch ? 'Passwords do not match.' : null,
                  ),
                  onChanged: (_) => setD(() => mismatch = false),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: !ok
                  ? null
                  : () {
                      if (confirm && first.text != second.text) {
                        setD(() => mismatch = true);
                        return;
                      }
                      Navigator.of(ctx).pop(first.text);
                    },
              child: const Text('Continue'),
            ),
          ],
        );
      },
    ),
  );
  first.dispose();
  second.dispose();
  return pw;
}
