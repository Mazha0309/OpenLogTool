import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 应用启动时按平台加载 SarasaGothicSC：
/// Web 加载子集 ttf（首屏只下载子集），桌面加载完整 ttf。
/// 字体文件在 assets/fonts/ 下（随包发布、惰性下载）。
Future<void> loadAppFonts() async {
  final asset = appFontAssetPath(isWeb: kIsWeb);
  final data = await rootBundle.load(asset);
  final loader = FontLoader('SarasaGothicSC')..addFont(Future.value(data));
  await loader.load();
}

/// 平台选择字体资产路径（可测试纯函数）。
String appFontAssetPath({required bool isWeb}) => isWeb
    ? 'assets/fonts/SarasaGothicSC-subset.ttf'
    : 'assets/fonts/SarasaGothicSC-Regular.ttf';
