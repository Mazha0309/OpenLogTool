import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:openlogtool/l10n/l10n.dart';
import 'package:openlogtool/models/dictionary_item.dart';
import 'package:openlogtool/providers/dictionary_provider.dart';
import 'package:provider/provider.dart';

int dictionaryGridColumnCount(double width) => width >= 760 ? 2 : 1;

class DictionaryManager extends StatefulWidget {
  const DictionaryManager({super.key});

  @override
  State<DictionaryManager> createState() => _DictionaryManagerState();
}

class _DictionaryManagerState extends State<DictionaryManager> {
  final Map<String, bool> _expandedStates = <String, bool>{
    'device': false,
    'antenna': false,
    'callsign': false,
    'qth': false,
  };
  final Map<String, TextEditingController> _addControllers =
      <String, TextEditingController>{
    'device': TextEditingController(),
    'antenna': TextEditingController(),
    'callsign': TextEditingController(),
    'qth': TextEditingController(),
  };
  final Map<String, TextEditingController> _searchControllers =
      <String, TextEditingController>{
    'device': TextEditingController(),
    'antenna': TextEditingController(),
    'callsign': TextEditingController(),
    'qth': TextEditingController(),
  };
  final Map<String, ScrollController> _listControllers =
      <String, ScrollController>{
    'device': ScrollController(),
    'antenna': ScrollController(),
    'callsign': ScrollController(),
    'qth': ScrollController(),
  };
  final Map<String, String> _queries = <String, String>{};
  final Set<String> _busyLibraries = <String>{};
  bool _importing = false;

  bool get _mutationInProgress => _importing || _busyLibraries.isNotEmpty;

