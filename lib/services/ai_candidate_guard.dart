import 'package:flutter/foundation.dart';
import 'package:openlogtool/services/ai_recognition/models.dart';

@immutable
final class AiDraftFieldSnapshot {
  const AiDraftFieldSnapshot({
    required this.value,
    required this.revision,
    this.remoteRevision,
  });

  final String value;
  final int revision;
  final int? remoteRevision;
}

/// Identity and field state captured when an audio recognition request starts.
/// [recordEpoch] must change whenever the visible recorder is cleared or moves
/// to its next record, even when a collaboration draft ID is reused locally.
@immutable
final class AiDraftSnapshot {
  AiDraftSnapshot({
    required this.sessionId,
    required this.recordEpoch,
    required this.captureGeneration,
    required Map<String, AiDraftFieldSnapshot> fields,
    this.draftId,
  }) : fields = Map.unmodifiable(fields);

  final String sessionId;
  final int recordEpoch;
  final int captureGeneration;
  final String? draftId;
  final Map<String, AiDraftFieldSnapshot> fields;
}

@immutable
final class AiCandidateApplicationState {
  AiCandidateApplicationState({
    required this.snapshot,
    Set<String> focusedFields = const {},
    Set<String> composingFields = const {},
    Set<String> lockedFields = const {},
    this.readOnly = false,
    this.busy = false,
  })  : focusedFields = Set.unmodifiable(focusedFields),
        composingFields = Set.unmodifiable(composingFields),
        lockedFields = Set.unmodifiable(lockedFields);

  final AiDraftSnapshot snapshot;
  final Set<String> focusedFields;
  final Set<String> composingFields;
  final Set<String> lockedFields;
  final bool readOnly;
  final bool busy;
}

enum AiCandidateDecision {
  fillEmpty,
  replaceWithConfirmation,
  unchanged,
  stale,
  focused,
  composing,
  locked,
  readOnly,
  busy,
  unsupportedField,
  invalidValue,
}

@immutable
final class AiFieldCandidateAssessment {
  const AiFieldCandidateAssessment({
    required this.field,
    required this.value,
    required this.decision,
    required this.currentValue,
    this.confidence,
  });

  final String field;
  final String value;
  final String currentValue;
  final AiCandidateDecision decision;
  final double? confidence;

  bool get canOfferApply =>
      decision == AiCandidateDecision.fillEmpty ||
      decision == AiCandidateDecision.replaceWithConfirmation;

  bool get requiresReplacementConfirmation =>
      decision == AiCandidateDecision.replaceWithConfirmation;
}

/// Evaluates AI output without mutating the draft.
///
/// The UI may offer an explicit apply action only for [canOfferApply]. It must
/// repeat this evaluation immediately before a local update or a collaboration
/// compare-and-swap request.
abstract final class AiCandidateGuard {
  static const Set<String> supportedFields = {
    'callsign',
    'device',
    'antenna',
    'power',
    'qth',
    'height',
    'rstSent',
    'rstRcvd',
    'remarks',
  };

  static const Map<String, int> _maxLengths = {
    'callsign': 64,
    'device': 256,
    'antenna': 256,
    'power': 64,
    'qth': 256,
    'height': 64,
    'rstSent': 16,
    'rstRcvd': 16,
    'remarks': 1000,
  };

  static List<AiFieldCandidateAssessment> assess(
    RecognitionCandidate candidate, {
    required AiDraftSnapshot baseline,
    required AiCandidateApplicationState current,
  }) {
    final sameGeneration = _sameGeneration(baseline, current.snapshot);
    return candidate.fields.entries.map((entry) {
      final field = entry.key;
      final currentField = current.snapshot.fields[field];
      final baselineField = baseline.fields[field];
      final rawValue = entry.value;
      final value =
          rawValue is String ? _normalizeCandidateValue(field, rawValue) : '';
      final currentValue = currentField?.value ?? '';

      if (!supportedFields.contains(field)) {
        return _assessment(
          candidate,
          field,
          value,
          currentValue,
          AiCandidateDecision.unsupportedField,
        );
      }
      if (rawValue is! String ||
          value.isEmpty ||
          value.length > (_maxLengths[field] ?? 256)) {
        return _assessment(
          candidate,
          field,
          value,
          currentValue,
          AiCandidateDecision.invalidValue,
        );
      }
      if (!sameGeneration ||
          baselineField == null ||
          currentField == null ||
          baselineField.revision != currentField.revision ||
          baselineField.value != currentField.value) {
        return _assessment(
          candidate,
          field,
          value,
          currentValue,
          AiCandidateDecision.stale,
        );
      }
      if (current.readOnly) {
        return _assessment(
          candidate,
          field,
          value,
          currentValue,
          AiCandidateDecision.readOnly,
        );
      }
      if (current.busy) {
        return _assessment(
          candidate,
          field,
          value,
          currentValue,
          AiCandidateDecision.busy,
        );
      }
      if (current.composingFields.contains(field)) {
        return _assessment(
          candidate,
          field,
          value,
          currentValue,
          AiCandidateDecision.composing,
        );
      }
      if (current.focusedFields.contains(field)) {
        return _assessment(
          candidate,
          field,
          value,
          currentValue,
          AiCandidateDecision.focused,
        );
      }
      if (current.lockedFields.contains(field)) {
        return _assessment(
          candidate,
          field,
          value,
          currentValue,
          AiCandidateDecision.locked,
        );
      }
      if (currentValue == value) {
        return _assessment(
          candidate,
          field,
          value,
          currentValue,
          AiCandidateDecision.unchanged,
        );
      }
      return _assessment(
        candidate,
        field,
        value,
        currentValue,
        currentValue.trim().isEmpty
            ? AiCandidateDecision.fillEmpty
            : AiCandidateDecision.replaceWithConfirmation,
      );
    }).toList(growable: false);
  }

  static bool _sameGeneration(AiDraftSnapshot a, AiDraftSnapshot b) =>
      a.sessionId == b.sessionId &&
      a.recordEpoch == b.recordEpoch &&
      a.captureGeneration == b.captureGeneration &&
      a.draftId == b.draftId;

  static String _normalizeCandidateValue(String field, String rawValue) {
    final value = rawValue.trim();
    if (field != 'callsign') return value;
    final upper = value.toUpperCase();
    final compact = upper.replaceAll(RegExp(r'\s+'), '');
    if (RegExp(r'^[A-Z0-9]+(?:/[A-Z0-9]+)?$').hasMatch(compact) &&
        RegExp(r'[A-Z]').hasMatch(compact) &&
        RegExp(r'\d').hasMatch(compact)) {
      return compact;
    }
    return upper;
  }

  static AiFieldCandidateAssessment _assessment(
    RecognitionCandidate candidate,
    String field,
    String value,
    String currentValue,
    AiCandidateDecision decision,
  ) =>
      AiFieldCandidateAssessment(
        field: field,
        value: value,
        currentValue: currentValue,
        decision: decision,
        confidence: candidate.confidence,
      );
}
