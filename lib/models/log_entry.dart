class LogEntry {
  final String time;
  final String controller;
  final String callsign;
  final String report;
  final String qth;
  final String device;
  final String power;
  final String antenna;
  final String height;

  LogEntry({
    required this.time,
    required this.controller,
    required this.callsign,
    required this.report,
    required this.qth,
    required this.device,
    required this.power,
    required this.antenna,
    required this.height,
  });

  Map<String, dynamic> toJson() {
    return {
      'time': time,
      'controller': controller,
      'callsign': callsign,
      'report': report,
      'qth': qth,
      'device': device,
      'power': power,
      'antenna': antenna,
      'height': height,
    };
  }

  Map<String, dynamic> toMap() {
    return {
      'time': time,
      'controller': controller,
      'callsign': callsign,
      'report': report,
      'qth': qth,
      'device': device,
      'power': power,
      'antenna': antenna,
      'height': height,
    };
  }

  factory LogEntry.fromJson(Map<String, dynamic> json) {
    return LogEntry(
      time: json['time'] ?? '',
      controller: json['controller'] ?? '',
      callsign: json['callsign'] ?? '',
      report: json['report'] ?? '',
      qth: json['qth'] ?? '',
      device: json['device'] ?? '',
      power: json['power'] ?? '',
      antenna: json['antenna'] ?? '',
      height: json['height'] ?? '',
    );
  }

  factory LogEntry.fromMap(Map<String, dynamic> map) {
    return LogEntry(
      time: map['time'] ?? '',
      controller: map['controller'] ?? '',
      callsign: map['callsign'] ?? '',
      report: map['report'] ?? '',
      qth: map['qth'] ?? '',
      device: map['device'] ?? '',
      power: map['power'] ?? '',
      antenna: map['antenna'] ?? '',
      height: map['height'] ?? '',
    );
  }

  List<String> toList() {
    return [
      time,
      controller,
      callsign,
      report,
      qth,
      device,
      power,
      antenna,
      height,
    ];
  }

  LogEntry copyWith({
    String? time,
    String? controller,
    String? callsign,
    String? report,
    String? qth,
    String? device,
    String? power,
    String? antenna,
    String? height,
  }) {
    return LogEntry(
      time: time ?? this.time,
      controller: controller ?? this.controller,
      callsign: callsign ?? this.callsign,
      report: report ?? this.report,
      qth: qth ?? this.qth,
      device: device ?? this.device,
      power: power ?? this.power,
      antenna: antenna ?? this.antenna,
      height: height ?? this.height,
    );
  }
}