// Deterministic builder for the phone-hosted "Show on PC" web bundle.
//
// Why this exists: `assets/webapp/` used to be refreshed by hand
// (`flutter build web` + manual copy), so it silently lagged the app
// (1.3.0 bundle inside a 1.3.1 APK). This tool makes the flow explicit,
// version-checked, and CI-runnable.
//
// Usage (from the repo root):
//   dart tool/build_embedded_web.dart          # build + copy + verify
//   dart tool/build_embedded_web.dart --check  # verify only, no build
//
// It exits non-zero on any mismatch, so CI can gate on it.
import 'dart:convert';
import 'dart:io';

const _webFlags = [
  'build',
  'web',
  '--release',
  '--no-tree-shake-icons',
  '--pwa-strategy',
  'none',
  // NOTE: no --base-href. The embedded bundle is served from the phone-host
  // root URL, so it must stay root-relative. The GitHub Pages build (which
  // needs --base-href /<repo>/) is a separate artifact built by CI.
];

const _requiredFiles = [
  'index.html',
  'flutter_bootstrap.js',
  'main.dart.js',
  'version.json',
  'manifest.json',
];

void _fail(String message) {
  stderr.writeln('build_embedded_web: ERROR: $message');
  exit(1);
}

/// `1.3.1+2` -> ('1.3.1', '2').
(String, String) _splitVersion(String raw) {
  final parts = raw.split('+');
  if (parts.length != 2 || parts.any((p) => p.isEmpty)) {
    _fail('unparseable pubspec version "$raw" (want name+number)');
  }
  return (parts[0], parts[1]);
}

String _readVersion(String path, RegExp pattern, String what) {
  final text = File(path).readAsStringSync();
  final match = pattern.firstMatch(text);
  if (match == null) _fail('could not find $what in $path');
  return match![1]!;
}

void _verifyBundle(Directory webapp, String wantName, String wantNumber) {
  for (final name in _requiredFiles) {
    if (!File('${webapp.path}/$name').existsSync()) {
      _fail('missing required file $name in ${webapp.path}');
    }
  }
  final meta = jsonDecode(
      File('${webapp.path}/version.json').readAsStringSync());
  if (meta is! Map) _fail('version.json is not an object');
  final version = '${meta['version']}';
  final buildNumber = '${meta['build_number']}';
  if (version != wantName || buildNumber != wantNumber) {
    _fail('embedded bundle is $version+$buildNumber, app is '
        '$wantName+$wantNumber (stale bundle)');
  }
  final index =
      File('${webapp.path}/index.html').readAsStringSync();
  if (!index.contains('<base href="/">')) {
    _fail('index.html is not root-relative (Pages base-href leaked in?)');
  }
  stdout.writeln(
      'build_embedded_web: bundle OK ($version+$buildNumber, root-relative)');
}

void _copyDir(Directory from, Directory to) {
  for (final entity in from.listSync(recursive: false)) {
    final name = entity.path.split(Platform.pathSeparator).last;
    final target = '${to.path}${Platform.pathSeparator}$name';
    if (entity is File) {
      entity.copySync(target);
    } else if (entity is Directory) {
      final child = Directory(target)..createSync();
      _copyDir(entity, child);
    }
  }
}

Future<void> main(List<String> args) async {
  final checkOnly = args.contains('--check');
  final root = Directory.current;
  if (!File('${root.path}/pubspec.yaml').existsSync()) {
    _fail('run from the repo root (pubspec.yaml not found in ${root.path})');
  }

  final pubspecVersion =
      _readVersion('pubspec.yaml', RegExp(r'^version:\s*(\S+)', multiLine: true), 'version');
  final (wantName, wantNumber) = _splitVersion(pubspecVersion);
  final dartVersion = _readVersion('lib/version.dart',
      RegExp(r"kAppVersion\s*=\s*'([^']+)'"), 'kAppVersion');
  if (dartVersion != wantName) {
    _fail('lib/version.dart kAppVersion $dartVersion != pubspec $wantName');
  }

  final webapp = Directory('${root.path}/assets/webapp');
  if (checkOnly) {
    _verifyBundle(webapp, wantName, wantNumber);
    return;
  }

  stdout.writeln('build_embedded_web: flutter ${_webFlags.join(' ')}');
  // Direct launch (no shell): on Windows the entry point is flutter.bat.
  final flutterBin = Platform.isWindows ? 'flutter.bat' : 'flutter';
  final build = await Process.start(flutterBin, _webFlags,
      workingDirectory: root.path,
      mode: ProcessStartMode.inheritStdio);
  final code = await build.exitCode;
  if (code != 0) _fail('flutter build web exited $code');

  final fresh = Directory('${root.path}/build/web');
  // The APK must bundle assets/webapp/ (the phone host serves it), so
  // `flutter build web` faithfully embeds the OLD bundle inside the NEW one
  // at build/web/assets/assets/webapp/. Copying that back would nest bundles
  // forever and balloon the APK. Prune it: nothing requests those paths
  // (missing assets fall back to index.html in the host anyway).
  final selfEmbed = Directory('${fresh.path}/assets/'
      'assets/webapp');
  if (selfEmbed.existsSync()) {
    stdout.writeln(
        'build_embedded_web: pruning self-embedded old bundle');
    selfEmbed.deleteSync(recursive: true);
  }
  _verifyBundle(fresh, wantName, wantNumber);

  if (webapp.existsSync()) webapp.deleteSync(recursive: true);
  webapp.createSync(recursive: true);
  _copyDir(fresh, webapp);
  stdout.writeln('build_embedded_web: copied build/web -> assets/webapp');
  _verifyBundle(webapp, wantName, wantNumber);
}
