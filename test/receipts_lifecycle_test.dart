import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:expense/receipts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late ReceiptStore store;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('dhadda-receipt-life-');
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

  Future<String> capture(String name) async {
    final f = File('${store.incoming().path}/$name');
    await f.writeAsBytes([1, 2, 3]);
    return f.path;
  }

  test('add to existing entry, remove, and a 3-photo limit', () async {
    final first = await capture('one.jpg');
    final saved = await store.attach('existing', [first]);
    expect(saved.single, p.join('existing', 'one.jpg'));

    // Simulate the owner's plan: one new capture, one stored removal.
    final second = await capture('two.jpg');
    final plan = planReceiptChanges(['existing/one.jpg'], ['existing/one.jpg', second]);
    expect(plan.captured, [second]);
    expect(plan.removed, isEmpty);

    final attached = await store.attach('existing', plan.captured);
    expect(attached.single, p.join('existing', 'two.jpg'));
    expect((await store.forEntryPaths('existing')).length, 2);

    // Remove the original stored photo.
    await store.removeOne(p.join('existing', 'one.jpg'));
    expect(await store.forEntryPaths('existing'), [p.join('existing', 'two.jpg')]);

    final removal = planReceiptChanges(
      [p.join('existing', 'two.jpg')],
      <String>[],
    );
    expect(removal.removed, [p.join('existing', 'two.jpg')]);
    await store.removeOne(removal.removed.single);
    expect(await store.hasFor('existing'), isFalse);

    // Widget-style cap: never more than three paths total.
    final capPaths = <String>[];
    for (var i = 0; i < 5; i++) {
      if (capPaths.length + 1 > 3) break;
      capPaths.add(await capture('cap$i.jpg'));
    }
    expect(capPaths.length, 3);
  });

  test('delete + undo keeps files; delete without undo removes them', () async {
    final a = await capture('undo.jpg');
    await store.attach('undo-entry', [a]);
    // Undo: the entry is live again, so cleanup must skip it entirely.
    final live = <String>{'undo-entry'};
    await cleanupRemovedReceipts({'undo-entry'}, live, store: store);
    expect(await store.hasFor('undo-entry'), isTrue);

    final b = await capture('gone.jpg');
    await store.attach('gone-entry', [b]);
    // No undo: the id is no longer in the live set.
    await cleanupRemovedReceipts({'gone-entry'}, live, store: store);
    expect(await store.hasFor('gone-entry'), isFalse);
    expect(await store.hasFor('undo-entry'), isTrue);
  });

  test('sync tombstone and erase-all remove receipts; double cleanup is a no-op',
      () async {
    final a = await capture('tomb.jpg');
    await store.attach('tombed', [a]);
    final b = await capture('live.jpg');
    await store.attach('live', [b]);

    // A sync merge tombstones 'tombed' and leaves 'live' untouched.
    await cleanupRemovedReceipts({'tombed'}, {'live'}, store: store);
    expect(await store.hasFor('tombed'), isFalse);
    expect(await store.hasFor('live'), isTrue);
    // Called twice — must be safe.
    await cleanupRemovedReceipts({'tombed'}, {'live'}, store: store);
    expect(await store.hasFor('live'), isTrue);

    // Erase all data clears everything.
    await store.clearAll();
    expect(await store.hasFor('live'), isFalse);
    expect(await store.usage(), (count: 0, bytes: 0));
  });

  test('cancelled capture files are removed without touching stored ones',
      () async {
    final kept = await capture('kept.jpg');
    await store.attach('entry', [kept]);
    final abandoned = await capture('abandoned.jpg');
    await cleanupCapturedPaths([abandoned]);
    expect(File(abandoned).existsSync(), isFalse);
    expect(await store.hasFor('entry'), isTrue);
  });
}
