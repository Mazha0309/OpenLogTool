import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;
import 'package:openlogtool/services/export_service.dart';

/// Web 端浏览器原生下载实现：Blob + AnchorElement。
/// 仅在编译到 Web 时使用，dart:io 平台走 [export_web_download_stub]。
Future<ExportSaveResult> downloadOnWeb(WebDownloadMeta meta) async {
  final bytes = meta.bytes as Uint8List;
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: meta.mimeType),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = meta.filename;
  web.document.body?.appendChild(anchor);
  anchor.click();
  anchor.remove();
  web.URL.revokeObjectURL(url);
  return ExportSaveResult(path: meta.filename, usedSaf: true);
}
