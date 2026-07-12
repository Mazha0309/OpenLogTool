import 'package:flutter/widgets.dart';
import 'package:openlogtool/l10n/generated/app_localizations.dart';
import 'package:openlogtool/models/controller_display.dart';

export 'package:openlogtool/l10n/generated/app_localizations.dart';

extension AppLocalizationsContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

Locale resolveAppLocale(Locale? locale, Iterable<Locale> supportedLocales) {
  if (locale?.languageCode.toLowerCase() == 'en') {
    return const Locale('en', 'US');
  }
  return const Locale('zh', 'CN');
}

String controllerFieldLabel(
  AppLocalizations l10n,
  ControllerDisplayField field,
) =>
    switch (field) {
      ControllerDisplayField.controller => l10n.fieldController,
      ControllerDisplayField.callsign => l10n.fieldCallsign,
      ControllerDisplayField.time => l10n.fieldTime,
      ControllerDisplayField.rstSent => l10n.fieldRstSent,
      ControllerDisplayField.rstRcvd => l10n.fieldRstRcvd,
      ControllerDisplayField.qth => l10n.fieldQth,
      ControllerDisplayField.device => l10n.fieldDevice,
      ControllerDisplayField.power => l10n.fieldPower,
      ControllerDisplayField.antenna => l10n.fieldAntenna,
      ControllerDisplayField.height => l10n.fieldHeight,
      ControllerDisplayField.remarks => l10n.fieldRemarks,
    };

String controllerDetailLabel(
  AppLocalizations l10n,
  ControllerDisplayDetail detail,
) =>
    switch (detail) {
      ControllerDisplayDetail.minimal => l10n.detailMinimal,
      ControllerDisplayDetail.standard => l10n.detailStandard,
      ControllerDisplayDetail.full => l10n.detailFull,
      ControllerDisplayDetail.custom => l10n.detailCustom,
    };

String controllerConnectionLabel(
  AppLocalizations l10n,
  ControllerConnectionState state,
) =>
    switch (state) {
      ControllerConnectionState.connected => l10n.connectionConnected,
      ControllerConnectionState.reconnecting => l10n.connectionReconnecting,
      ControllerConnectionState.offline => l10n.connectionOffline,
    };

String collaborationStateLabel(AppLocalizations l10n, String state) =>
    switch (state) {
      'localOnly' => l10n.collaborationLocalOnly,
      'publishing' => l10n.collaborationPublishing,
      'joining' => l10n.collaborationJoining,
      'snapshotting' => l10n.collaborationSnapshotting,
      'catchingUp' => l10n.collaborationCatchingUp,
      'ready' => l10n.collaborationReady,
      'resyncing' => l10n.collaborationResyncing,
      'revoked' => l10n.collaborationRevoked,
      'failed' => l10n.collaborationFailed,
      _ => state,
    };
