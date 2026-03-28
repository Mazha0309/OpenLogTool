import 'package:flutter/material.dart';

class ExportSettings {
  String headerText;
  String headerDateFormat;
  Color headerBackgroundColor;
  Color headerRowBackgroundColor;
  Color controllerBackgroundColor;
  Color tableBackgroundColor;
  Color alternateRowColor;
  bool useAlternateColors;
  String fontFamily;
  bool showFooter;
  String exportPath;
  String fileNameTemplate;

  ExportSettings({
    this.headerText = '{yyyy}-{MM}-{dd}日点名记录',
    this.headerDateFormat = 'yyyy-MM-dd',
    this.headerBackgroundColor = const Color(0xFF1E84D2),
    this.headerRowBackgroundColor = const Color(0xFFCFE7FF),
    this.controllerBackgroundColor = const Color(0xFFFFFFC3),
    this.tableBackgroundColor = Colors.white,
    this.alternateRowColor = const Color(0xFFC0E5F2),
    this.useAlternateColors = true,
    this.fontFamily = 'SarasaGothicSC',
    this.showFooter = true,
    this.exportPath = '',
  this.fileNameTemplate = '点名记录_{yyyy}-{MM}-{dd}',
  });

  Map<String, dynamic> toJson() {
    return {
      'headerText': headerText,
      'headerDateFormat': headerDateFormat,
      'headerBackgroundColor': headerBackgroundColor.toARGB32(),
      'headerRowBackgroundColor': headerRowBackgroundColor.toARGB32(),
      'controllerBackgroundColor': controllerBackgroundColor.toARGB32(),
      'tableBackgroundColor': tableBackgroundColor.toARGB32(),
      'alternateRowColor': alternateRowColor.toARGB32(),
      'useAlternateColors': useAlternateColors,
      'fontFamily': fontFamily,
      'showFooter': showFooter,
      'exportPath': exportPath,
      'fileNameTemplate': fileNameTemplate,
    };
  }

  factory ExportSettings.fromJson(Map<String, dynamic> json) {
    // 辅助函数：将可能为负数的颜色值转换为正确的Color
    Color parseColor(dynamic value, int defaultValue) {
      if (value == null) return Color(defaultValue);
      // 处理有符号整数转换为无符号
      final intValue = value is int ? value : defaultValue;
      return Color(intValue & 0xFFFFFFFF);
    }

    return ExportSettings(
      headerText: json['headerText'] ?? '{yyyy}-{MM}-{dd}日点名记录',
      headerDateFormat: json['headerDateFormat'] ?? 'yyyy-MM-dd',
      headerBackgroundColor: parseColor(json['headerBackgroundColor'], 0xFF1E84D2),
      headerRowBackgroundColor: parseColor(json['headerRowBackgroundColor'], 0xFFCFE7FF),
      controllerBackgroundColor: parseColor(json['controllerBackgroundColor'], 0xFFFFFFC3),
      tableBackgroundColor: parseColor(json['tableBackgroundColor'], 0xFFFFFFFF),
      alternateRowColor: parseColor(json['alternateRowColor'], 0xFFC0E5F2),
      useAlternateColors: json['useAlternateColors'] ?? true,
      fontFamily: json['fontFamily'] ?? 'SarasaGothicSC',
      showFooter: json['showFooter'] ?? true,
      exportPath: json['exportPath'] ?? '',
        fileNameTemplate: json['fileNameTemplate'] ?? '点名记录_{yyyy}-{MM}-{dd}',
    );
  }

  ExportSettings copyWith({
    String? headerText,
    String? headerDateFormat,
    Color? headerBackgroundColor,
    Color? headerRowBackgroundColor,
    Color? controllerBackgroundColor,
    Color? tableBackgroundColor,
    Color? alternateRowColor,
    bool? useAlternateColors,
    String? fontFamily,
    bool? showFooter,
    String? exportPath,
    String? fileNameTemplate,
  }) {
    return ExportSettings(
      headerText: headerText ?? this.headerText,
      headerDateFormat: headerDateFormat ?? this.headerDateFormat,
      headerBackgroundColor: headerBackgroundColor ?? this.headerBackgroundColor,
      headerRowBackgroundColor: headerRowBackgroundColor ?? this.headerRowBackgroundColor,
      controllerBackgroundColor: controllerBackgroundColor ?? this.controllerBackgroundColor,
      tableBackgroundColor: tableBackgroundColor ?? this.tableBackgroundColor,
      alternateRowColor: alternateRowColor ?? this.alternateRowColor,
      useAlternateColors: useAlternateColors ?? this.useAlternateColors,
      fontFamily: fontFamily ?? this.fontFamily,
      showFooter: showFooter ?? this.showFooter,
      exportPath: exportPath ?? this.exportPath,
      fileNameTemplate: fileNameTemplate ?? this.fileNameTemplate,
    );
  }
}
