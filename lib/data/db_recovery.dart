// Platform-selected database file recovery.
// Web never opens a database file, so the dart:io surface must never be
// compiled into the web bundle. Mirrors db_connection.dart.
export 'db_recovery_stub.dart' if (dart.library.io) 'db_recovery_io.dart';