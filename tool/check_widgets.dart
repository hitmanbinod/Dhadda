import 'dart:io';

const allowed = {
  'FrameLayout', 'LinearLayout', 'RelativeLayout', 'TextView',
  'ImageView', 'ImageButton', 'Button', 'ProgressBar',
};

// Usage: dart run tool/check_widgets.dart [widget_name]
void main(List<String> args) {
  final key = args.isEmpty ? '' : args.first.replaceFirst('widget_', '').toLowerCase();
  var errors = 0;
  final ids = <String>{};
  final layoutDir = Directory('android/app/src/main/res/layout');
  for (final f in layoutDir.listSync().whereType<File>()) {
    final name = f.uri.pathSegments.last;
    if (!name.startsWith('widget_')) continue;
    final text = f.readAsStringSync();
    for (final m in RegExp(r'@\+id/(\w+)').allMatches(text)) {
      ids.add(m.group(1)!);
    }
    if (key.isNotEmpty && !name.toLowerCase().contains(key)) continue;
    for (final m in RegExp(r'<([A-Za-z][A-Za-z0-9_.]*)').allMatches(text)) {
      final tag = m.group(1)!;
      if (!allowed.contains(tag)) {
        print('FAIL $name: <$tag> is not allowed in a widget');
        errors++;
      }
    }
    for (final bad in ['?attr/', '?android:attr/', 'app:', '@font/', 'tools:']) {
      if (text.contains(bad)) {
        print('FAIL $name: contains $bad');
        errors++;
      }
    }
  }
  final src = Directory('android/app/src/main');
  for (final f in src.listSync(recursive: true).whereType<File>()) {
    final lower = f.path.toLowerCase();
    if (!lower.endsWith('.kt') || !lower.contains('widget')) continue;
    if (key.isNotEmpty && !lower.contains(key)) continue;
    for (final m in RegExp(r'R\.id\.(\w+)').allMatches(f.readAsStringSync())) {
      if (!ids.contains(m.group(1)!)) {
        print('FAIL ${f.path}: R.id.${m.group(1)} is not in any widget_ layout');
        errors++;
      }
    }
  }
  if (errors > 0) {
    print('$errors problem(s) found. Fix them.');
    exit(1);
  }
  print('Widget check passed.');
}
