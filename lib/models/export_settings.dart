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

  ExportSettings({
    this.headerText = '{yyyy-MM-dd}日点名记录',
    this.headerDateFormat = 'yyyy-MM-dd',
    this.headerBackgroundColor = const Color(0xFFC0E5F2),
    this.headerRowBackgroundColor = const Color(0xFFCFE7FF),
    this.controllerBackgroundColor = const Color(0xFFFFFFC3),
    this.tableBackgroundColor = Colors.white,
    this.alternateRowColor = const Color(0xFFC0E5F2),
    this.useAlternateColors = true,
    this.fontFamily = 'Roboto',
    this.showFooter = true,
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
    };
  }

  factory ExportSettings.fromJson(Map<String, dynamic> json) {
    return ExportSettings(
      headerText: json['headerText'] ?? 'BR5AI {yyyy-MM-dd}日点名记录',
      headerDateFormat: json['headerDateFormat'] ?? 'yyyy-MM-dd',
      headerBackgroundColor: Color(json['headerBackgroundColor'] ?? 0xFF2196F3),
      headerRowBackgroundColor: Color(json['headerRowBackgroundColor'] ?? 0xFF1976D2),
      controllerBackgroundColor: Color(json['controllerBackgroundColor'] ?? 0xFFFFFF00),
      tableBackgroundColor: Color(json['tableBackgroundColor'] ?? 0xFFFFFFFF),
      alternateRowColor: Color(json['alternateRowColor'] ?? 0xFFADD8E6),
      useAlternateColors: json['useAlternateColors'] ?? true,
      fontFamily: json['fontFamily'] ?? 'Roboto',
      showFooter: json['showFooter'] ?? true,
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
    );
  }
}
