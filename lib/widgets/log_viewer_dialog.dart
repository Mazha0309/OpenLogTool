import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:openlogtool/l10n/l10n.dart';
import 'package:openlogtool/services/app_logger.dart';
import 'package:openlogtool/theme/app_theme.dart';

/// 设置页入口：查看最近日志，可复制。
class LogViewerDialog extends StatelessWidget {
  const LogViewerDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final lines = AppLogger.instance.snapshot().join('\n');
    final mediaSize = MediaQuery.sizeOf(context);
    final double maxHeight = math.min(
      math.max(mediaSize.height - 32.0, 240.0),
      560.0,
    );

    return Dialog(
      key: const Key('log-viewer-dialog'),
      insetPadding: const EdgeInsets.all(16),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: AppDimensions.dialogWidth,
          maxHeight: maxHeight,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  context.l10n.logsTitle,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                key: const Key('log-viewer-scroll'),
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
                child: lines.isEmpty
                    ? Text(
                        context.l10n.logsEmpty,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      )
                    : SelectableText(
                        lines,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          height: 1.5,
                        ),
                      ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    key: const Key('log-viewer-copy'),
                    onPressed:
                        lines.isEmpty ? null : () => _copyLogs(context, lines),
                    icon: const Icon(Icons.copy_outlined, size: 18),
                    label: Text(context.l10n.logsCopy),
                  ),
                  TextButton(
                    key: const Key('log-viewer-close'),
                    onPressed: () => Navigator.pop(context),
                    child: Text(context.l10n.logsClose),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _copyLogs(BuildContext context, String lines) async {
    await Clipboard.setData(ClipboardData(text: lines));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.logsCopied)),
    );
  }
}
