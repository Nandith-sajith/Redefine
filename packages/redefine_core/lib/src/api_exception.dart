/// Every failure of an API call, with a message that is safe to show.
class ApiException implements Exception {
  const ApiException(
    this.statusCode,
    this.code,
    this.message, {
    this.extra = const <String, dynamic>{},
  });

  /// HTTP status, or 0 when no response arrived (network, timeout).
  final int statusCode;

  /// The server's machine code, or `network` | `timeout` | `bad_response`.
  final String code;

  final String message;

  /// The remaining fields of the error body (e.g. `jobId` on `job_active`).
  final Map<String, dynamic> extra;

  bool get isNetwork => code == 'network' || code == 'timeout';

  /// The token is missing, unknown or expired (never a wrong password).
  bool get isUnauthorized => code == 'unauthorized';

  @override
  String toString() => message;
}
