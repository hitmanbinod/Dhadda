import 'package:expense/sync/mdns.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const ch = MethodChannel('expense/mdns');
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ch, null);
  });

  test('register passes name/type/port and keeps actual name', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ch, (call) async {
      expect(call.method, 'register');
      expect(call.arguments['name'], 'dhadda');
      expect(call.arguments['type'], '_http._tcp.');
      expect(call.arguments['port'], 8080);
      return {'ok': true, 'name': 'dhadda-2'};
    });
    final r = await Mdns.register(port: 8080);
    expect(r.ok, isTrue);
    expect(r.name, 'dhadda-2');
  });

  test('channel failure falls back, never throws', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ch, (call) async {
      throw PlatformException(code: 'NO NSD');
    });
    final r = await Mdns.register(port: 8080);
    expect(r.ok, isFalse);
    expect(r.name, 'dhadda');
    await Mdns.unregister();
  });

  test('unregister completes silently', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ch, (call) async => null);
    await Mdns.unregister();
  });
}