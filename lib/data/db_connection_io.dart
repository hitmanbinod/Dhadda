// Native (Android/desktop) SQLite connection. Imported only on IO
// platforms via db_connection.dart — never compiled into web builds.
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Opens (creating first) the app-private database file. Local-only, matching
/// the Phase 1 `allowBackup=false` posture: no cloud, no sync of the file.
QueryExecutor openDbConnection() => LazyDatabase(() async {
  final dir = await getApplicationDocumentsDirectory();
  return NativeDatabase(File(p.join(dir.path, 'dhadda.sqlite')));
});
