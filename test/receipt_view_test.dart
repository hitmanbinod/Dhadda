import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:expense/receipts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late ReceiptStore store;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('dhadda-receipt-view-');
    store = ReceiptStore(root);
    await store.ensure();
    ReceiptStore.debugOverride(store);
  });

  tearDown(() async {
    ReceiptStore.debugOverride(null);
    try {
      await root.delete(recursive: true);
    } catch (_) {}
  });

  test('picked bytes are saved as a downscaled JPEG and attachable', () async {
    final source = img.Image(width: 2000, height: 1000);
    img.fill(source, color: img.ColorRgb8(200, 100, 50));
    final bytes = Uint8List.fromList(img.encodeJpg(source));

    final path = await store.savePickedBytes(bytes, prefix: 'gallery');
    expect(File(path).existsSync(), isTrue);

    final decoded = img.decodeJpg(await File(path).readAsBytes());
    expect(decoded, isNotNull);
    expect(decoded!.width, 1600);
    expect(decoded.height, 800);

    final saved = await store.attach('entry-1', [path]);
    expect(saved.single, matches(r'entry-1[\\/]gallery-.*\.jpg'));
    expect(await store.hasFor('entry-1'), isTrue);
  });
}
