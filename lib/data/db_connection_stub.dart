// Web stub: browsers cannot open the native database. The web build keeps
// the SharedPreferences backend (PrefsDomainStore), so this is never called.
import 'package:drift/drift.dart';

QueryExecutor openDbConnection() =>
    throw UnsupportedError('SQLite persistence needs Android/desktop.');
