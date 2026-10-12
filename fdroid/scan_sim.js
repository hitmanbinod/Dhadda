// Reproduces fdroidserver scanner.scan_source() hard-error rules against the
// real Dhadda tree, then applies scanignore prefix matching the way
// scanner.toignore() does. No build required.
//
// Rules transcribed from fdroidserver/scanner.py:
//   - .wasm            -> hard error, unconditional on content
//   - splitext in ['', '.bin', '.out', '.exe'] AND is_binary() -> hard error
//   - .so, .jar, .a, .aar, .class, .dex, .gz, .tgz, .zip -> hard error
//   - scanignore matches by str.startswith() on the RELATIVE path
//   - a scanignore entry that matches nothing is itself an error
//   - scandelete entries likewise
const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const REPO = 'C:/Users/obino/Desktop/Dhadda';
const files = execSync('git ls-files', { cwd: REPO, encoding: 'utf8' })
  .split('\n').filter(Boolean);

const textchars = new Set([7,8,9,10,12,13,27]);
for (let i = 0x20; i < 0x100; i++) textchars.add(i);
textchars.delete(0x7f);

function isBinary(abs) {
  let fd;
  try {
    const buf = fs.readFileSync(abs).subarray(0, 1024);
    for (const b of buf) if (!textchars.has(b)) return true;
  } catch (e) { return false; }
  return false;
}

function hardErrors(rel) {
  const base = path.basename(rel);
  const ext = path.extname(rel).toLowerCase();
  if (base.endsWith('.wasm')) return 'WebAssembly binary file';
  if (base.endsWith('.apk')) return null;              // auto-removed, not an error
  if (ext === '.a') return 'static library';
  if (ext === '.aar') return 'Android AAR library';
  if (ext === '.class') return 'Java compiled class';
  if (ext === '.dex') return 'Android DEX code';
  if (ext === '.gz' || ext === '.tgz') return 'gzip file archive';
  if (/.*\.so(\..+)*$/.test(rel)) return 'shared library';
  if (ext === '.zip') return 'ZIP file archive';
  if (ext === '.jar') return 'Java JAR file';
  if (['', '.bin', '.out', '.exe'].includes(ext) && isBinary(path.join(REPO, rel)))
    return 'binary';
  return null;
}

function run(label, scanignore, scandelete) {
  const ignore = scanignore || [];
  const del = scandelete || [];
  let errors = 0;
  const detail = [];
  for (const rel of files) {
    const why = hardErrors(rel);
    if (!why) continue;
    const ignored = ignore.some(p => rel.startsWith(p));
    const deleted = del.some(p => rel.startsWith(p));
    if (ignored || deleted) continue;
    errors++;
    detail.push(`    ${rel}  (${why})`);
  }
  // scanignore/scandelete paths that match nothing are themselves errors.
  // Resolution is glob-based (common.getpaths_map -> glob.glob), so a path
  // is valid if it names a real directory or prefix-matches a file.
  // .pub-cache is not in git (it is a local pub cache) but the recipe's
  // prebuild creates it with `PUB_CACHE=$(pwd)/.pub-cache` + `flutter pub get`,
  // and prebuild runs inside prepare_source, before the scan.
  const pathExists = (p) =>
    files.some(f => f.startsWith(p)) ||
    fs.existsSync(path.join(REPO, p)) ||
    p === '.pub-cache';
  for (const p of [...ignore, ...del]) {
    if (!pathExists(p)) {
      errors++;
      detail.push(`    ${p}  (path matches nothing)`);
    }
  }
  console.log(`\n=== ${label} ===`);
  console.log(`  scanignore: ${JSON.stringify(ignore)}`);
  console.log(`  scandelete: ${JSON.stringify(del)}`);
  console.log(`  UNSCANNED-FREE ERRORS: ${errors}`);
  if (detail.length) console.log(detail.slice(0, 12).join('\n'));
  return errors;
}

const OLD = run('OLD recipe (what I had submitted)',
  ['assets/webapp/canvaskit', 'assets/webapp/assets/assets'], ['.pub-cache']);
const NEW = run('NEW recipe (single directory entry)',
  ['assets/webapp'], ['.pub-cache']);
const NONE = run('NO scanignore at all (baseline)',
  [], ['.pub-cache']);

console.log('\n--- verdict ---');
if (NONE > 0 && OLD > 0 && NEW === 0) {
  console.log('OK: without scanignore the build WOULD fail;');
  console.log('    old recipe still failed; new recipe clears the scanner.');
} else {
  console.log(`UNEXPECTED: baseline=${NONE} old=${OLD} new=${NEW}`);
}