import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../format.dart';
import '../store.dart';

/// Shares an event as a clean minimal report card (PNG) plus a text
/// summary. The card is drawn directly on a canvas, so it needs no
/// widget tree and works on Android, desktop and web alike. Currency
/// appears as its code (NPR 1,250) rather than a glyph that canvas
/// fonts may not carry.
Future<void> shareEventReport(
  BuildContext context,
  ExpenseStore store,
  Project p,
) async {
  final txns = store.projectTxns(p.id).toList()
    ..sort((a, b) => b.date.compareTo(a.date));
  final summary = _textSummary(store, p, txns);
  try {
    final bytes = await _renderCard(store, p, txns);
    if (bytes != null) {
      await SharePlus.instance.share(ShareParams(
        files: [
          XFile.fromData(
            bytes,
            name: 'dhadda-${_safeName(p.name)}.png',
            mimeType: 'image/png',
          ),
        ],
        text: summary,
      ));
      return;
    }
  } catch (_) {
    // Fall through to the text dialog.
  }
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('${p.name} - summary'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(child: SelectableText(summary)),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: summary));
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

/// Renders the share card to PNG bytes. [visibleForTesting] hook so the
/// minimal-graphics layout can be golden-checked without involving the
/// share sheet.
@visibleForTesting
Future<Uint8List?> buildEventCardForTest(ExpenseStore store, Project p) {
  final txns = store.projectTxns(p.id).toList()
    ..sort((a, b) => b.date.compareTo(a.date));
  return _renderCard(store, p, txns);
}

String _safeName(String s) =>
    s.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-').trim().toLowerCase();

String _money(ExpenseStore store, double v) {
  final n = NumberFormat('#,##0.##').format(v);
  return '${store.currency} $n';
}

String _textSummary(
  ExpenseStore store,
  Project p,
  List<Txn> txns,
) {
  final spent = txns.fold(0.0, (s, t) => t.isExpense ? s + t.amount : s);
  final income = txns.fold(0.0, (s, t) => t.isExpense ? s : s + t.amount);
  final b = StringBuffer('${p.name} - event report');
  if (p.note.isNotEmpty) b.write('\n${p.note}');
  if (txns.isNotEmpty) {
    b.write('\n${_range(txns)}');
  }
  b.write('\nSpent ${_money(store, spent)} - Income ${_money(store, income)}'
      ' - ${txns.length} entries');
  final cats = _byCategory(store, txns);
  if (cats.isNotEmpty) {
    b.write('\n\nBy category:');
    for (final e in cats.take(10)) {
      b.write('\n- ${e.key}: ${_money(store, e.value)}');
    }
  }
  if (txns.isNotEmpty) {
    b.write('\n\nEntries:');
    for (final t in txns.take(15)) {
      b.write(
          '\n- ${dayStr(t.dateTime)} - ${t.note.isEmpty ? store.categoryOf(t.categoryId).name : t.note}'
          ' - ${t.isExpense ? '-' : '+'}${_money(store, t.amount)}');
    }
    if (txns.length > 15) b.write('\n- and ${txns.length - 15} more');
  }
  b.write('\n\nShared from Dhadda.');
  return b.toString();
}

String _range(List<Txn> txns) {
  final oldest = txns
      .map((t) => t.dateTime)
      .reduce((a, b) => a.isBefore(b) ? a : b);
  final newest = txns
      .map((t) => t.dateTime)
      .reduce((a, b) => a.isAfter(b) ? a : b);
  final f = DateFormat('d MMM y');
  return f.format(oldest) == f.format(newest)
      ? f.format(oldest)
      : '${f.format(oldest)} - ${f.format(newest)}';
}

List<MapEntry<String, double>> _byCategory(
  ExpenseStore store,
  List<Txn> txns,
) {
  final m = <String, double>{};
  for (final t in txns) {
    if (!t.isExpense) continue;
    final name = store.categoryOf(t.categoryId).name;
    m[name] = (m[name] ?? 0) + t.amount;
  }
  final entries = m.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return entries;
}

