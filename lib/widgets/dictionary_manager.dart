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
        Wrap(
          spacing: 12,
          runSpacing: 8,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 420,
              child: Column(
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
              ),
            ),
            Wrap(
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
            ),
          ],
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
                        _buildItemList(library, items),
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

  Widget _buildItemList(
    _LibraryDefinition library,
    List<DictionaryItem> items,
  ) {
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
            leading: CircleAvatar(
              radius: 13,
              child: Text('${index + 1}', style: theme.textTheme.labelSmall),
            ),
            title: Text(item.raw),
            subtitle: searchHint.isEmpty ? null : Text(searchHint),
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
      ),
      _LibraryDefinition(
        type: 'antenna',
        items: provider.antennaDict,
        onAdd: provider.addAntenna,
      ),
      _LibraryDefinition(
        type: 'callsign',
        items: provider.callsignDict,
        onAdd: provider.addCallsign,
      ),
      _LibraryDefinition(
        type: 'qth',
        items: provider.qthDict,
        onAdd: provider.addQth,
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
  });

  final String type;
  final List<DictionaryItem> items;
  final Future<void> Function(String value) onAdd;
}
