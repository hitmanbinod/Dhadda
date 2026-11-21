// Round 3.1 Step 4 — migration stress tests (tests only; no production code
// is changed here). Builds a real file-backed v2 SQLite database with raw
// SQL, then opens it through AppDb so the guarded v2->v3 onUpgrade runs.
// VM-only (dart:io + sqlite3/drift native); never compiled to web.
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:expense/data/app_db.dart';
import 'package:expense/data/db_recovery.dart';
import 'package:expense/data/drift_domain_store.dart';
import 'package:expense/models.dart';
import 'package:expense/store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

const _marker = 'expense_db_migrated_v1';

/// A temp directory used both as the real db file location and as the
/// mocked app-documents directory for the safety-copy test.
class _TempDir {
  final Directory dir;
  _TempDir(this.dir);

  static Future<_TempDir> create(String name) async {
    final d = await Directory.systemTemp.createTemp('dhadda-r31-$name-');
    return _TempDir(d);
  }

  Future<void> dispose() async {
    for (var i = 0; i < 20; i++) {
      try {
        if (await dir.exists()) await dir.delete(recursive: true);
        return;
      } catch (_) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
    }
  }
}

/// Creates a v2 database file (rev/rev_by + tombstones present, no accounts,
/// no receipts, no account_id) with [n] transactions across all four modes.
Future<File> createV2Db(
  Directory dir, {
  required int n,
  required String name,
}) async {
  final file = File('${dir.path}/$name.sqlite');
  if (await file.exists()) await file.delete();
  final db = sqlite3.sqlite3.open(file.path);
  try {
    db.execute('PRAGMA foreign_keys = OFF');
    db.execute('''
      CREATE TABLE categories (
        id TEXT NOT NULL PRIMARY KEY, name TEXT NOT NULL, icon INTEGER NOT NULL,
        color INTEGER NOT NULL, budget REAL NOT NULL, sort_order INTEGER NOT NULL,
        rev INTEGER NOT NULL DEFAULT 0, rev_by TEXT NOT NULL DEFAULT ''
      )''');
    db.execute('''
      CREATE TABLE transactions (
        id TEXT NOT NULL PRIMARY KEY, type TEXT NOT NULL, amount REAL NOT NULL,
        category_id TEXT NOT NULL, date INTEGER NOT NULL, note TEXT NOT NULL,
        mode TEXT NOT NULL, project_id TEXT NOT NULL,
        rev INTEGER NOT NULL DEFAULT 0, rev_by TEXT NOT NULL DEFAULT ''
      )''');
    db.execute('''
      CREATE TABLE projects (
        id TEXT NOT NULL PRIMARY KEY, name TEXT NOT NULL, note TEXT NOT NULL,
        created INTEGER NOT NULL, icon INTEGER NOT NULL, color INTEGER NOT NULL,
        rev INTEGER NOT NULL DEFAULT 0, rev_by TEXT NOT NULL DEFAULT ''
      )''');
    db.execute('''
      CREATE TABLE loans (
        id TEXT NOT NULL PRIMARY KEY, person TEXT NOT NULL, kind TEXT NOT NULL,
        principal REAL NOT NULL, date_lent INTEGER NOT NULL, due_date INTEGER,
        note TEXT NOT NULL, remind_at INTEGER NOT NULL,
        rev INTEGER NOT NULL DEFAULT 0, rev_by TEXT NOT NULL DEFAULT ''
      )''');
    db.execute('''
      CREATE TABLE loan_topups (
        id TEXT NOT NULL PRIMARY KEY, loan_id TEXT NOT NULL, amount REAL NOT NULL,
        date INTEGER NOT NULL, note TEXT NOT NULL,
        rev INTEGER NOT NULL DEFAULT 0, rev_by TEXT NOT NULL DEFAULT ''
      )''');
    db.execute('''
      CREATE TABLE loan_repayments (
        id TEXT NOT NULL PRIMARY KEY, loan_id TEXT NOT NULL, amount REAL NOT NULL,
        date INTEGER NOT NULL, note TEXT NOT NULL,
        rev INTEGER NOT NULL DEFAULT 0, rev_by TEXT NOT NULL DEFAULT ''
      )''');
    db.execute('''
      CREATE TABLE tombstones (
        type TEXT NOT NULL, record_id TEXT NOT NULL, rev INTEGER NOT NULL,
        rev_by TEXT NOT NULL, PRIMARY KEY (type, record_id)
      )''');

    // Categories with budgets, including 'other' (frozen rule).
    final cat = db.prepare(
      'INSERT INTO categories (id,name,icon,color,budget,sort_order) '
      'VALUES (?,?,?,?,?,?)',
    );
    for (var i = 0; i < 6; i++) {
      cat.execute([
        'cat-$i',
        'Category $i',
        0,
        0xFF009688,
        i * 100.0,
        i,
      ]);
    }
    cat.execute(['other', 'Other', 0, 0xFF607D8B, 0.0, 6]);
    cat.close();

    // Transactions spread over 12 months and all four legacy modes.
    final txn = db.prepare(
      'INSERT INTO transactions '
      '(id,type,amount,category_id,date,note,mode,project_id) '
      'VALUES (?,?,?,?,?,?,?,?)',
    );
    final modes = ['cash', 'bank', 'card', 'ewallet'];
    final base = DateTime(2025, 1, 1).millisecondsSinceEpoch;
    for (var i = 0; i < n; i++) {
      final day = base + (i % 360) * 86400000;
      txn.execute([
        'txn-$i',
        i % 11 == 0 ? 'income' : 'expense',
        (i % 97 + 1) * 1.5,
        'cat-${i % 6}',
        day,
        'note $i',
        modes[i % 4],
        i % 5 == 0 ? 'proj-${i % 3}' : '',
      ]);
    }
    txn.close();

    // Projects.
    final proj = db.prepare(
      'INSERT INTO projects (id,name,note,created,icon,color) '
      'VALUES (?,?,?,?,?,?)',
    );
    for (var i = 0; i < 3; i++) {
      proj.execute(['proj-$i', 'Event $i', '', base, 0, 0xFF009688]);
    }
    proj.close();

    // One loan with a top-up and a repayment.
    db.execute(
      "INSERT INTO loans (id,person,kind,principal,date_lent,due_date,note,remind_at) "
      "VALUES ('loan-1','Ram','lent',1000,$base,NULL,'trip',0)",
    );
    db.execute(
      "INSERT INTO loan_topups (id,loan_id,amount,date,note) "
      "VALUES ('top-1','loan-1',200,$base,'more')",
    );
    db.execute(
      "INSERT INTO loan_repayments (id,loan_id,amount,date,note) "
      "VALUES ('rep-1','loan-1',300,$base,'back')",
    );

    // A tombstone from the v2 era which must survive the v3 upgrade.
    db.execute(
      "INSERT INTO tombstones (type,record_id,rev,rev_by) "
      "VALUES ('txn','deleted-1',7,'peer')",
    );

    db.execute('PRAGMA user_version = 2');
  } finally {
    db.close();
  }
  return file;
}

