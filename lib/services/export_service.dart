import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:excel/excel.dart' as excel_lib;
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:openlogtool/models/export_settings.dart';
import 'package:openlogtool/models/log_entry.dart';

class ExportSaveResult {
  final String? path;
  final bool usedSaf;
  final bool cancelled;

  const ExportSaveResult({
    this.path,
    this.usedSaf = false,
    this.cancelled = false,
  });
}

class ExportService {
  /// 根据配置的平台路径和平台类型，解析实际可用的导出路径。
  static Future<String?> resolveExportPath(String configuredPath) async {
    if (!Platform.isAndroid && configuredPath.isNotEmpty) {
      return configuredPath;
    }

    final directory = await getDownloadsDirectory();
    return directory?.path;
  }

  /// 判断当前 [configuredPath] 是否在 Android 上需要走 SAF 文件选择器。
  /// 桌面端始终返回 false。
  static Future<bool> shouldUseSaf(String configuredPath) async {
    if (!Platform.isAndroid) {
      return false;
    }

    final normalizedConfiguredPath = configuredPath.trim();
    if (normalizedConfiguredPath.isEmpty) {
      return false;
    }

    final downloadsDirectory = await getDownloadsDirectory();
    final downloadsPath = downloadsDirectory?.path;
    if (downloadsPath == null) {
      return true;
    }

    final normalizedDownloadsPath = _normalizePath(downloadsPath);
    final normalizedConfigured = _normalizePath(normalizedConfiguredPath);

    return !(normalizedConfigured == normalizedDownloadsPath ||
        normalizedConfigured.startsWith('$normalizedDownloadsPath/'));
  }

  /// 保存二进制数据到文件。
  /// Android 上如需 SAF，使用 [FilePicker.saveFile]；其余平台直接写文件。
  static Future<ExportSaveResult> saveFile({
    required String configuredPath,
    required String filename,
    required Uint8List bytes,
    required String dialogTitle,
    required List<String> allowedExtensions,
  }) async {
    if (await shouldUseSaf(configuredPath)) {
      final result = await FilePicker.platform.saveFile(
        dialogTitle: dialogTitle,
        fileName: filename,
        type: FileType.custom,
        allowedExtensions: allowedExtensions,
        bytes: bytes,
      );

      if (result == null) {
        return const ExportSaveResult(cancelled: true, usedSaf: true);
      }

      return ExportSaveResult(path: result, usedSaf: true);
    }

    final exportPath = await resolveExportPath(configuredPath);
    if (exportPath == null) {
      return const ExportSaveResult();
    }

    final file = File('$exportPath/$filename');
    await file.writeAsBytes(bytes);
    return ExportSaveResult(path: file.path, usedSaf: false);
  }

  /// 从模板和当前时间生成导出文件名。
  static String generateFileName(String template, DateTime now) {
    String filename = template;
    filename = filename.replaceAll('{yyyy}', now.year.toString());
    filename = filename.replaceAll('{MM}', now.month.toString().padLeft(2, '0'));
    filename = filename.replaceAll('{dd}', now.day.toString().padLeft(2, '0'));
    filename = filename.replaceAll('{HH}', now.hour.toString().padLeft(2, '0'));
    filename = filename.replaceAll('{mm}', now.minute.toString().padLeft(2, '0'));
    filename = filename.replaceAll('{ss}', now.second.toString().padLeft(2, '0'));
    return filename;
  }

