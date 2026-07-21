import 'package:flutter_test/flutter_test.dart';
import 'package:openlogtool/services/ai_candidate_guard.dart';
import 'package:openlogtool/services/ai_recognition/models.dart';

void main() {
  test('offers empty fields but requires confirmation for replacements', () {
    final baseline = _snapshot(callsign: '', qth: 'Hangzhou');
    final candidate = RecognitionCandidate(
      fields: const {'callsign': 'BG5CRL', 'qth': 'Ningbo'},
      confidence: 0.9,
    );

    final result = AiCandidateGuard.assess(
      candidate,
      baseline: baseline,
      current: AiCandidateApplicationState(snapshot: baseline),
    );

    expect(_decision(result, 'callsign'), AiCandidateDecision.fillEmpty);
    expect(
      _decision(result, 'qth'),
      AiCandidateDecision.replaceWithConfirmation,
    );
  });

  test('compacts a spaced phonetic callsign without changing other fields', () {
    final baseline = _snapshot(callsign: '', power: '');
    final result = AiCandidateGuard.assess(
      RecognitionCandidate(
        fields: const {'callsign': 'B G 5 E U U', 'power': '低功率'},
      ),
      baseline: baseline,
      current: AiCandidateApplicationState(snapshot: baseline),
    );

    expect(
      result.singleWhere((item) => item.field == 'callsign').value,
      'BG5EUU',
    );
    expect(
      result.singleWhere((item) => item.field == 'power').value,
      '低功率',
    );
  });

  test('never offers time, unknown fields, or non-string output', () {
    final baseline = _snapshot();
    final candidate = RecognitionCandidate(
      fields: const {
        'time': '20:00',
        'controller': 'BA5AAA',
        'unknown': 'value',
        'power': 10,
      },
    );

    final result = AiCandidateGuard.assess(
      candidate,
      baseline: baseline,
      current: AiCandidateApplicationState(snapshot: baseline),
    );

    expect(_decision(result, 'time'), AiCandidateDecision.unsupportedField);
    expect(
      _decision(result, 'controller'),
      AiCandidateDecision.unsupportedField,
    );
    expect(_decision(result, 'unknown'), AiCandidateDecision.unsupportedField);
    expect(_decision(result, 'power'), AiCandidateDecision.invalidValue);
  });

  test('a user edit after capture makes that field stale', () {
    final baseline = _snapshot(callsign: 'B');
    final current = _snapshot(
      callsign: 'BG5CRL',
      callsignRevision: 2,
    );

    final result = AiCandidateGuard.assess(
      RecognitionCandidate(fields: const {'callsign': 'BG5CRL'}),
      baseline: baseline,
      current: AiCandidateApplicationState(snapshot: current),
    );

    expect(result.single.decision, AiCandidateDecision.stale);
  });

  test('record and capture generations prevent late results reaching next row',
      () {
    final baseline = _snapshot();
    final nextRecord = _snapshot(recordEpoch: 2, captureGeneration: 4);

    final result = AiCandidateGuard.assess(
      RecognitionCandidate(fields: const {'callsign': 'BG5CRL'}),
      baseline: baseline,
      current: AiCandidateApplicationState(snapshot: nextRecord),
    );

    expect(result.single.decision, AiCandidateDecision.stale);
  });

  test('a collaboration draft generation change invalidates old output', () {
    final baseline = _snapshot(draftId: 'draft-1');
    final nextDraft = _snapshot(draftId: 'draft-2');

    final result = AiCandidateGuard.assess(
      RecognitionCandidate(fields: const {'callsign': 'BG5CRL'}),
      baseline: baseline,
      current: AiCandidateApplicationState(snapshot: nextDraft),
    );

    expect(result.single.decision, AiCandidateDecision.stale);
  });

  test('IME composition, focus, lock, read-only and busy block application',
      () {
    final baseline = _snapshot(
      callsign: '',
      qth: '',
      power: '',
      remarks: '',
    );
    final candidate = RecognitionCandidate(fields: const {
      'callsign': 'BG5CRL',
      'qth': 'Hangzhou',
      'power': '10W',
      'remarks': 'test',
    });

    expect(
      _decision(
        AiCandidateGuard.assess(
          candidate,
          baseline: baseline,
          current: AiCandidateApplicationState(
            snapshot: baseline,
            composingFields: const {'callsign'},
            focusedFields: const {'qth'},
            lockedFields: const {'power'},
          ),
        ),
        'callsign',
      ),
      AiCandidateDecision.composing,
    );
    expect(
      _decision(
        AiCandidateGuard.assess(
          candidate,
          baseline: baseline,
          current: AiCandidateApplicationState(
            snapshot: baseline,
            focusedFields: const {'qth'},
          ),
        ),
        'qth',
      ),
      AiCandidateDecision.focused,
    );
    expect(
      _decision(
        AiCandidateGuard.assess(
          candidate,
          baseline: baseline,
          current: AiCandidateApplicationState(
            snapshot: baseline,
            lockedFields: const {'power'},
          ),
        ),
        'power',
      ),
      AiCandidateDecision.locked,
    );
    expect(
      _decision(
        AiCandidateGuard.assess(
          candidate,
          baseline: baseline,
          current: AiCandidateApplicationState(
            snapshot: baseline,
            readOnly: true,
          ),
        ),
        'callsign',
      ),
      AiCandidateDecision.readOnly,
    );
    expect(
      _decision(
        AiCandidateGuard.assess(
          candidate,
          baseline: baseline,
          current: AiCandidateApplicationState(
            snapshot: baseline,
            busy: true,
          ),
        ),
        'remarks',
      ),
      AiCandidateDecision.busy,
    );
  });
}

AiCandidateDecision _decision(
  List<AiFieldCandidateAssessment> values,
  String field,
) =>
    values.singleWhere((value) => value.field == field).decision;

AiDraftSnapshot _snapshot({
  String sessionId = 'session-1',
  int recordEpoch = 1,
  int captureGeneration = 3,
  String? draftId,
  String controller = 'BA5AAA',
  String callsign = '',
  String qth = '',
  String power = '',
  String remarks = '',
  int callsignRevision = 1,
}) =>
    AiDraftSnapshot(
      sessionId: sessionId,
      recordEpoch: recordEpoch,
      captureGeneration: captureGeneration,
      draftId: draftId,
      fields: {
        'controller': AiDraftFieldSnapshot(value: controller, revision: 1),
        'callsign': AiDraftFieldSnapshot(
          value: callsign,
          revision: callsignRevision,
        ),
        'qth': AiDraftFieldSnapshot(value: qth, revision: 1),
        'power': AiDraftFieldSnapshot(value: power, revision: 1),
        'remarks': AiDraftFieldSnapshot(value: remarks, revision: 1),
      },
    );
