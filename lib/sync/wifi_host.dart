// Conditional export: real LAN server on dart:io platforms
// (Android / Windows), unsupported stub on Web.
export 'wifi_host_stub.dart' if (dart.library.io) 'wifi_host_io.dart';