  static String _normalizePath(String path) {
    var normalized = path.replaceAll('\\', '/').trim();
    while (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  /// 将日志列表序列化为 JSON 字符串的字节。
  static Uint8List generateJsonBytes(List<LogEntry> logs) {
    final jsonData = logs.map((log) => log.toJson()).toList();
    final jsonString = const JsonEncoder.withIndent('  ').convert(jsonData);
    return Uint8List.fromList(utf8.encode(jsonString));
  }

  /// 根据日志列表和导出设置生成 Excel 文件字节。
  static Uint8List? generateExcelBytes(
    List<LogEntry> logs,
    ExportSettings settings,
    DateTime now,
  ) {
    final excel = excel_lib.Excel.createExcel();
    final sheet = excel['点名记录'];

    final defaultSheet = excel.getDefaultSheet();
    if (defaultSheet != null && defaultSheet != '点名记录') {
      excel.delete(defaultSheet);
    }

    final headerColor =
        excel_lib.ExcelColor.fromInt(settings.headerBackgroundColor.toARGB32());
    final headerRowColor =
        excel_lib.ExcelColor.fromInt(settings.headerRowBackgroundColor.toARGB32());
    final controllerColor =
        excel_lib.ExcelColor.fromInt(settings.controllerBackgroundColor.toARGB32());
    final alternateColor =
        excel_lib.ExcelColor.fromInt(settings.alternateRowColor.toARGB32());
    const whiteColor = excel_lib.ExcelColor.white;

    final borderStyle = excel_lib.Border(
      borderStyle: excel_lib.BorderStyle.Thin,
      borderColorHex: excel_lib.ExcelColor.grey,
    );

    final String? excelFontFamily =
        settings.fontFamily.isEmpty ? null : settings.fontFamily;

    // Header
    String headerText = generateFileName(settings.headerText, now);
    sheet.insertRowIterables([excel_lib.TextCellValue(headerText)], 0);
    sheet.merge(
      excel_lib.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0),
      excel_lib.CellIndex.indexByColumnRow(columnIndex: 9, rowIndex: 0),
      customValue: excel_lib.TextCellValue(headerText),
    );
    sheet.row(0).forEach((cell) {
      if (cell != null) {
        cell.cellStyle = excel_lib.CellStyle(
          backgroundColorHex: headerColor,
          fontSize: 14,
          bold: true,
          fontFamily: excelFontFamily,
          horizontalAlign: excel_lib.HorizontalAlign.Center,
          verticalAlign: excel_lib.VerticalAlign.Center,
          textWrapping: excel_lib.TextWrapping.WrapText,
          topBorder: borderStyle,
          bottomBorder: borderStyle,
          leftBorder: borderStyle,
          rightBorder: borderStyle,
        );
      }
    });
    sheet.setRowHeight(0, 30);

    // Column headers
    final headers = ['#', '时间', '呼号', '信号报告', 'QTH', '设备', '功率', '天线', '高度', '备注'];
    sheet.insertRowIterables(
      headers.map((e) => excel_lib.TextCellValue(e)).toList(),
      1,
    );
    sheet.row(1).forEach((cell) {
      if (cell != null) {
        cell.cellStyle = excel_lib.CellStyle(
          backgroundColorHex: headerRowColor,
          fontSize: 12,
          bold: true,
          fontFamily: excelFontFamily,
          horizontalAlign: excel_lib.HorizontalAlign.Center,
          verticalAlign: excel_lib.VerticalAlign.Center,
          topBorder: borderStyle,
          bottomBorder: borderStyle,
          leftBorder: borderStyle,
          rightBorder: borderStyle,
        );
      }
    });
    sheet.setRowHeight(1, 25);

    // Group by controller
    final grouped = <String, List<LogEntry>>{};
    for (final log in logs) {
      grouped.putIfAbsent(log.controller, () => []).add(log);
    }

    int globalIndex = 1;
    int currentRow = 2;

    for (final controller in grouped.keys) {
      final controllerLogs = grouped[controller]!;
      final firstTime =
          controllerLogs.isNotEmpty ? controllerLogs.first.time : '';
      final controllerTime = calculateControllerTime(firstTime);

      final controllerRow = <String>[
        '点名主控:', controllerTime, controller, '', '', '', '', '', '', ''];
      sheet.insertRowIterables(
        controllerRow.map((e) => excel_lib.TextCellValue(e)).toList(),
        currentRow,
      );
      sheet.row(currentRow).forEach((cell) {
        if (cell != null) {
          cell.cellStyle = excel_lib.CellStyle(
            backgroundColorHex: controllerColor,
            fontSize: 11,
            bold: true,
            fontFamily: excelFontFamily,
            horizontalAlign: excel_lib.HorizontalAlign.Center,
            verticalAlign: excel_lib.VerticalAlign.Center,
            topBorder: borderStyle,
            bottomBorder: borderStyle,
            leftBorder: borderStyle,
            rightBorder: borderStyle,
          );
        }
      });
      sheet.setRowHeight(currentRow, 20);
      currentRow++;

      for (int i = 0; i < controllerLogs.length; i++) {
        final log = controllerLogs[i];
        final rowColor = settings.useAlternateColors && i % 2 == 1
            ? alternateColor
            : whiteColor;

        final rowData = [
          excel_lib.TextCellValue(globalIndex.toString()),
          excel_lib.TextCellValue(log.time),
          excel_lib.TextCellValue(log.callsign),
          excel_lib.TextCellValue(log.report),
          excel_lib.TextCellValue(log.qth),
          excel_lib.TextCellValue(log.device),
          excel_lib.TextCellValue(log.power),
          excel_lib.TextCellValue(log.antenna),
          excel_lib.TextCellValue(log.height),
          excel_lib.TextCellValue(''),
        ];
        sheet.insertRowIterables(rowData, currentRow);
        sheet.row(currentRow).forEach((cell) {
          if (cell != null) {
            cell.cellStyle = excel_lib.CellStyle(
              backgroundColorHex: rowColor,
              fontSize: 11,
              fontFamily: excelFontFamily,
              horizontalAlign: excel_lib.HorizontalAlign.Center,
              verticalAlign: excel_lib.VerticalAlign.Center,
              topBorder: borderStyle,
              bottomBorder: borderStyle,
              leftBorder: borderStyle,
              rightBorder: borderStyle,
            );
          }
        });
        sheet.setRowHeight(currentRow, 20);
        globalIndex++;
        currentRow++;
      }
    }

    // Footer
    if (settings.showFooter) {
      currentRow += 2;
      const footerBgColor = excel_lib.ExcelColor.white;
      const footerTextColor = excel_lib.ExcelColor.grey;
      final lightGreyBorder = excel_lib.Border(
        borderStyle: excel_lib.BorderStyle.Thin,
        borderColorHex: excel_lib.ExcelColor.grey,
      );

      final footerTexts = [
        '此表格由 OpenLogTool 生成导出，本项目使用开源协议: GNU Affero General Public License V3',
        '项目仓库地址: https://github.com/Mazha0309/OpenLogTool',
        '分享点名记录时无须携带本条说明',
      ];

      for (final text in footerTexts) {
        sheet.insertRowIterables(
          [excel_lib.TextCellValue(text)],
          currentRow,
        );
        sheet.merge(
          excel_lib.CellIndex.indexByColumnRow(
              columnIndex: 0, rowIndex: currentRow),
          excel_lib.CellIndex.indexByColumnRow(
              columnIndex: 9, rowIndex: currentRow),
          customValue: excel_lib.TextCellValue(text),
        );
        sheet.row(currentRow).forEach((cell) {
          if (cell != null) {
            cell.cellStyle = excel_lib.CellStyle(
              backgroundColorHex: footerBgColor,
              fontColorHex: footerTextColor,
              fontSize: 10,
              fontFamily: excelFontFamily,
              horizontalAlign: excel_lib.HorizontalAlign.Center,
              verticalAlign: excel_lib.VerticalAlign.Center,
              leftBorder: lightGreyBorder,
              rightBorder: lightGreyBorder,
            );
          }
        });
        sheet.setRowHeight(currentRow, 22);
        currentRow++;
      }
    }

    // Column widths
    const colWidths = <double>[10, 10, 15, 12, 18, 15, 10, 18, 10, 10];
    for (var i = 0; i < colWidths.length; i++) {
      sheet.setColumnWidth(i, colWidths[i]);
    }

    final saved = excel.save();
    return saved != null ? Uint8List.fromList(saved) : null;
  }

  /// 计算控制器时间显示值（比第一条记录早一分钟并取整）。
  static String calculateControllerTime(String timeStr) {
    if (timeStr.isEmpty) return '';

    final parts = timeStr.split(':');
    if (parts.length < 2) return timeStr;

    var hours = int.tryParse(parts[0]) ?? 0;
    var minutes = int.tryParse(parts[1]) ?? 0;

    minutes -= 1;
    if (minutes < 0) {
      minutes = 59;
      hours = (hours - 1) % 24;
    }

    if (minutes % 5 == 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}';
    }

    final nearestFive = (minutes / 5).round() * 5;
    final nearestTen = (minutes / 10).round() * 10;

    final diffToFive = (minutes - nearestFive).abs();
    final diffToTen = (minutes - nearestTen).abs();

    if (diffToTen == 1 || nearestTen == 60) {
      minutes = nearestTen == 60 ? 0 : nearestTen;
      if (nearestTen == 60) {
        hours = (hours + 1) % 24;
      }
    } else if (diffToFive == 1) {
      minutes = nearestFive % 60;
      if (nearestFive == 60) {
        hours = (hours + 1) % 24;
        minutes = 0;
      }
    }

    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}';
  }
}

