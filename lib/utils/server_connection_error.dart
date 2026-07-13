import 'package:openlogtool/l10n/generated/app_localizations.dart';
import 'package:openlogtool/services/server_api.dart';

String localizedServerConnectionError({
  required AppLocalizations l10n,
  required String serverUrl,
  required Object error,
}) {
  final normalizedUrl = serverUrl.trim();
  final uri = Uri.tryParse(normalizedUrl);
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
