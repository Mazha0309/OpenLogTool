import 'package:flutter_test/flutter_test.dart';
import 'package:openlogtool/services/app_fonts.dart';

void main() {
  test('web uses subset font asset', () {
    expect(appFontAssetPath(isWeb: true),
        'assets/fonts/SarasaGothicSC-subset.ttf');
  });

  test('desktop uses full font asset', () {
    expect(appFontAssetPath(isWeb: false),
        'assets/fonts/SarasaGothicSC-Regular.ttf');
  });
}
