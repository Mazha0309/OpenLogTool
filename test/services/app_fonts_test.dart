import 'package:flutter/services.dart';
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
  testWidgets('loadAppFonts succeeds with the real font asset', (tester) async {
    await tester.runAsync(() async {
      // 两个平台路径的资源都应存在且可加载
      for (final asset in [
        'assets/fonts/SarasaGothicSC-subset.ttf',
        'assets/fonts/SarasaGothicSC-Regular.ttf'
      ]) {
        final data = await rootBundle.load(asset);
        expect(data.lengthInBytes, greaterThan(0));
      }
      // flutter_test 中 FontLoader 注册可用，直接调用应不报错
      await loadAppFonts();
    });
  });
}
