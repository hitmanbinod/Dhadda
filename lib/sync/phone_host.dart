// Conditional export: real phone hosting on dart:io platforms
// (Android app serves the UI + sync API on your WiFi),
// unsupported stub on Web.
export 'phone_host_stub.dart' if (dart.library.io) 'phone_host_io.dart';