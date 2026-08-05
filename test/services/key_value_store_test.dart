import 'package:flutter_test/flutter_test.dart';
import 'package:openlogtool/services/key_value_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('PrefsKeyValueStore round-trips string/bool/int', () async {
    final store = PrefsKeyValueStore(await SharedPreferences.getInstance());
    expect(await store.setString('s', 'hello'), isTrue);
    expect(await store.setBool('b', true), isTrue);
    expect(await store.setInt('i', 42), isTrue);
    expect(await store.getString('s'), 'hello');
    expect(await store.getBool('b'), isTrue);
    expect(await store.getInt('i'), 42);
    expect(await store.containsKey('s'), isTrue);
    expect(await store.getBool('missing', defaultValue: true), isTrue);
  });

  test('PrefsKeyValueStore remove/clear/getKeys', () async {
    final store = PrefsKeyValueStore(await SharedPreferences.getInstance());
    await store.setString('a', '1');
    await store.setString('b', '2');
    expect(await store.getKeys(), {'a', 'b'});
    expect(await store.remove('a'), isTrue);
    expect(await store.getString('a'), isNull);
    expect(await store.containsKey('a'), isFalse);
    expect(await store.clear(), isTrue);
    expect(await store.getKeys(), isEmpty);
  });

  test('migrateLegacyLocalStorage is a no-op off web', () async {
    final store = PrefsKeyValueStore(await SharedPreferences.getInstance());
    await store.setString('x', 'y');
    await store.setBool('flag', true);
    await store.setInt('n', 7);
    await migrateLegacyLocalStorage(store); // kIsWeb=false 时应不抛错且不改数据
    expect(await store.getString('x'), 'y');
    expect(await store.getBool('flag'), isTrue);
    expect(await store.getInt('n'), 7);
  });
}
