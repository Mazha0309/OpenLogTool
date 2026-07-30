import 'package:flutter/foundation.dart';
import 'package:openlogtool/l10n/generated/app_localizations.dart';
import 'package:openlogtool/services/server_api.dart';

String localizedServerConnectionError({
  required AppLocalizations l10n,
  required String serverUrl,
  required Object error,
  bool? isWeb,
  Uri? pageUri,
}) {
  final normalizedUrl = serverUrl.trim();
  final uri = Uri.tryParse(normalizedUrl);
  final runningOnWeb = isWeb ?? kIsWeb;
  final currentPageUri = pageUri ?? Uri.base;
  late final String detail;
  if (normalizedUrl.isEmpty) {
    detail = l10n.serverAddressRequired;
  } else if (uri == null ||
      !uri.hasScheme ||
      !const {'http', 'https'}.contains(uri.scheme.toLowerCase()) ||
      uri.host.isEmpty) {
    detail = l10n.serverAddressInvalid;
  } else if (error is ServerApiException) {
    detail = switch (error.code) {
      'NETWORK_ERROR'
          when runningOnWeb &&
              currentPageUri.scheme.toLowerCase() == 'https' &&
              uri.scheme.toLowerCase() == 'http' =>
        l10n.serverWebMixedContentError(normalizedUrl),
      'NETWORK_ERROR'
          when runningOnWeb && _isCrossOrigin(currentPageUri, uri) =>
        l10n.serverWebCrossOriginError(
          normalizedUrl,
          currentPageUri.origin,
        ),
      'NETWORK_ERROR' => l10n.serverNetworkError(normalizedUrl),
      'NETWORK_TIMEOUT' => l10n.serverNetworkTimeout(normalizedUrl),
      'INVALID_RESPONSE' => l10n.serverInvalidResponse(normalizedUrl),
      _ => '${error.code}: ${error.message}',
    };
  } else {
    detail = error.toString().replaceFirst('Bad state: ', '');
  }
  return l10n.serverConnectionFailed(detail);
}

bool _isCrossOrigin(Uri pageUri, Uri serverUri) {
  if (!const {'http', 'https'}.contains(pageUri.scheme.toLowerCase()) ||
      pageUri.host.isEmpty) {
    return false;
  }
  return pageUri.scheme.toLowerCase() != serverUri.scheme.toLowerCase() ||
      pageUri.host.toLowerCase() != serverUri.host.toLowerCase() ||
      _effectivePort(pageUri) != _effectivePort(serverUri);
}

int _effectivePort(Uri uri) {
  if (uri.hasPort) return uri.port;
  return switch (uri.scheme.toLowerCase()) {
    'http' => 80,
    'https' => 443,
    _ => 0,
  };
}
