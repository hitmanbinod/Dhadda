// Test-environment gate without importing dart:io (which web forbids).
// Unit/widget tests run the prefs backend; production IO opens SQLite.
export 'test_env_stub.dart' if (dart.library.io) 'test_env_io.dart';
