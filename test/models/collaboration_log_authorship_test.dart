import 'package:flutter_test/flutter_test.dart';
import 'package:openlogtool/models/collaboration_dto.dart';

void main() {
  test('canonical log parses and serializes authorship', () {
    final log = CollaborationLogDto.fromJson(_logJson(
      createdBy: 'user-1',
      updatedBy: 'user-2',
    ));

    expect(log.createdBy, 'user-1');
    expect(log.updatedBy, 'user-2');
    expect(log.toJson()['createdBy'], 'user-1');
    expect(log.toJson()['updatedBy'], 'user-2');
  });

  test('old canonical log without authorship remains parseable and read-only',
      () {
    final log = CollaborationLogDto.fromJson(_logJson());

    expect(log.createdBy, isNull);
    expect(log.updatedBy, isNull);
  });
}

Map<String, Object?> _logJson({String? createdBy, String? updatedBy}) => {
      'syncId': 'log-1',
      'sessionId': 'session-1',
      'version': 1,
      'time': '2026-07-13T00:00:00Z',
      'controller': 'BG5CRL',
      'callsign': 'BA1ABC',
      'rstSent': '59',
      'rstRcvd': '59',
      'qth': null,
      'device': null,
      'power': null,
      'antenna': null,
      'height': null,
      'remarks': null,
      if (createdBy != null) 'createdBy': createdBy,
      if (updatedBy != null) 'updatedBy': updatedBy,
      'createdAt': '2026-07-13T00:00:00Z',
      'updatedAt': '2026-07-13T00:00:00Z',
      'deletedAt': null,
    };
