enum AiRecognitionErrorKind {
  invalidConfiguration,
  unsupportedProtocol,
  missingCredentials,
  audioRejected,
  timeout,
  network,
  httpStatus,
  invalidResponse,
  cancelled,
  closed,
}

final class AiRecognitionException implements Exception {
  const AiRecognitionException({
    required this.kind,
    required this.message,
    this.providerId,
    this.statusCode,
    this.responseBody,
    this.cause,
  });

  final AiRecognitionErrorKind kind;
  final String message;
  final String? providerId;
  final int? statusCode;
  final String? responseBody;
  final Object? cause;

  @override
  String toString() {
    final status = statusCode == null ? '' : ' ($statusCode)';
    final provider = providerId == null ? '' : ' [$providerId]';
    return 'AiRecognitionException$status$provider: ${kind.name}: $message';
  }
}