// ---------- card rendering ----------

const _cardW = 1000.0;
const _ink = Color(0xFF111827);
const _muted = Color(0xFF6B7280);
const _hair = Color(0xFFE5E7EB);
const _red = Color(0xFFB91C1C);
const _green = Color(0xFF047857);

ui.Paragraph _para(
  String s, {
  required double size,
  required double width,
  Color color = _ink,
  bool bold = false,
  ui.TextAlign align = ui.TextAlign.left,
}) {
  final b = ui.ParagraphBuilder(ui.ParagraphStyle(
    fontSize: size,
    fontWeight: bold ? ui.FontWeight.w700 : ui.FontWeight.w400,
    textAlign: align,
    maxLines: 1,
    ellipsis: '…',
    textDirection: ui.TextDirection.ltr,
  ))
    ..pushStyle(ui.TextStyle(color: color, fontSize: size,
        fontWeight: bold ? ui.FontWeight.w700 : ui.FontWeight.w400))
    ..addText(s);
  final para = b.build();
  para.layout(ui.ParagraphConstraints(width: width));
  return para;
}

Future<Uint8List?> _renderCard(
  ExpenseStore store,
  Project p,
  List<Txn> txns,
) async {
  final spent = txns.fold(0.0, (s, t) => t.isExpense ? s + t.amount : s);
  final income = txns.fold(0.0, (s, t) => t.isExpense ? s : s + t.amount);
  final cats = _byCategory(store, txns).take(8).toList();
  final shown = txns.take(14).toList();
  final accent = Color(p.color);

  const m = 56.0; // side margin
  final inner = _cardW - m * 2;

  // ---- Phase 1: compute every y position, then derive the card
  // height from them, so nothing can ever clip at the bottom. ----
  var y = 44.0;
  final eyebrowY = y;
  y += 40;
  final nameY = y;
  y += 76;
  final noteY = p.note.isNotEmpty ? y : null;
  if (noteY != null) y += 42;
  final rangeY = txns.isNotEmpty ? y : null;
  if (rangeY != null) y += 44;
  y += 28;
  final totalsY = y;
  y += 84;
  y += 30;
  final div1Y = y;
  y += 36;
  double? catsHeadY;
  final catYs = <double>[];
  if (cats.isNotEmpty) {
    catsHeadY = y;
    y += 50;
    for (final _ in cats) {
      catYs.add(y);
      y += 72;
    }
    y += 20;
  }
  double? entriesHeadY;
  final entryYs = <double>[];
  double? moreY;
  if (shown.isNotEmpty) {
    entriesHeadY = y;
    y += 50;
    for (final _ in shown) {
      entryYs.add(y);
      y += 60;
    }
    if (txns.length > shown.length) {
      moreY = y;
      y += 38;
    }
  }
  y += 24;
  final div2Y = y;
  final footY = y + 22;
  final h = footY + 58;

  // ---- Phase 2: draw at the computed positions. ----
  final recorder = ui.PictureRecorder();
  final c = ui.Canvas(recorder, ui.Rect.fromLTWH(0, 0, _cardW, h));

  // Background + accent band.
  c.drawRect(
      ui.Rect.fromLTWH(0, 0, _cardW, h), ui.Paint()..color = ui.Color(0xFFFFFFFF));
  c.drawRect(ui.Rect.fromLTWH(0, 0, _cardW, 12), ui.Paint()..color = accent);

  c.drawParagraph(_para('EVENT REPORT', size: 26, width: inner,
      color: accent, bold: true), ui.Offset(m, eyebrowY));
  c.drawParagraph(_para(p.name, size: 58, width: inner, bold: true),
      ui.Offset(m, nameY));
  if (noteY != null) {
    c.drawParagraph(_para(p.note, size: 30, width: inner, color: _muted),
        ui.Offset(m, noteY));
  }
  if (rangeY != null) {
    c.drawParagraph(_para(_range(txns), size: 30, width: inner, color: _muted),
        ui.Offset(m, rangeY));
  }

  // Totals row: three equal columns.
  final colW = inner / 3;
  void total(String label, String value, int col, Color colr) {
    final x = m + colW * col;
    c.drawParagraph(_para(label, size: 26, width: colW, color: _muted),
        ui.Offset(x, totalsY));
    c.drawParagraph(
        _para(value, size: 44, width: colW, bold: true, color: colr),
        ui.Offset(x, totalsY + 38));
  }

  total('SPENT', _money(store, spent), 0, _red);
  total('INCOME', _money(store, income), 1, _green);
  total('ENTRIES', '${txns.length}', 2, _ink);

  ui.Paint hair(ui.Color col) => ui.Paint()..color = col ..strokeWidth = 1;
  c.drawLine(ui.Offset(m, div1Y), ui.Offset(m + inner, div1Y), hair(_hair));

  final maxCat = cats.isEmpty ? 1.0 : cats.first.value;
  if (catsHeadY != null) {
    c.drawParagraph(_para('BY CATEGORY', size: 26, width: inner,
        color: _muted, bold: true), ui.Offset(m, catsHeadY));
    for (var i = 0; i < cats.length; i++) {
      final e = cats[i];
      final ry = catYs[i];
      c.drawParagraph(_para(e.key, size: 30, width: inner * 0.6),
          ui.Offset(m, ry));
      c.drawParagraph(
          _para(_money(store, e.value), size: 30, width: inner,
              bold: true, align: ui.TextAlign.right),
          ui.Offset(m, ry));
      final barY = ry + 44;
      c.drawRRect(
          ui.RRect.fromRectAndRadius(
              ui.Rect.fromLTWH(m, barY, inner, 8),
              const ui.Radius.circular(4)),
          ui.Paint()..color = _hair);
      if (e.value > 0) {
        c.drawRRect(
            ui.RRect.fromRectAndRadius(
                ui.Rect.fromLTWH(
                    m, barY, (inner * (e.value / maxCat)).clamp(8, inner), 8),
                const ui.Radius.circular(4)),
            ui.Paint()..color = accent);
      }
    }
  }

  if (entriesHeadY != null) {
    c.drawParagraph(_para('ENTRIES', size: 26, width: inner, color: _muted,
        bold: true), ui.Offset(m, entriesHeadY));
    final df = DateFormat('d MMM');
    for (var i = 0; i < shown.length; i++) {
      final t = shown[i];
      final ry = entryYs[i];
      final label = t.note.isEmpty
          ? store.categoryOf(t.categoryId).name
          : t.note;
      c.drawParagraph(
          _para('${df.format(t.dateTime)}  ·  $label', size: 30,
              width: inner * 0.7, color: _ink),
          ui.Offset(m, ry));
      c.drawParagraph(
          _para('${t.isExpense ? '-' : '+'}${_money(store, t.amount)}',
              size: 30,
              width: inner,
              bold: true,
              color: t.isExpense ? _red : _green,
              align: ui.TextAlign.right),
          ui.Offset(m, ry));
    }
    if (moreY != null) {
      c.drawParagraph(
          _para('and ${txns.length - shown.length} more', size: 28,
              width: inner, color: _muted),
          ui.Offset(m, moreY));
    }
  }

  c.drawLine(ui.Offset(m, div2Y), ui.Offset(m + inner, div2Y), hair(_hair));
  c.drawParagraph(
      _para('Shared from Dhadda - private by design', size: 26,
          width: inner, color: _muted),
      ui.Offset(m, footY));

  final pic = recorder.endRecording();
  try {
    final img = await pic.toImage(_cardW.round(), h.round());
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  } catch (_) {
    return null;
  }
}
