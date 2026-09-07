// Platform-selected SQLite connection for Drift.
//
// Web never opens a database (it keeps the SharedPreferences backend), so the
// sqlite3 native binding must never be compiled into the web bundle. The
// conditional export below guarantees that: browsers see only the stub.
// Mirrors the existing wifi_host.dart / phone_host.dart pattern.
export 'db_connection_stub.dart'
    if (dart.library.io) 'db_connection_io.dart';
