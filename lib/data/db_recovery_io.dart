// Native (Android/desktop) database file recovery. Imported only on IO
// platforms via db_recovery.dart — never compiled into web builds.
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Database file name. Kept in one place so quarantine and connection agree.
const kDbFileName = 'dhadda.sqlite';

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