  @override
  void dispose() {
    for (final controller in _addControllers.values) {
      controller.dispose();
    }
    for (final controller in _searchControllers.values) {
      controller.dispose();
    }
    for (final controller in _listControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _toggleAll() {
    final allExpanded = _expandedStates.values.every((state) => state);
    setState(() {
      for (final key in _expandedStates.keys) {
        _expandedStates[key] = !allExpanded;
      }
    });
  }

  void _toggleLibrary(String key) {
    setState(() => _expandedStates[key] = !_expandedStates[key]!);
  }

  String _libraryName(String type) => switch (type) {
        'device' => context.l10n.deviceLibrary,
        'antenna' => context.l10n.antennaLibrary,
        'callsign' => context.l10n.callsignLibrary,
        'qth' => context.l10n.qthLibrary,
        _ => '',
      };

  IconData _libraryIcon(String type) => switch (type) {
        'device' => Icons.radio,
        'antenna' => Icons.settings_input_antenna,
        'callsign' => Icons.badge_outlined,
        'qth' => Icons.place_outlined,
        _ => Icons.folder_outlined,
      };

  Future<void> _importFromFile() async {
    if (_mutationInProgress) return;
    final messenger = ScaffoldMessenger.of(context);
    final provider = context.read<DictionaryProvider>();
    setState(() => _importing = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const <String>['json'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final bytes = result.files.first.bytes;
      if (bytes == null) {
        throw const FormatException('The selected file could not be read.');
      }
      final counts = await provider.importFromJson(utf8.decode(bytes));
      if (!mounted) return;
      final imported = counts.entries.where((entry) => entry.value > 0);
      if (imported.isEmpty) {
        messenger.showSnackBar(
          SnackBar(content: Text(context.l10n.libraryImportEmpty)),
        );
        return;
      }
      final summary = imported
          .map(
            (entry) => context.l10n.libraryImportCount(
              _libraryName(entry.key),
              entry.value,
            ),
          )
          .join(context.l10n.listSeparator);
      messenger.showSnackBar(
        SnackBar(content: Text(context.l10n.libraryImportSucceeded(summary))),
      );
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(context.l10n.libraryImportFailed('$error'))),
      );
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _addItem(_LibraryDefinition library) async {
    final controller = _addControllers[library.type]!;
    final value = controller.text.trim();
    if (value.isEmpty || _mutationInProgress) return;
    final messenger = ScaffoldMessenger.of(context);
    if (library.items.any((item) => item.raw == value)) {
      messenger.showSnackBar(
        SnackBar(content: Text(context.l10n.libraryItemAlreadyExists(value))),
      );
      return;
    }

    setState(() => _busyLibraries.add(library.type));
    try {
      await library.onAdd(value);
      if (!mounted) return;
      controller.clear();
      messenger.showSnackBar(
        SnackBar(content: Text(context.l10n.libraryItemAdded(value))),
      );
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(context.l10n.libraryItemAddFailed('$error'))),
      );
    } finally {
      if (mounted) setState(() => _busyLibraries.remove(library.type));
    }
  }

  Future<void> _deleteItem(
    _LibraryDefinition library,
    DictionaryItem item,
  ) async {
    if (_mutationInProgress) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(dialogContext.l10n.deleteLibraryItemTitle),
        content: Text(
          dialogContext.l10n.deleteLibraryItemConfirmation(
            item.raw,
            _libraryName(library.type),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(dialogContext.l10n.cancel),
          ),
          FilledButton(
            key: Key('confirm-delete-library-item-${library.type}'),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(dialogContext.l10n.deleteLibraryItemAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busyLibraries.add(library.type));
    try {
      await library.onDelete(item.raw);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(context.l10n.libraryItemDeleted(item.raw))),
      );
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(context.l10n.libraryItemDeleteFailed('$error')),
        ),
      );
    } finally {
      if (mounted) setState(() => _busyLibraries.remove(library.type));
    }
  }

  Future<void> _clearLibrary(_LibraryDefinition library) async {
    if (_mutationInProgress || library.items.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          dialogContext.l10n.clearLibraryTitle(_libraryName(library.type)),
        ),
        content: Text(
          dialogContext.l10n.clearLibraryConfirmation(
            _libraryName(library.type),
            library.items.length,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(dialogContext.l10n.cancel),
          ),
          FilledButton(
            key: Key('confirm-clear-library-${library.type}'),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(dialogContext.l10n.clearLibraryAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busyLibraries.add(library.type));
    try {
      await library.onClear();
      if (!mounted) return;
      _searchControllers[library.type]?.clear();
      setState(() => _queries.remove(library.type));
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.libraryCleared(_libraryName(library.type)),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(context.l10n.libraryClearFailed('$error'))),
      );
    } finally {
      if (mounted) setState(() => _busyLibraries.remove(library.type));
    }
  }

  List<DictionaryItem> _filteredItems(_LibraryDefinition library) {
    final query = _queries[library.type]?.trim() ?? '';
    if (query.isEmpty) return library.items;
    return library.items.where((item) => item.matches(query)).toList();
  }

  Widget _buildHeader(List<_LibraryDefinition> libraries) {
    final theme = Theme.of(context);
    final allExpanded = _expandedStates.values.every((state) => state);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final introduction = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.dictionaryManagementTitle,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  context.l10n.dictionaryManagementHint,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            );
            final actions = Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  key: const Key('import-library-json'),
                  onPressed: _mutationInProgress ? null : _importFromFile,
                  icon: _importing
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.file_upload_outlined, size: 18),
                  label: Text(context.l10n.importLibraryJson),
                ),
                TextButton.icon(
                  onPressed: _toggleAll,
                  icon: Icon(
                    allExpanded ? Icons.unfold_less : Icons.unfold_more,
                    size: 18,
                  ),
                  label: Text(
                    allExpanded
                        ? context.l10n.collapseAll
                        : context.l10n.expandAll,
                  ),
                ),
              ],
            );
            if (constraints.maxWidth < 680) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  introduction,
                  const SizedBox(height: 12),
                  Align(alignment: Alignment.centerLeft, child: actions),
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: introduction),
                const SizedBox(width: 16),
                actions,
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: libraries
              .map(
                (library) => ActionChip(
                  avatar: Icon(_libraryIcon(library.type), size: 16),
                  label: Text(
                    '${_libraryName(library.type)} · ${library.items.length}',
                  ),
                  onPressed: () => _toggleLibrary(library.type),
                ),
              )
              .toList(growable: false),
        ),
      ],
    );
  }

  Widget _buildLibraryCard(_LibraryDefinition library) {
    final theme = Theme.of(context);
    final isExpanded = _expandedStates[library.type]!;
    final isBusy = _busyLibraries.contains(library.type);
    final items = _filteredItems(library);
    return Card(
      key: Key('library-card-${library.type}'),
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => _toggleLibrary(library.type),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      _libraryIcon(library.type),
                      size: 20,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _libraryName(library.type),
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          context.l10n.libraryItemCount(library.items.length),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isBusy)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  Tooltip(
                    message: context.l10n.clearLibraryTitle(
                      _libraryName(library.type),
                    ),
                    child: IconButton(
                      key: Key('clear-library-${library.type}'),
                      onPressed: library.items.isEmpty || _mutationInProgress
                          ? null
                          : () => _clearLibrary(library),
                      icon: const Icon(Icons.delete_sweep_outlined),
                    ),
                  ),
                  AnimatedRotation(
                    turns: isExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 160),
                    child: const Icon(Icons.expand_more),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: isExpanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Divider(height: 1),
                        const SizedBox(height: 12),
                        _buildAddRow(library, _mutationInProgress),
                        const SizedBox(height: 10),
                        TextField(
                          key: Key('search-library-${library.type}'),
                          controller: _searchControllers[library.type],
                          decoration: InputDecoration(
                            hintText: context.l10n.searchLibrary(
                              _libraryName(library.type),
                            ),
                            prefixIcon: const Icon(Icons.search, size: 20),
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                          onChanged: (value) => setState(
                            () => _queries[library.type] = value,
                          ),
                        ),
                        const SizedBox(height: 10),
                        _buildItemList(
                          library,
                          items,
                          isBusy: _mutationInProgress,
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildAddRow(_LibraryDefinition library, bool isBusy) {
    final field = TextField(
      key: Key('add-library-${library.type}'),
      controller: _addControllers[library.type],
      enabled: !isBusy,
      decoration: InputDecoration(
        labelText: context.l10n.addLibraryItem(_libraryName(library.type)),
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => _addItem(library),
    );
    final button = FilledButton.icon(
      onPressed: isBusy ? null : () => _addItem(library),
      icon: const Icon(Icons.add, size: 18),
      label: Text(context.l10n.add),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 430) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [field, const SizedBox(height: 8), button],
          );
        }
        return Row(
          children: [
            Expanded(child: field),
            const SizedBox(width: 8),
            button,
          ],
        );
      },
    );
  }

  Widget _buildItemList(_LibraryDefinition library, List<DictionaryItem> items,
      {required bool isBusy}) {
    final theme = Theme.of(context);
    if (items.isEmpty) {
      final hasQuery = (_queries[library.type]?.trim().isNotEmpty ?? false);
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 28),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.35,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Icon(
              hasQuery ? Icons.search_off : Icons.inbox_outlined,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 6),
            Text(
              hasQuery
                  ? context.l10n.noLibrarySearchResults
                  : context.l10n.libraryEmpty,
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }
    final listController = _listControllers[library.type]!;
    return Container(
      constraints: const BoxConstraints(maxHeight: 280),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(10),
      ),
      child: ListView.separated(
        controller: listController,
        primary: false,
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: items.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final item = items[index];
          final searchHint = <String>{
            if (item.pinyin.trim().isNotEmpty) item.pinyin.trim(),
            if (item.abbreviation.trim().isNotEmpty) item.abbreviation.trim(),
          }.join(' · ');
          return ListTile(
            dense: true,
            contentPadding: const EdgeInsets.only(left: 12, right: 4),
            leading: CircleAvatar(
              radius: 13,
              child: Text('${index + 1}', style: theme.textTheme.labelSmall),
            ),
            title: Text(item.raw, maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: searchHint.isEmpty ? null : Text(searchHint),
            trailing: IconButton(
              key: Key('delete-library-${library.type}-${item.syncId}'),
              tooltip: context.l10n.deleteLibraryItemAction,
              onPressed: isBusy ? null : () => _deleteItem(library, item),
              icon: const Icon(Icons.delete_outline),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DictionaryProvider>();
    final libraries = <_LibraryDefinition>[
      _LibraryDefinition(
        type: 'device',
        items: provider.deviceDict,
        onAdd: provider.addDevice,
        onDelete: provider.deleteDevice,
        onClear: provider.clearDeviceDict,
      ),
      _LibraryDefinition(
        type: 'antenna',
        items: provider.antennaDict,
        onAdd: provider.addAntenna,
        onDelete: provider.deleteAntenna,
        onClear: provider.clearAntennaDict,
      ),
      _LibraryDefinition(
        type: 'callsign',
        items: provider.callsignDict,
        onAdd: provider.addCallsign,
        onDelete: provider.deleteCallsign,
        onClear: provider.clearCallsignDict,
      ),
      _LibraryDefinition(
        type: 'qth',
        items: provider.qthDict,
        onAdd: provider.addQth,
        onDelete: provider.deleteQth,
        onClear: provider.clearQthDict,
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(libraries),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            const spacing = 12.0;
            final columns = dictionaryGridColumnCount(constraints.maxWidth);
            final width = columns == 1
                ? constraints.maxWidth
                : (constraints.maxWidth - spacing) / columns;
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: libraries
                  .map(
                    (library) => SizedBox(
                      width: width,
                      child: _buildLibraryCard(library),
                    ),
                  )
                  .toList(growable: false),
            );
          },
        ),
      ],
    );
  }
}

class _LibraryDefinition {
  const _LibraryDefinition({
    required this.type,
    required this.items,
    required this.onAdd,
    required this.onDelete,
    required this.onClear,
  });

  final String type;
  final List<DictionaryItem> items;
  final Future<void> Function(String value) onAdd;
  final Future<void> Function(String value) onDelete;
  final Future<void> Function() onClear;
}
