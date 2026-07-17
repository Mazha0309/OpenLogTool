import 'package:flutter/material.dart';
import 'package:openlogtool/l10n/l10n.dart';
import 'package:provider/provider.dart';
import 'package:openlogtool/providers/log_provider.dart';
import 'package:openlogtool/providers/settings_provider.dart';
import 'package:openlogtool/models/log_entry.dart';
import 'package:openlogtool/utils/app_snack_bar.dart';
import 'package:openlogtool/utils/log_time.dart';

class LogTable extends StatefulWidget {
  const LogTable({
    super.key,
    this.readOnly = false,
    this.conflictedLogIds = const <String>{},
  });

  final bool readOnly;
  final Set<String> conflictedLogIds;

  @override
  State<LogTable> createState() => _LogTableState();
}

class _LogTableState extends State<LogTable> {
  int? _editingIndex;
  late Map<String, TextEditingController> _controllers;
  int _currentPage = 0;
  static const int _itemsPerPage = 5;
  List<LogEntry> _lastSeenLogs = [];

  final ScrollController _horizontalController = ScrollController();

  @override
  void initState() {
    super.initState();
    _controllers = {};
  }

  @override
  void dispose() {
    for (var controller in _controllers.values) {
      controller.dispose();
    }
    _horizontalController.dispose();
    super.dispose();
  }

  void _startEditing(int index, LogEntry log) {
    final logProvider = context.read<LogProvider>();
    if (widget.readOnly ||
        widget.conflictedLogIds.contains(log.id) ||
        !logProvider.canMutateLog(log)) {
      return;
    }
    setState(() {
      _editingIndex = index;
      _controllers = {
        'time': TextEditingController(
          text: formatLogTimeForDisplay(log.time),
        ),
        'controller': TextEditingController(text: log.controller),
        'callsign': TextEditingController(text: log.callsign),
        'report': TextEditingController(text: log.report),
        'rstRcvd': TextEditingController(text: log.rstRcvd),
        'qth': TextEditingController(text: log.qth),
        'device': TextEditingController(text: log.device),
        'power': TextEditingController(text: log.power),
        'antenna': TextEditingController(text: log.antenna),
        'height': TextEditingController(text: log.height),
        'remarks': TextEditingController(text: log.remarks),
        '_id': TextEditingController(text: log.id),
        '_sessionId': TextEditingController(text: log.sessionId ?? ''),
        '_createdAt': TextEditingController(text: log.createdAt),
      };
    });
  }

  void _cancelEditing() {
    if (!mounted) return;
    setState(() {
      _editingIndex = null;
      for (var controller in _controllers.values) {
        controller.dispose();
      }
      _controllers = {};
    });
  }

