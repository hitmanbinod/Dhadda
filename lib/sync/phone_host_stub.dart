import 'package:flutter/foundation.dart';

/// Web stub: browsers cannot host. Phone hosting needs the Android app.
class PhoneHostSession {
  final String url = '';
  final ValueNotifier<int> hits = ValueNotifier<int>(0);
  Future<void> close() async {}
}

Future<PhoneHostSession> startPhoneHost() async {
  throw UnsupportedError('Showing on PC needs the Android app.');
}