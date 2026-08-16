import 'package:flutter/material.dart';
import 'package:openlogtool/services/app_logger.dart';

extension LoggedSnackBarContext on BuildContext {
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showLoggedSnackBar(
    SnackBar snackBar, {
    String? source,
    String? type,
  }) {
    _logSnackBar(snackBar, source: source, type: type);
    return ScaffoldMessenger.of(this).showSnackBar(snackBar);
  }
}

extension LoggedSnackBarMessenger on ScaffoldMessengerState {
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showLoggedSnackBar(
    SnackBar snackBar, {
    String? source,
    String? type,
  }) {
    _logSnackBar(snackBar, source: source, type: type);
    return showSnackBar(snackBar);
  }
}

void _logSnackBar(
  SnackBar snackBar, {
  String? source,
  String? type,
}) {
  final content = snackBar.content;
  final message = content is Text
      ? content.data ?? content.textSpan?.toPlainText() ?? ''
      : content.toStringShort();
  final resolvedType = type ?? _inferType(snackBar, message);
  AppLogger.instance.log(
    resolvedType == 'error' ? AppLogLevel.error : AppLogLevel.info,
    message,
    source: source ?? 'Snackbar',
  );
}

String _inferType(SnackBar snackBar, String message) {
  final normalized = message.toLowerCase();
  if (normalized.contains('失败') ||
      normalized.contains('错误') ||
      normalized.contains('error') ||
      normalized.contains('failed')) {
    return 'error';
  }
  if (normalized.contains('成功') || normalized.contains('已')) {
    return 'success';
  }
  if (snackBar.backgroundColor == Colors.red ||
      snackBar.backgroundColor == Colors.redAccent) {
    return 'error';
  }
  return 'info';
}