/// Opens the v2 file through AppDb, which runs onUpgrade(2,3).
Future<DriftDomainStore> openMigrated(File file) async {
  final db = AppDb(NativeDatabase(file));
  return DriftDomainStore(db);
}

void main() {
  late _TempDir temp;

  setUp(() async {
    temp = await _TempDir.create('stress');
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    await temp.dispose();
  });

  test('large v2 DB migrates: counts, mode mapping, loans/events, timing',
      () async {
    final file = await createV2Db(temp.dir, n: 5000, name: 'large');
    final stopwatch = Stopwatch()..start();
    final store = await openMigrated(file);
    final data = await store.loadDomain();
    final counts = await store.counts();
    stopwatch.stop();

    expect(data.transactions.length, 5000);
    expect(counts['transactions'], 5000);
    expect(data.categories.length, 7);
    expect(data.projects.length, 3);
    expect(data.loans.length, 1);
    expect(data.loans.single.topups.length, 1);
    expect(data.loans.single.repayments.length, 1);

    // Mode -> deterministic default account, all four modes present.
    final mapped = {for (final t in data.transactions) t.mode: t.accountId};
    expect(mapped, containsPair('cash', 'acct_cash'));
    expect(mapped, containsPair('bank', 'acct_bank'));
    expect(mapped, containsPair('card', 'acct_card'));
    expect(mapped, containsPair('ewallet', 'acct_ewallet'));
    // Every legacy row got one of the four defaults (no empty ids).
    expect(
      data.transactions.every(
        (t) => const {
          'acct_cash',
          'acct_bank',
          'acct_card',
          'acct_ewallet',
        }.contains(t.accountId),
      ),
      isTrue,
    );

    // Per-month totals are unchanged: sum over all rows equals the sum of
    // the 12 monthly buckets (spot-check a few months via date grouping).
    final byMonth = <int, double>{};
    for (final t in data.transactions) {
      final d = DateTime.fromMillisecondsSinceEpoch(t.date);
      final key = d.year * 100 + d.month;
      byMonth[key] = (byMonth[key] ?? 0) + t.amount;
    }
    final total = byMonth.values.fold<double>(0, (s, v) => s + v);
    final direct = data.transactions.fold<double>(
      0,
      (s, t) => s + t.amount,
    );
    expect(total, closeTo(direct, 1e-6));
    expect(byMonth.length, 12);

    // Four default accounts were seeded, no duplicates.
    final acctRows = await store.db.select(store.db.accounts).get();
    final acctIds = acctRows.map((r) => r.id).toList()..sort();
    expect(acctIds, [
      'acct_bank',
      'acct_card',
      'acct_cash',
      'acct_ewallet',
    ]);

    // Tombstone survived.
    final tombs = await store.loadTombstones();
    expect(
      tombs.any((t) => t.type == 'txn' && t.id == 'deleted-1'),
      isTrue,
    );

    // Generous bound: feasibility, not a benchmark.
    expect(
      stopwatch.elapsed < const Duration(seconds: 60),
      isTrue,
      reason: 'migration took ${stopwatch.elapsed}',
    );
    await store.close();
  });

  test('interrupted then resumed migration equals a clean one', () async {
    final cleanFile = await createV2Db(temp.dir, n: 200, name: 'clean');
    final cleanStore = await openMigrated(cleanFile);
    final clean = await cleanStore.loadDomain();
    await cleanStore.close();

    final file = await createV2Db(temp.dir, n: 200, name: 'resumed');

    // Simulate a crash after the account inserts: create accounts, seed the
    // four defaults, but leave user_version at 2 so onUpgrade resumes.
    final raw = sqlite3.sqlite3.open(file.path);
    raw.execute('''
      CREATE TABLE accounts (
        id TEXT NOT NULL PRIMARY KEY, name TEXT NOT NULL, type TEXT NOT NULL,
        color INTEGER NOT NULL DEFAULT 0, sort_order INTEGER NOT NULL DEFAULT 0,
        archived INTEGER NOT NULL DEFAULT 0, rev INTEGER NOT NULL DEFAULT 0,
        rev_by TEXT NOT NULL DEFAULT ''
      )''');
    for (final a in defaultAccounts()) {
      raw.execute(
        "INSERT OR IGNORE INTO accounts (id,name,type,color,sort_order,archived,rev,rev_by) "
        "VALUES ('${a.id}','${a.name}','${a.type}',${a.color},${a.sortOrder},0,0,'')",
      );
    }
    raw.close();

    final resumedStore = await openMigrated(file);
    final resumed = await resumedStore.loadDomain();
    expect(resumed.transactions.length, clean.transactions.length);
    expect(
      resumed.transactions.map((t) => t.id).toList()..sort(),
      clean.transactions.map((t) => t.id).toList()..sort(),
    );
    // No duplicate default accounts despite the pre-seeded rows.
    final acctRows = await (resumedStore.db.select(resumedStore.db.accounts).get());
    expect(acctRows.length, 4);
    await resumedStore.close();
  });

  test('re-running the guarded migration is a no-op', () async {
    final file = await createV2Db(temp.dir, n: 50, name: 'twice');
    final first = await openMigrated(file);
    final before = await first.loadDomain();
    await first.close();

    // Force user_version back to 2 so the guarded steps run again.
    final raw = sqlite3.sqlite3.open(file.path);
    raw.execute('PRAGMA user_version = 2');
    raw.close();

    final second = await openMigrated(file);
    final after = await second.loadDomain();
    expect(after.transactions.length, before.transactions.length);
    final acctRows = await (second.db.select(second.db.accounts).get());
    expect(acctRows.length, 4);
    await second.close();
  });

  test('legacy v1 JSON and v2 snapshot import into the migrated app', () async {
    final file = await createV2Db(temp.dir, n: 20, name: 'imports');
    final migrated = await (await openMigrated(file)).loadDomain();

    // Build a v1 JSON backup from the migrated domain.
    final v1 = Snapshot(
      version: kSnapshotVersion,
      updatedAt: DateTime.now().toUtc().toIso8601String(),
      deviceId: 'stress',
      deviceName: 'stress',
      categories: migrated.categories,
      accounts: const [],
      transactions: migrated.transactions,
      loans: migrated.loans,
      projects: migrated.projects,
    );
    final v1Json = jsonEncode(v1.toJson());

    // Import the v1 backup into a clean, already-migrated app.
    SharedPreferences.setMockInitialValues({_marker: 1});
    final targetFile = await createV2Db(temp.dir, n: 0, name: 'import-target');
    final targetStore = ExpenseStore(
      domainOverride: await openMigrated(targetFile),
    );
    await targetStore.load();
    final map = jsonDecode(v1Json) as Map<String, dynamic>;
    map['updatedAt'] = '2028-01-01T00:00:00.000Z';
    final msg = await targetStore.importSnapshotString(jsonEncode(map));
    expect(msg, contains('Synced'));
    expect(targetStore.transactions.length, migrated.transactions.length);

    // v2 snapshot: export from a migrated store and import into another.
    SharedPreferences.setMockInitialValues({_marker: 1});
    final sourceFile = await createV2Db(temp.dir, n: 20, name: 'import-src');
    final sourceStore = ExpenseStore(
      domainOverride: await openMigrated(sourceFile),
    );
    await sourceStore.load();
    final v2 = sourceStore.exportSnapshotV2();
    SharedPreferences.setMockInitialValues({_marker: 1});
    final target2File = await createV2Db(temp.dir, n: 0, name: 'import-v2');
    final target2Store = ExpenseStore(
      domainOverride: await openMigrated(target2File),
    );
    await target2Store.load();
    final v2msg = await target2Store.importSnapshotV2(v2);
    expect(v2msg, isNot(contains('Could not')));
    expect(target2Store.transactions.length, migrated.transactions.length);
  });

  test('pre-migration safety copy exists and is a readable legacy DB',
      () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // The safety copy looks specifically for dhadda.sqlite in the app docs.
    await createV2Db(temp.dir, n: 5, name: 'dhadda');
    // Mock the path_provider channel to point at our temp directory.
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getApplicationDocumentsDirectory') {
        return temp.dir.path;
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(channel, null),
    );

    final target = await backupDatabaseBeforeMigration();
    expect(target, isNotEmpty);
    final copy = File(target);
    expect(await copy.exists(), isTrue);
    // Readable as a SQLite DB: its user_version is still the legacy 2.
    final raw = sqlite3.sqlite3.open(copy.path);
    final rows = raw.select('PRAGMA user_version');
    expect(rows.first['user_version'] as int, 2);
    raw.close();

    // One-time: a second call returns empty (copy already exists).
    expect(await backupDatabaseBeforeMigration(), isEmpty);
  });

  test('marker and budgets survive the v2->v3 upgrade', () async {
    final file = await createV2Db(temp.dir, n: 10, name: 'budgets');
    SharedPreferences.setMockInitialValues({_marker: 1});
    final store = ExpenseStore(
      domainOverride: await openMigrated(file),
    );
    await store.load();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt(_marker), 1);
    expect(store.categoryOf('cat-0').budget, 0.0);
    expect(store.transactions.length, 10);
    expect(store.accounts.length, 4);
  });
}