  Future<void> _saveEditing() async {
    final logId = _controllers['_id']?.text ?? '';
    final logProvider = Provider.of<LogProvider>(context, listen: false);
    final currentIndex =
        logProvider.logs.indexWhere((candidate) => candidate.id == logId);
    final original = currentIndex < 0 ? null : logProvider.logs[currentIndex];
    if (widget.readOnly ||
        widget.conflictedLogIds.contains(logId) ||
        original == null ||
        !logProvider.canMutateLog(original)) {
      _cancelEditing();
      return;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    final time = _controllers['time']?.text ?? '';
    if (!isValidLogTimeInput(time)) {
      messenger?.showSnackBar(
        SnackBar(content: Text(context.l10n.logTimeInvalid)),
      );
      return;
    }
    // updateLog preserves sync_id / localId / sessionId / createdAt — only the
    // text fields below are taken from the form.
    final patch = LogEntry(
      id: _controllers['_id']?.text ?? '',
      sessionId: _controllers['_sessionId']?.text,
      time: time,
      controller: _controllers['controller']?.text ?? '',
      callsign: _controllers['callsign']?.text ?? '',
      report: _controllers['report']?.text ?? '',
      rstRcvd: _controllers['rstRcvd']?.text ?? '',
      qth: _controllers['qth']?.text ?? '',
      device: _controllers['device']?.text ?? '',
      power: _controllers['power']?.text ?? '',
      antenna: _controllers['antenna']?.text ?? '',
      height: _controllers['height']?.text ?? '',
      createdAt: _controllers['_createdAt']?.text,
    );
    patch.remarks = _controllers['remarks']?.text ?? '';
    try {
      await logProvider.updateLogById(logId, patch);
    } catch (error) {
      if (!mounted) return;
      messenger?.showSnackBar(
        SnackBar(content: Text(context.l10n.operationFailed('$error'))),
      );
      return;
    }
    _cancelEditing();
  }

  @override
  Widget build(BuildContext context) {
    final logProvider = Provider.of<LogProvider>(context);
    final settingsProvider = Provider.of<SettingsProvider>(context);

    if (logProvider.logs.isEmpty) {
      return Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(40),
        width: double.infinity,
        decoration: BoxDecoration(
          color: Theme.of(context)
              .colorScheme
              .surfaceContainerHighest
              .withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.list_alt,
              size: 64,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              context.l10n.noSavedRecords,
              style: TextStyle(
                fontSize: 18,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.addFirstRecordHint,
              style: TextStyle(
                color: Theme.of(context)
                    .colorScheme
                    .onSurfaceVariant
                    .withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      );
    }

    final horizontalController = _horizontalController;

    return LayoutBuilder(
      builder: (context, constraints) {
        var effectivePage = _currentPage;
        if (settingsProvider.paginationEnabled) {
          final totalPages = (logProvider.logs.length / _itemsPerPage).ceil();
          if (effectivePage >= totalPages) effectivePage = totalPages - 1;
          if (effectivePage < 0) effectivePage = 0;
        }
        final visibleRows = settingsProvider.paginationEnabled
            ? (logProvider.logs.length - effectivePage * _itemsPerPage)
                .clamp(1, _itemsPerPage)
            : logProvider.logs.length;
        final contentHeight = (48.0 + visibleRows * 56.0).clamp(104.0, 400.0);
        final enableInnerVerticalScroll = !settingsProvider.paginationEnabled &&
            48.0 + logProvider.logs.length * 56.0 > 400.0;
        final maxHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : contentHeight;
        final colors = Theme.of(context).colorScheme;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: maxHeight,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: DecoratedBox(
                  key: const Key('log-table-surface'),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    border: Border.all(color: colors.outlineVariant),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: NotificationListener<ScrollNotification>(
                    onNotification: (notification) => true,
                    child: Scrollbar(
                      controller: horizontalController,
                      thumbVisibility: true,
                      trackVisibility: true,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        controller: horizontalController,
                        child: ConstrainedBox(
                          constraints:
                              BoxConstraints(minWidth: constraints.maxWidth),
                          child: SingleChildScrollView(
                            physics: enableInnerVerticalScroll
                                ? const ClampingScrollPhysics()
                                : const NeverScrollableScrollPhysics(),
                            child: DataTable(
                              columnSpacing: 16,
                              horizontalMargin: 16,
                              headingRowHeight: 48,
                              dataRowMinHeight: 56,
                              dataRowMaxHeight: 56,
                              headingRowColor: WidgetStatePropertyAll(
                                colors.surfaceContainerHighest,
                              ),
                              headingTextStyle: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: colors.onSurface,
                                fontSize: 13,
                              ),
                              dataTextStyle: TextStyle(
                                color: colors.onSurface,
                                fontSize: 13,
                              ),
                              dividerThickness: 1,
                              border: TableBorder(
                                horizontalInside: BorderSide(
                                  color: colors.outlineVariant,
                                ),
                              ),
                              columns: [
                                DataColumn(
                                  label:
                                      _buildCenteredCell(const Text('#'), 60),
                                ),
                                DataColumn(
                                  label: _buildCenteredCell(
                                    Text(context.l10n.fieldTime),
                                    100,
                                  ),
                                ),
                                DataColumn(
                                  label: _buildCenteredCell(
                                    Text(context.l10n.fieldController),
                                    120,
                                  ),
                                ),
                                DataColumn(
                                  label: _buildCenteredCell(
                                    Text(context.l10n.fieldCallsign),
                                    120,
                                  ),
                                ),
                                DataColumn(
                                  label: _buildCenteredCell(
                                    Text(context.l10n.fieldRstSent),
                                    60,
                                  ),
                                ),
                                DataColumn(
                                  label: _buildCenteredCell(
                                    Text(context.l10n.fieldRstRcvd),
                                    60,
                                  ),
                                ),
                                DataColumn(
                                  label: _buildCenteredCell(
                                    Text(context.l10n.fieldQth),
                                    150,
                                  ),
                                ),
                                DataColumn(
                                  label: _buildCenteredCell(
                                    Text(context.l10n.fieldDevice),
                                    150,
                                  ),
                                ),
                                DataColumn(
                                  label: _buildCenteredCell(
                                    Text(context.l10n.fieldPower),
                                    80,
                                  ),
                                ),
                                DataColumn(
                                  label: _buildCenteredCell(
                                    Text(context.l10n.fieldAntenna),
                                    150,
                                  ),
                                ),
                                DataColumn(
                                  label: _buildCenteredCell(
                                    Text(context.l10n.fieldHeight),
                                    80,
                                  ),
                                ),
                                DataColumn(
                                  label: _buildCenteredCell(
                                    Text(context.l10n.fieldRemarks),
                                    120,
                                  ),
                                ),
                                DataColumn(
                                  label: _buildCenteredCell(
                                    Text(context.l10n.fieldActions),
                                    120,
                                  ),
                                ),
                              ],
                              rows: _buildTableRows(
                                context,
                                logProvider,
                                settingsProvider,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // 分页控件
            if (settingsProvider.paginationEnabled &&
                logProvider.logs.length > _itemsPerPage)
              _buildPaginationControls(logProvider.logs.length),
          ],
        );
      },
    );
  }

  List<DataRow> _buildTableRows(BuildContext context, LogProvider logProvider,
      SettingsProvider settingsProvider) {
    final logs = logProvider.logs;
    final indexedLogs = logs.asMap().entries.toList().reversed.toList();

    // Reset page when underlying log list is replaced (e.g. session switch).
    // Use identity comparison because LogProvider rebuilds the list on every load.
    if (!identical(_lastSeenLogs, logs)) {
      _lastSeenLogs = logs;
      _currentPage = 0;
    }

    // 如果启用分页，只显示当前页的数据（按最新在上排序后的结果）
    List<MapEntry<int, LogEntry>> displayEntries;
    if (settingsProvider.paginationEnabled) {
      final totalPages =
          (indexedLogs.length / _itemsPerPage).ceil().clamp(1, 1 << 30);
      if (_currentPage >= totalPages) {
        // Logs got shorter (session switch / clear / undo) — snap back to a
        // valid page instead of showing an empty slice.
        _currentPage = totalPages - 1;
      }
      final startIndex = _currentPage * _itemsPerPage;
      final endIndex =
          (startIndex + _itemsPerPage).clamp(0, indexedLogs.length);
      displayEntries = indexedLogs.sublist(startIndex, endIndex);
    } else {
      displayEntries = indexedLogs;
    }

    return displayEntries.asMap().entries.map((entry) {
      final originalIndex = entry.value.key;
      final log = entry.value.value;
      final isEditing = _editingIndex == originalIndex;
      final isConflicted = widget.conflictedLogIds.contains(log.id);
      final mutationBlockReason = widget.readOnly
          ? 'COLLABORATION_SESSION_READ_ONLY'
          : logProvider.mutationBlockReason(log);
      final canMutate = mutationBlockReason == null && !isConflicted;
      final mutationHint = isConflicted
          ? context.l10n.logConflictReadOnlyHint
          : mutationBlockReason == null
              ? ''
              : _mutationBlockLabel(context, mutationBlockReason);
      // 倒序序号：最新的记录显示最大序号
      final reverseIndex = originalIndex + 1;

      return DataRow(
        color: WidgetStatePropertyAll(
          isEditing
              ? Theme.of(context)
                  .colorScheme
                  .primaryContainer
                  .withValues(alpha: 0.22)
              : entry.key.isOdd
                  ? Theme.of(context).colorScheme.surfaceContainerLowest
                  : Colors.transparent,
        ),
        cells: [
          DataCell(
            _buildCenteredCell(Text('$reverseIndex'), 60),
          ),
          DataCell(
            isEditing
                ? SizedBox(
                    width: 100,
                    child: TextField(
                      controller: _controllers['time'],
                      style: const TextStyle(fontSize: 13),
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  )
                : _buildCenteredCell(
                    Text(formatLogTimeForDisplay(log.time)), 100),
          ),
          DataCell(
            isEditing
                ? SizedBox(
                    width: 120,
                    child: TextField(
                      controller: _controllers['controller'],
                      style: const TextStyle(fontSize: 13),
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  )
                : _buildCenteredCell(Text(log.controller), 120),
          ),
          DataCell(
            isEditing
                ? SizedBox(
                    width: 120,
                    child: TextField(
                      controller: _controllers['callsign'],
                      style: const TextStyle(fontSize: 13),
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  )
                : _buildCenteredCell(Text(log.callsign), 120),
          ),
          DataCell(
            isEditing
                ? SizedBox(
                    width: 60,
                    child: TextField(
                      controller: _controllers['report'],
                      style: const TextStyle(fontSize: 13),
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  )
                : _buildCenteredCell(Text(log.report), 60),
          ),
          DataCell(
            isEditing
                ? SizedBox(
                    width: 60,
                    child: TextField(
                      controller: _controllers['rstRcvd'],
                      style: const TextStyle(fontSize: 13),
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  )
                : _buildCenteredCell(Text(log.rstRcvd), 60),
          ),
          DataCell(
            isEditing
                ? SizedBox(
                    width: 150,
                    child: TextField(
                      controller: _controllers['qth'],
                      style: const TextStyle(fontSize: 13),
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  )
                : _buildCenteredCell(Text(log.qth), 150),
          ),
          DataCell(
            isEditing
                ? SizedBox(
                    width: 150,
                    child: TextField(
                      controller: _controllers['device'],
                      style: const TextStyle(fontSize: 13),
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  )
                : _buildCenteredCell(Text(log.device), 150),
          ),
          DataCell(
            isEditing
                ? SizedBox(
                    width: 80,
                    child: TextField(
                      controller: _controllers['power'],
                      style: const TextStyle(fontSize: 13),
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  )
                : _buildCenteredCell(Text(log.power), 80),
          ),
          DataCell(
            isEditing
                ? SizedBox(
                    width: 150,
                    child: TextField(
                      controller: _controllers['antenna'],
                      style: const TextStyle(fontSize: 13),
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  )
                : _buildCenteredCell(Text(log.antenna), 150),
          ),
          DataCell(
            isEditing
                ? SizedBox(
                    width: 80,
                    child: TextField(
                      controller: _controllers['height'],
                      style: const TextStyle(fontSize: 13),
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  )
                : _buildCenteredCell(Text(log.height), 80),
          ),
          DataCell(
            _buildCenteredCell(
              isEditing
                  ? SizedBox(
                      width: 110,
                      child: TextField(
                        controller: _controllers['remarks'],
                        decoration: const InputDecoration(
                          isDense: true,
                          contentPadding:
                              EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                        ),
                      ),
                    )
                  : Text(log.remarks),
              110,
            ),
          ),
          DataCell(
            _buildCenteredCell(
              isEditing
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.check, size: 20),
                          onPressed: !canMutate ? null : _saveEditing,
                          tooltip:
                              !canMutate ? mutationHint : context.l10n.save,
                          style: IconButton.styleFrom(
                            backgroundColor: Theme.of(context)
                                .colorScheme
                                .primary
                                .withValues(alpha: 0.1),
                          ),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          icon: const Icon(Icons.close, size: 20),
                          onPressed: _cancelEditing,
                          tooltip: context.l10n.cancel,
                          style: IconButton.styleFrom(
                            backgroundColor: Theme.of(context)
                                .colorScheme
                                .error
                                .withValues(alpha: 0.1),
                          ),
                        ),
                      ],
                    )
                  : !canMutate
                      ? Tooltip(
                          message: mutationHint,
                          child: Icon(
                            Icons.lock_outline,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit, size: 20),
                              onPressed: () =>
                                  _startEditing(originalIndex, log),
                              tooltip: context.l10n.editRecord,
                              style: IconButton.styleFrom(
                                backgroundColor: Theme.of(context)
                                    .colorScheme
                                    .primary
                                    .withValues(alpha: 0.1),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.delete, size: 20),
                              onPressed: () => _showDeleteConfirmation(
                                context,
                                log,
                              ),
                              tooltip: context.l10n.deleteRecord,
                              style: IconButton.styleFrom(
                                backgroundColor: Theme.of(context)
                                    .colorScheme
                                    .error
                                    .withValues(alpha: 0.1),
                              ),
                            ),
                          ],
                        ),
              120,
            ),
          ),
        ],
      );
    }).toList();
  }

  Widget _buildCenteredCell(Widget child, double width) {
    return SizedBox(
      width: width,
      child: Align(
        alignment: Alignment.center,
        child: child,
      ),
    );
  }

  Widget _buildPaginationControls(int totalItems) {
    final totalPages = (totalItems / _itemsPerPage).ceil();

    return Container(
      key: const Key('log-pagination'),
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed:
                _currentPage > 0 ? () => setState(() => _currentPage--) : null,
          ),
          const SizedBox(width: 8),
          Text('${_currentPage + 1} / $totalPages'),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: _currentPage < totalPages - 1
                ? () => setState(() => _currentPage++)
                : null,
          ),
        ],
      ),
    );
  }

  Future<void> _showDeleteConfirmation(
    BuildContext tableContext,
    LogEntry log,
  ) async {
    final logProvider = tableContext.read<LogProvider>();
    if (widget.readOnly ||
        widget.conflictedLogIds.contains(log.id) ||
        !logProvider.canMutateLog(log)) {
      return;
    }
    final deleted = await showDialog<bool>(
      context: tableContext,
      barrierDismissible: false,
      builder: (dialogContext) => _DeleteLogDialog(
        onDelete: () async {
          if (widget.readOnly ||
              widget.conflictedLogIds.contains(log.id) ||
              !logProvider.canMutateLog(log)) {
            throw StateError(_mutationBlockLabel(
              dialogContext,
              logProvider.mutationBlockReason(log),
            ));
          }
          await logProvider.deleteLogById(log.id);
        },
      ),
    );
    if (deleted != true || !mounted) return;
    context.showLoggedSnackBar(
      SnackBar(
        content: Text(context.l10n.recordDeleted),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  String _mutationBlockLabel(BuildContext context, String? reason) =>
      switch (reason) {
        'COLLABORATION_LOG_NOT_OWNED' => context.l10n.logNotOwnedReadOnlyHint,
        'COLLABORATION_LOG_AUTHOR_UNKNOWN' =>
          context.l10n.logAuthorUnknownReadOnlyHint,
        _ => context.l10n.logSessionReadOnlyHint,
      };
}

class _DeleteLogDialog extends StatefulWidget {
  const _DeleteLogDialog({required this.onDelete});

  final Future<void> Function() onDelete;

  @override
  State<_DeleteLogDialog> createState() => _DeleteLogDialogState();
}

class _DeleteLogDialogState extends State<_DeleteLogDialog> {
  bool _deleting = false;

  Future<void> _delete() async {
    if (_deleting) return;
    setState(() => _deleting = true);

    try {
      await widget.onDelete();
    } catch (error) {
      if (!mounted) return;
      setState(() => _deleting = false);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(context.l10n.operationFailed('$error'))),
      );
      return;
    }

    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_deleting,
      child: AlertDialog(
        title: Text(context.l10n.deleteRecord),
        content: Text(context.l10n.deleteRecordConfirmation),
        actions: [
          TextButton(
            onPressed: _deleting ? null : () => Navigator.pop(context, false),
            child: Text(context.l10n.cancel),
          ),
          ElevatedButton(
            onPressed: _deleting ? null : _delete,
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: _deleting
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(context.l10n.delete),
          ),
        ],
      ),
    );
  }
}
