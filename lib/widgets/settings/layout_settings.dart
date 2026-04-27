import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:forui/forui.dart';
import 'package:openlogtool/providers/settings_provider.dart';

class LayoutSettings extends StatelessWidget {
  final bool isNarrow;
  final double cardPadding;

  const LayoutSettings({
    super.key,
    required this.isNarrow,
    required this.cardPadding,
  });

  @override
  Widget build(BuildContext context) {
    final settingsProvider = Provider.of<SettingsProvider>(context);

    return FCard(
      child: Padding(
        padding: EdgeInsets.all(cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '布局设置',
              style: TextStyle(
                fontSize: isNarrow ? 14 : 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: isNarrow ? 8 : 12),
            _buildSwitchRow(
              title: '启用宽屏平行布局',
              subtitle: '在窗口宽度足够时，将添加记录和已有记录并排显示',
              value: settingsProvider.wideLayoutEnabled,
              onChanged: (v) => settingsProvider.setWideLayout(v),
            ),
            SizedBox(height: isNarrow ? 10 : 12),
            _buildSwitchRow(
              title: '分页显示记录',
              subtitle: '每5条记录分为一页显示',
              value: settingsProvider.paginationEnabled,
              onChanged: (v) => settingsProvider.setPaginationEnabled(v),
            ),
            SizedBox(height: isNarrow ? 10 : 12),
            _buildSwitchRow(
              title: '呼号-QTH联动',
              subtitle: '自动关联呼号和QTH，输入呼号时显示历史QTH',
              value: settingsProvider.callSignQthLinkEnabled,
              onChanged: (v) => settingsProvider.setCallSignQthLink(v),
            ),
            SizedBox(height: isNarrow ? 10 : 12),
            _buildSwitchRow(
              title: '导入时记录呼号QTH',
              subtitle: '导入JSON时，将呼号与QTH联动记录到历史数据库',
              value: settingsProvider.importCallsignQthHistoryEnabled,
              onChanged: (v) => settingsProvider.setImportCallsignQthHistory(v),
              isNarrow: isNarrow,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSwitchRow({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    bool isNarrow = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: TextStyle(fontSize: isNarrow ? 13 : 14)),
              const SizedBox(height: 2),
              Text(subtitle,
                  style:
                      const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
        ),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }
}
