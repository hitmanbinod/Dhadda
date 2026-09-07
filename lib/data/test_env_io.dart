// IO platforms: true only inside `flutter test` runs.
import 'dart:io';

bool get isFlutterTest => Platform.environment.containsKey('FLUTTER_TEST');
