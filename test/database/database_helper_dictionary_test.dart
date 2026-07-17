import 'package:flutter_test/flutter_test.dart';
import 'package:openlogtool/database/database_helper.dart';

void main() {
  test('dictionary deletion rejects a non-dictionary table before opening DB',
      () async {
    await expectLater(
      DatabaseHelper().deleteDictionaryItem('logs', 1),
      throwsArgumentError,
    );
  });

  test('dictionary clearing rejects a non-dictionary table before opening DB',
      () async {
    await expectLater(
      DatabaseHelper().clearDictionary('sessions'),
      throwsArgumentError,
    );
  });
}
