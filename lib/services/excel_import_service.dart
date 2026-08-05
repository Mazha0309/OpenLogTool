import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart' show Uint8List;
import 'package:openlogtool/services/text_assistant.dart';

/// 解析 Excel 工作簿：返回第一个工作表的非空行（每行是单元格文本列表）。
List<List<String>> parseExcelRows(Uint8List bytes) {
  final excel = Excel.decodeBytes(bytes);
  final tables = excel.tables;
  if (tables.isEmpty) return const [];
  final sheet = tables.values.first;
  final rows = <List<String>>[];
  for (final row in sheet.rows) {
    final cells = row
        .map((cell) => cell?.value?.toString().trim() ?? '')
        .toList(growable: false);
    if (cells.any((cell) => cell.isNotEmpty)) {
      rows.add(cells);
    }
  }
  return rows;
}

/// 把行文本化，供 LLM 解析（每行用 | 分隔单元格，行首是行号）。
String buildSheetText(List<List<String>> rows) {
  final buffer = StringBuffer();
  for (var i = 0; i < rows.length; i++) {
    buffer.writeln('${i + 1}: ${rows[i].join(' | ')}');
  }
  return buffer.toString();
}

const excelLlmSystemPrompt = '你是业余无线电点名记录助手。用户会提供一张点名记录表的文本行，'
    '请把每一行转换为结构化 JSON 记录。输出格式：'
    '{"records":[{"callsign":"呼号（必填，大写字母数字）",'
    '"time":"时间（可选，HH:mm 或原样）","rstSent":"RST 发送（可选）",'
    '"rstRcvd":"RST 接收（可选）","qth":"QTH 地名（可选）",'
    '"device":"设备型号（可选）","power":"功率（可选）",'
    '"remarks":"备注（可选）"}]}。'
    '无法识别为点名记录的行直接跳过，不要输出。只输出 JSON，不要解释。';

/// 让 LLM 把文本行解析为结构化记录数组。
Future<List<Map<String, Object?>>> structureWithLlm(
  TextAssistantClient client,
  String sheetText,
) async {
  final result = await client.completeJson(
    systemPrompt: excelLlmSystemPrompt,
    userPrompt: sheetText,
    maxOutputTokens: 2048,
  );
  final records = result['records'];
  return validateLlmOutput(records);
}

/// 校验并清洗 LLM 输出：必须是记录数组，每项呼号必填（大写化），
/// 剔除空项与非法项。
List<Map<String, Object?>> validateLlmOutput(Object? records) {
  if (records is! List) return const [];
  final output = <Map<String, Object?>>[];
  for (final item in records) {
    if (item is! Map) continue;
    final record = Map<String, Object?>.from(item);
    final callsign = record['callsign']?.toString().trim().toUpperCase() ?? '';
    if (callsign.isEmpty) continue;
    record['callsign'] = callsign;
    for (final key in <String>[
      'time',
      'rstSent',
      'rstRcvd',
      'qth',
      'device',
      'power',
      'remarks',
    ]) {
      final value = record[key];
      if (value != null) {
        record[key] = value.toString().trim();
      }
    }
    output.add(record);
  }
  return output;
}
