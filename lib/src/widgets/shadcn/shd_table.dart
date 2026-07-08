import 'package:flutter/material.dart';

class ShColumn {
  final String label;
  final double flex;
  final String? Function(dynamic row) cellBuilder;

  const ShColumn({required this.label, this.flex = 1, required this.cellBuilder});
}

class ShTable extends StatelessWidget {
  final List<ShColumn> columns;
  final List<dynamic> rows;
  final String? emptyMessage;
  final Widget Function(dynamic row)? onRowTap;

  const ShTable({
    super.key,
    required this.columns,
    required this.rows,
    this.emptyMessage,
    this.onRowTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final border = theme.dividerTheme.color ?? const Color(0xFFE4E4E7);

    if (rows.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(emptyMessage ?? '暂无数据', style: theme.textTheme.bodySmall),
        ),
      );
    }

    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: border)),
          ),
          child: Row(
            children: columns.map((col) => Expanded(
              flex: col.flex.round(),
              child: Text(col.label, style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
            )).toList(),
          ),
        ),
        // Rows
        ...rows.asMap().entries.map((entry) {
          final row = entry.value;
          final isEven = entry.key.isEven;
          return InkWell(
            onTap: onRowTap != null ? () => onRowTap!(row) : null,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: isEven ? null : theme.colorScheme.surface.withAlpha(10),
                border: Border(bottom: BorderSide(color: border.withAlpha(100))),
              ),
              child: Row(
                children: columns.map((col) => Expanded(
                  flex: col.flex.round(),
                  child: Text(
                    col.cellBuilder(row) ?? '',
                    style: theme.textTheme.bodyMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                )).toList(),
              ),
            ),
          );
        }),
      ],
    );
  }
}
