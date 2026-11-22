// Debug-only test server used by scripts/lan-simulate.mjs.
// Binds loopback, prints READY <base-url>, and serves the real LanServer.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:expense/sync/lan_server.dart';

Future<void> main() async {
  final port = int.tryParse(Platform.environment['LAN_TEST_PORT'] ?? '') ?? 18765;
  final server = LanServer(
    data: MemoryLanDataStore(),
    options: LanServerOptions(
      port: port,
      allowLoopback: true,
      assetLoader: (name) async => name == 'webapp/index.html'
          ? Uint8List.fromList(utf8.encode('<html>Dhadda test</html>'))
          : null,
    ),
  );
  await server.start();
  stdout.writeln('READY ${server.baseUrl}');
  await stdin.drain(); // stay up until the parent closes stdin
  await server.stop();
}
