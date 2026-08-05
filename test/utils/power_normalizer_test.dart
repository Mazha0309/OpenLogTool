import 'package:flutter_test/flutter_test.dart';
import 'package:openlogtool/utils/power_normalizer.dart';

void main() {
  test('appends W to pure integers and decimals', () {
    expect(normalizePower('50'), '50 W');
    expect(normalizePower('50.5'), '50.5 W');
    expect(normalizePower(' 100 '), '100 W');
  });

  test('leaves values that already carry a unit untouched', () {
    expect(normalizePower('50W'), '50W');
    expect(normalizePower('50W '), '50W');
    expect(normalizePower('5kW'), '5kW');
    expect(normalizePower('500mW'), '500mW');
  });

  test('leaves Chinese units and other letters untouched', () {
    expect(normalizePower('50瓦'), '50瓦');
    expect(normalizePower('50 瓦'), '50 瓦');
    expect(normalizePower('5k'), '5k');
    expect(normalizePower('abc'), 'abc');
  });

  test('leaves empty values untouched', () {
    expect(normalizePower(''), '');
    expect(normalizePower('   '), '');
  });
}
