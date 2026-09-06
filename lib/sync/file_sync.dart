import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

/// Option 1: manual backup file. Works on Android / Windows / Web,
/// uses only in-memory bytes (no dart:io) so Web builds keep compiling.
class FileSync {
  static String fileNameFor(DateTime when) {
    final d =
        '${when.year.toString().padLeft(4, '0')}-${when.month.toString().padLeft(2, '0')}-${when.day.toString().padLeft(2, '0')}';
    return 'expense-$d.json';
  }

  /// Shares [json] as a file. Falls back to a copy-paste dialog when
  /// sharing is unavailable (some desktop / web setups).
  static Future<void> exportJson(
      BuildContext context, String json, String filename) async {
    try {
      await SharePlus.instance.share(ShareParams(
        files: [
          XFile.fromData(Uint8List.fromList(utf8.encode(json)),
              name: filename, mimeType: 'application/json'),
        ],
        text: 'Expense backup',
      ));
      return;
    } catch (_) {
      // Fall through to copy dialog.
    }
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Copy backup JSON'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(child: SelectableText(json)),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: json));
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
            child: const Text('Copy & close'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  /// Lets the user pick a previously exported .json backup.
  /// Returns the raw JSON string, or null if cancelled / unreadable.
  static Future<String?> importJson() async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json', 'JSON'],
      );
      if (files.isEmpty) return null;
      final bytes = await files.first.readAsBytes();
      return utf8.decode(bytes);
    } catch (_) {
      return null;
    }
  }

  static String buildCsv(
      String Function(String categoryId) categoryName, List<dynamic> txns) {
    final buf = StringBuffer('date,type,amount,category,mode,note\n');
    for (final t in txns) {
      buf.writeln(
          '${t.dateTime.toIso8601String()},${t.type},${t.amount},${categoryName(t.categoryId)},${t.mode},${t.note.replaceAll(',', ';').replaceAll('\n', ' ')}');
    }
    return buf.toString();
  }
}