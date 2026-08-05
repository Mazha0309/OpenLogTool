import 'package:openlogtool/services/export_service.dart';

/// dart:io 平台的占位实现。
/// 实际下载逻辑仅在 Web 端执行（saveFile 中 kIsWeb 分支），此分支不应被调用。
Future<ExportSaveResult> downloadOnWeb(WebDownloadMeta meta) async =>
    throw UnsupportedError('Web native download is only available on web.');