/// JSON 导入解析结果。
class ImportResult {
  final List<LogEntry> logs;
  final List<List<String>> callsignQthPairs;

  const ImportResult({
    required this.logs,
    required this.callsignQthPairs,
  });
}

/// 从 JSON 字符串解析导入数据。
/// 支持两种格式：OpenLogTool 原生 JSON（数组）和 HamTool 导出格式（含 `currentRecords` 的 Map）。
/// [recordCallsignQth] 决定是否收集呼号-QTH 对用于后续历史记录。
ImportResult parseJsonImport(
  String jsonString, {
  bool recordCallsignQth = true,
}) {
  final jsonData = json.decode(jsonString);
  final List<LogEntry> importedLogs;
  final List<List<String>> callsignQthPairs = [];

  if (jsonData is Map && jsonData.containsKey('currentRecords')) {
    // HamTool format compatibility
    final records = jsonData['currentRecords'] as List;
    importedLogs = records.map((item) {
      String time = '';
      final createdAt = item['created_at'];
      if (createdAt != null) {
        try {
          final dt = DateTime.parse(createdAt.toString());
          time =
              '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
        } catch (_) {}
      }

      String callsign = '';
      String qth = '';
      if (item['called_call'] != null) {
        callsign = item['called_call'].toString();
      }
      if (item['qth'] != null) {
        qth = item['qth'].toString();
      }

      if (recordCallsignQth && callsign.isNotEmpty && qth.isNotEmpty) {
        callsignQthPairs.add([callsign, qth]);
      }

      String report = '59';
      if (item['signal_report'] != null) {
        report = item['signal_report'].toString();
      }

      return LogEntry(
        time: time,
        controller: item['controller_call']?.toString() ?? '',
        callsign: callsign,
        report: report,
        qth: qth,
        device: item['device']?.toString() ?? '',
        power: item['power']?.toString() ?? '',
        antenna: item['antenna']?.toString() ?? '',
        height: item['height']?.toString() ?? '',
      );
    }).toList();
  } else if (jsonData is List) {
    // OpenLogTool JSON format
    importedLogs = jsonData.map((item) {
      String callsign = '';
      String qth = '';
      if (item['callsign'] != null) callsign = item['callsign'].toString();
      if (item['qth'] != null) qth = item['qth'].toString();

      if (recordCallsignQth && callsign.isNotEmpty && qth.isNotEmpty) {
        callsignQthPairs.add([callsign, qth]);
      }

      return LogEntry(
        time: item['time']?.toString() ?? '',
        controller: item['controller']?.toString() ?? '',
        callsign: callsign,
        report: item['report']?.toString() ?? '59',
        qth: qth,
        device: item['device']?.toString() ?? '',
        power: item['power']?.toString() ?? '',
        antenna: item['antenna']?.toString() ?? '',
        height: item['height']?.toString() ?? '',
      );
    }).toList();
  } else {
    throw FormatException('未知的JSON格式');
  }

  return ImportResult(logs: importedLogs, callsignQthPairs: callsignQthPairs);
}
