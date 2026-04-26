import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:openlogtool/providers/snackbar_log_provider.dart';

extension LoggedSnackBarContext on BuildContext {
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showLoggedSnackBar(
    SnackBar snackBar, {
    String? source,
    String? type,
  }) {
    String message = '';
    final content = snackBar.content;
    if (content is Text) {
      message = content.data ?? '';
    } else {
      message = content.toStringShort();
    }

    final resolvedType = type ?? _inferType(snackBar, message);

    read<SnackbarLogProvider>().add(
      message: message,
      type: resolvedType,
      source: source ?? widget.runtimeType.toString(),
    );

    return ScaffoldMessenger.of(this).showSnackBar(snackBar);
  }

  String _inferType(SnackBar snackBar, String message) {
    final normalized = message.toLowerCase();
    if (normalized.contains('失败') || normalized.contains('错误') || normalized.contains('error')) {
      return 'error';
    }
    if (normalized.contains('成功') || normalized.contains('已')) {
      return 'success';
    }
    if (snackBar.backgroundColor == Colors.red || snackBar.backgroundColor == Colors.redAccent) {
      return 'error';
    }
    return 'info';
  }
}
