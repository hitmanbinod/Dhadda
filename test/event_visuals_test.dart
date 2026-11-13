import 'dart:io';
import 'dart:ui' as ui;

import 'package:expense/screens/history_screen.dart';
import 'package:expense/store.dart';
import 'package:expense/widgets/event_share.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Visual checks for the event branch view and the share card. Both
/// render to PNG files under build/ (gitignored) so the output can be
/// eyeballed; the pass/fail assertions are structural so CI never
/// depends on pixel-identical fonts.
void main() {
  setUpAll(() async {
    // Real typeface so the captures carry readable text instead of the
    // Ahem boxes (the SDK ships Roboto in its cache).
    final root = Platform.environment['FLUTTER_ROOT'];
    if (root == null) return;
    final dir = Directory('$root/bin/cache/artifacts/material_fonts');
    if (!dir.existsSync()) return;
    final loader = FontLoader('Roboto');
    for (final f in dir.listSync().whereType<File>()) {
      if (!f.path.endsWith('.ttf')) continue;
      final bytes = await f.readAsBytes();
      loader.addFont(Future.value(ByteData.view(bytes.buffer)));
    }
    await loader.load();
  });

  ExpenseStore makeStore() {
    SharedPreferences.setMockInitialValues({});
    return ExpenseStore();
  }

  Future<Uint8List> capture(WidgetTester tester, GlobalKey key) async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image =
        await tester.runAsync(() => boundary.toImage(pixelRatio: 1.0));
    final data = await tester.runAsync(() async {
      if (image == null) return null;
      return image.toByteData(format: ui.ImageByteFormat.png);
    });
    return data!.buffer.asUint8List();
  }

  void write(String name, List<int> bytes) {
    final out = File('build/visual_checks/$name');
    out.parent.createSync(recursive: true);
    out.writeAsBytesSync(bytes);
  }

  testWidgets('event branch view renders the tagged entries', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final store = makeStore();
    await store.load();
    final trekId = await store.addProject('Trek', 'Annapurna weekend with friends');
    await store.addTransaction(
        type: 'expense',
        amount: 250,
        categoryId: 'food',
        date: DateTime(2026, 10, 10, 9),
        note: 'Momo',
        mode: 'cash',
        projectId: trekId);
    await store.addTransaction(
        type: 'expense',
        amount: 700,
        categoryId: 'travel',
        date: DateTime(2026, 10, 11, 14),
        note: 'Jeep to Besisahar',
        mode: 'bank',
        projectId: trekId);
    await store.addTransaction(
        type: 'income',
        amount: 450,
        categoryId: 'other',
        date: DateTime(2026, 10, 12, 19),
        note: 'Split from Sita',
        mode: 'ewallet',
        projectId: trekId);

    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MaterialApp(
          home: ChangeNotifierProvider<ExpenseStore>.value(
            value: store,
            child: const Scaffold(body: HistoryScreen()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Events'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Trek'));
    await tester.pumpAndSettle();

    // The branch shows every tagged entry, newest first, plus actions.
    expect(find.text('Split from Sita'), findsOneWidget);
    expect(find.text('Jeep to Besisahar'), findsOneWidget);
    expect(find.text('Momo'), findsOneWidget);
    expect(find.text('Share'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);

    write('event_branch.png', await capture(tester, key));
  });

  testWidgets('share card renders a minimal detailed PNG', (tester) async {
    final store = makeStore();
    await store.load();
    final trekId = await store.addProject('Trek', 'Annapurna weekend with friends');
    for (var i = 0; i < 6; i++) {
      await store.addTransaction(
          type: i == 5 ? 'income' : 'expense',
          amount: 100.0 * (i + 1),
          categoryId: i.isEven ? 'food' : 'travel',
          date: DateTime(2026, 10, 10 + i, 9 + i),
          note: i == 5 ? 'Split from Sita' : 'Day ${i + 1} costs',
          mode: 'cash',
          projectId: trekId);
    }
    final trek = store.projectOf(trekId);
    final png = await tester.runAsync(
        () => buildEventCardForTest(store, trek));
    expect(png, isNotNull);
    expect(png!.length, greaterThan(10000));
    write('event_card.png', png);
  });
}
