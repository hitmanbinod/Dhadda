import 'package:expense/format.dart';
import 'package:expense/store.dart';
import 'package:expense/sync/sms.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

/// Store platform that reads normally but refuses every write, the way the
/// web backend does when localStorage is full.
class _RefusingPrefs extends SharedPreferencesStorePlatform {
  _RefusingPrefs(this.inner);

  final SharedPreferencesStorePlatform inner;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async =>
      false;

  @override
  Future<bool> remove(String key) => inner.remove(key);

  @override
  Future<bool> clear() => inner.clear();

  @override
  Future<Map<String, Object>> getAll() => inner.getAll();
}

void main() {
  test('currency defaults to NPR and formats everywhere', () async {
    SharedPreferences.setMockInitialValues({});
    final store = ExpenseStore();
    await store.load();
    expect(store.currency, 'NPR');
    expect(store.currencySymbol, 'रू');
    expect(money(1500), contains('रू'));
  });

  test('currency change persists across restarts, junk ignored',
      () async {
    SharedPreferences.setMockInitialValues({});
    final a = ExpenseStore();
    await a.load();
    await a.setCurrency('USD');
    expect(a.currency, 'USD');
    expect(money(25), contains('\$'));
    final b = ExpenseStore();
    await b.load();
    expect(b.currency, 'USD');
    await b.setCurrency('BOGUS');
    expect(b.currency, 'USD');
  });

  test('parseAmount accepts cash, rejects alphabets', () {    expect(parseAmount('500'), 500);
    expect(parseAmount('1,000'), 1000);
    expect(parseAmount('1,00,000'), 100000);
    expect(parseAmount('99.50'), 99.5);
    expect(parseAmount(' 250 '), 250);
    expect(parseAmount('abc'), isNull);
    expect(parseAmount('12a34'), isNull);
    expect(parseAmount(''), isNull);
    expect(parseAmount('-50'), isNull);
    expect(parseAmount('0'), isNull);
    expect(parseAmount('10.999'), isNull);
  });

  test('theme mode and accent persist; junk falls back', () async {
    SharedPreferences.setMockInitialValues({});
    final a = ExpenseStore();
    await a.load();
    expect(a.themeMode, 'system');
    await a.setThemeMode('dark');
    await a.setAccent(0xFFC2185B);
    final b = ExpenseStore();
    await b.load();
    expect(b.themeMode, 'dark');
    expect(b.accent, 0xFFC2185B);
    await b.setThemeMode('neon');
    expect(b.themeMode, 'system');
  });

  test('a refused prefs write is reported, not shown as Saved', () async {
    // setString signals a refused write by returning false rather than
    // throwing. The prefs backend used to discard that bool, so on web a
    // quota-exhausted save took the success branch: lastPersistError stayed
    // null and the UI showed "Saved" for data that was never written.
    SharedPreferences.setMockInitialValues({});
    final original = SharedPreferencesStorePlatform.instance;
    SharedPreferencesStorePlatform.instance = _RefusingPrefs(original);
    addTearDown(() => SharedPreferencesStorePlatform.instance = original);

    final store = ExpenseStore();
    await store.load();
    await store.addTransaction(
      type: 'expense',
      amount: 99,
      categoryId: 'food',
      date: DateTime.utc(2026, 9, 1),
    );

    expect(
      store.lastPersistError,
      isNotNull,
      reason: 'the refused write must surface as an error',
    );
    // And the in-memory entry was rolled back rather than left as a phantom
    // the UI would render as saved.
    expect(store.transactions.where((t) => t.amount == 99), isEmpty);
  });

  test('eraseAll wipes domain data and reseeds', () async {    SharedPreferences.setMockInitialValues({});
    final a = ExpenseStore();
    await a.load();
    await a.addProject('Trip', '');
    await a.addTransaction(
        type: 'expense',
        amount: 10,
        categoryId: 'food',
        date: DateTime.utc(2026, 9, 1));
    expect(a.transactions, isNotEmpty);
    await a.eraseAll();
    expect(a.transactions, isEmpty);
    expect(a.projects, isEmpty);
    expect(a.categories.length, defaultCategories().length);
    expect(a.currency, 'NPR');
  });

  test('legacy installs gain Fuel once, never duplicated', () async {
    SharedPreferences.setMockInitialValues({
      'expense_cats_v1':
          '[{"id":"food","name":"Food","icon":0,"color":1}]',
    });
    final a = ExpenseStore();
    await a.load();
    expect(a.categories.length, 2);
    expect(a.categories.last.id, 'fuel');
    expect(a.categories.last.name, 'Fuel');
    final b = ExpenseStore();
    await b.load();
    expect(
        b.categories.where((c) => c.id == 'fuel').length, 1);
  });

  test('twelve accent choices, username round-trips', () async {
    expect(ExpenseStore.accentChoices.length, 12);
    SharedPreferences.setMockInitialValues({});
    final a = ExpenseStore();
    await a.load();
    expect(a.userName, '');
    await a.setUserName('  Ram  ');
    expect(a.userName, 'Ram');
    final b = ExpenseStore();
    await b.load();
    expect(b.userName, 'Ram');
  });

  test('sms mode + sender allowlist persist and clean', () async {
    SharedPreferences.setMockInitialValues({});
    final a = ExpenseStore();
    await a.load();
    expect(a.smsMode, 'manual');
    expect(a.smsSenders, isEmpty);
    await a.setSmsMode('auto');
    await a.setSmsSenders([' eSewa ', 'nabil', 'eSewa', 'x']);
    expect(a.smsMode, 'auto');
    expect(a.smsSenders, ['eSewa', 'nabil']);
    final b = ExpenseStore();
    await b.load();
    expect(b.smsMode, 'auto');
    expect(b.smsSenders, ['eSewa', 'nabil']);
    await b.setSmsMode('bogus');
    expect(b.smsMode, 'manual');
  });

  test('sms imported ids round-trip without dupes', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await SmsReader.importedIds(), isEmpty);
    await SmsReader.markImported(['a', 'b']);
    await SmsReader.markImported(['b', 'c']);
    final ids = await SmsReader.importedIds();
    expect(ids, containsAll(['a', 'b', 'c']));
  });

  test('updateTransaction edits fields, keeps rest, false on unknown',
      () async {
    SharedPreferences.setMockInitialValues({});
    final a = ExpenseStore();
    await a.load();
    await a.addTransaction(
        type: 'expense',
        amount: 100,
        categoryId: 'food',
        date: DateTime.utc(2026, 9, 1),
        note: 'x');
    final id = a.transactions.single.id;
    expect(await a.updateTransaction('nope', amount: 5), isFalse);
    expect(
        await a.updateTransaction(id,
            amount: 250,
            note: 'y',
            mode: 'card',
            projectId: 'p1'),
        isTrue);
    final t = a.transactions.single;
    expect(t.amount, 250);
    expect(t.note, 'y');
    expect(t.mode, 'card');
    expect(t.projectId, 'p1');
    expect(t.categoryId, 'food');
    expect(t.type, 'expense');
    final b = ExpenseStore();
    await b.load();
    expect(b.transactions.single.amount, 250);
    expect(b.transactions.single.projectId, 'p1');
  });
}