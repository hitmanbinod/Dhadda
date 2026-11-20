import 'dart:io';

import 'package:expense/receipts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late ReceiptStore store;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('dhadda-receipts-');
    store = ReceiptStore(root);
    await store.ensure();
  });

  tearDown(() async {
    try {
      await root.delete(recursive: true);
    } catch (_) {}
  });

  File incoming(String name) {
    final f = File('${store.incoming().path}/$name');
    f.writeAsBytesSync([1, 2, 3, 4]);
    return f;
  }

  test('attach moves captures under the entry id and lists them', () async {
    final a = incoming('one.jpg');
    final b = incoming('two.jpg');
    final saved = await store.attach('entry-1', [a.path, b.path]);
    expect(saved.length, 2);
    expect(a.existsSync(), isFalse);
    expect((await store.forEntryPaths('entry-1')).length, 2);
    expect(await store.hasFor('entry-1'), isTrue);
  });

  test('removeOne and removeEntry keep other entries intact', () async {
    final a = incoming('one.jpg');
    await store.attach('entry-1', [a.path]);
    final b = incoming('two.jpg');
    await store.attach('entry-2', [b.path]);
    final first = (await store.forEntryPaths('entry-1')).single;
    await store.removeOne(first);
    expect(await store.hasFor('entry-1'), isFalse);
    expect(await store.hasFor('entry-2'), isTrue);
    await store.removeEntry('entry-2');
    expect(await store.hasFor('entry-2'), isFalse);
  });

  test('orphan cleanup removes deleted entries and stale captures', () async {
    final a = incoming('one.jpg');
    await store.attach('live', [a.path]);
    incoming('stale.jpg');
    final removed = await store.cleanOrphans({'live'});
    expect(removed, greaterThan(0));
    expect(await store.hasFor('live'), isTrue);
    expect(await store.incoming().list().isEmpty, isTrue);
  });

  test('usage counts files and clearAll empties the store', () async {
    final a = incoming('one.jpg');
    await store.attach('entry', [a.path]);
    final before = await store.usage();
    expect(before.count, 1);
    expect(before.bytes, 4);
    expect(formatBytes(4), '4 B');
    await store.clearAll();
    final after = await store.usage();
    expect(after.count, 0);
    expect(await store.hasFor('entry'), isFalse);
  });
}
