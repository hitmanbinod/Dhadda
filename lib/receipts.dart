// Receipt photos live ONLY in app-private files. Never in the database,
// never in sync payloads or JSON/CSV backups. This service owns their layout
// and lifecycle; the native side only writes shrunken JPEGs into `incoming`.
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class ReceiptStore {
  ReceiptStore(this.root);

  /// Injectable for tests. Production uses `await ReceiptStore.create()`.
  final Directory root;

  static Future<ReceiptStore> create() async {
    final dir = await getApplicationDocumentsDirectory();
    return ReceiptStore(Directory(p.join(dir.path, 'receipts')));
  }

  Directory incoming() => Directory(p.join(root.path, 'incoming'));

  Directory forEntry(String entryId) => Directory(p.join(root.path, entryId));

  Future<void> ensure() async {
    await root.create(recursive: true);
    await incoming().create(recursive: true);
  }

  /// Moves freshly captured files from `incoming` under the saved entry id.
  Future<List<String>> attach(String entryId, Iterable<String> incomingPaths) async {
    await ensure();
    final target = forEntry(entryId);
    await target.create(recursive: true);
    final saved = <String>[];
    for (final path in incomingPaths) {
      final source = File(path);
      if (!await source.exists()) continue;
      final dest = File(p.join(target.path, p.basename(path)));
      await source.copy(dest.path);
      await source.delete();
      saved.add(p.relative(dest.path, from: root.path));
    }
    return saved;
  }

  Future<List<String>> forEntryPaths(String entryId) async {
    final dir = forEntry(entryId);
    if (!await dir.exists()) return [];
    return [
      for (final f in dir.listSync().whereType<File>())
        p.relative(f.path, from: root.path),
    ]..sort();
  }

  Future<bool> hasFor(String entryId) async {
    final dir = forEntry(entryId);
    if (!await dir.exists()) return false;
    return await dir.list().any((_) => true);
  }

  Future<void> removeOne(String relativePath) async {
    try {
      await File(p.join(root.path, relativePath)).delete();
    } catch (_) {}
  }

  Future<void> removeEntry(String entryId) async {
    try {
      await forEntry(entryId).delete(recursive: true);
    } catch (_) {}
  }

  /// Deletes files for entries that no longer exist (permanent delete, sync
  /// removal, undo/erase) plus stale incoming captures on app start.
  Future<int> cleanOrphans(Set<String> liveEntryIds) async {
    await ensure();
    var removed = 0;
    for (final d in root.listSync().whereType<Directory>()) {
      if (d.path == incoming().path) continue;
      if (!liveEntryIds.contains(p.basename(d.path))) {
        await d.delete(recursive: true);
        removed++;
      }
    }
    for (final f in incoming().listSync().whereType<File>()) {
      await f.delete();
      removed++;
    }
    return removed;
  }

  Future<void> clearAll() async {
    try {
      await root.delete(recursive: true);
    } catch (_) {}
    await ensure();
  }

  Future<({int count, int bytes})> usage() async {
    if (!await root.exists()) return (count: 0, bytes: 0);
    var count = 0;
    var bytes = 0;
    for (final f in root.listSync(recursive: true).whereType<File>()) {
      count++;
      bytes += await f.length();
    }
    return (count: count, bytes: bytes);
  }
}

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
