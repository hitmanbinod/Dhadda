// Native (Android/desktop) database file recovery. Imported only on IO
// platforms via db_recovery.dart — never compiled into web builds.
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Database file name. Kept in one place so quarantine and connection agree.
const kDbFileName = 'dhadda.sqlite';

/// One-time safety copy taken before the Round 3 schema migration. The file
/// stays in the same app-private directory; a failed copy never blocks startup
/// (the migration itself is guarded and resumable).
Future<String> backupDatabaseBeforeMigration() async {
  try {
    final dir = await getApplicationDocumentsDirectory();
    final source = File(p.join(dir.path, kDbFileName));
    final target = p.join(dir.path, 'dhadda.pre-round3.sqlite');
    if (!await source.exists() || await File(target).exists()) return '';
    await source.copy(target);
    return target;
  } catch (_) {
    return '';
  }
}

/// Moves an unreadable database file aside so the app can start clean without
/// destroying whatever the file still contains, and returns the new file name
/// (or an empty string when there was nothing to move).
///
/// Never throws: a recovery path that itself fails must not take the app down
/// with it, and the caller falls back to the prefs backend either way.
Future<String> quarantineDatabaseFile() async {
  try {
    final dir = await getApplicationDocumentsDirectory();
    final source = File(p.join(dir.path, kDbFileName));
    if (!await source.exists()) return '';
    final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(
      RegExp(r'[^0-9]'),
      '',
    );
    final target = 'dhadda.corrupt-$stamp.sqlite';
    await source.rename(p.join(dir.path, target));
    return target;
  } catch (_) {
    return '';
  }
}