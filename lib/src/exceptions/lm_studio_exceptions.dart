import 'dart:async';
import 'dart:io';

import 'agents_core_exception.dart';

/// Exception thrown when an LM Studio HTTP request fails.
///
/// Contains the HTTP [statusCode] and the response [body] for diagnostics.
class LmStudioHttpException implements Exception {
  /// Creates an [LmStudioHttpException].
  const LmStudioHttpException({
    required this.statusCode,
    required this.body,
    required this.method,
    required this.path,
  });

  /// The HTTP status code returned by the server.
  final int statusCode;

  /// The raw response body.
  final String body;

  /// The HTTP method of the failed request (e.g. `GET`, `POST`).
  final String method;

  /// The request path that produced the error.
  final String path;

  @override
  String toString() =>
      'LmStudioHttpException: $method $path returned $statusCode: $body';
}

/// Exception thrown when the library cannot establish or maintain a connection
/// to an LM Studio server.
///
/// Wraps low-level transport errors ([SocketException], [HttpException],
/// [TimeoutException]) with actionable, human-readable messages that help
/// the developer diagnose the problem quickly.
///
/// Use the named factory constructors to create instances from specific
/// underlying exceptions:
///
/// ```dart
/// try {
///   await httpClient.post('/v1/chat/completions', body);
/// } on SocketException catch (e) {
///   throw LmStudioConnectionException.socketError(
///     uri: serverUri,
///     cause: e,
///   );
/// }
/// ```
class LmStudioConnectionException implements Exception {
  /// Creates an [LmStudioConnectionException] with an explicit [message].
  ///
  /// [uri] is the target endpoint that could not be reached.
  /// [cause] is the original exception that triggered this error.
  const LmStudioConnectionException({
    required this.message,
    required this.uri,
    this.cause,
  });

  /// Creates a connection exception from a [SocketException].
  ///
  /// Typically indicates the server is not running or the host/port is wrong.
  factory LmStudioConnectionException.socketError({
    required Uri uri,
    required SocketException cause,
  }) {
    return LmStudioConnectionException(
      message: 'Could not connect to $uri. Is LM Studio running?',
      uri: uri,
      cause: cause,
    );
  }

  /// Creates a connection exception from an [HttpException].
  ///
  /// Indicates a protocol-level problem during the HTTP exchange.
  factory LmStudioConnectionException.httpError({
    required Uri uri,
    required HttpException cause,
  }) {
    return LmStudioConnectionException(
      message: 'HTTP error while communicating with $uri: ${cause.message}',
      uri: uri,
      cause: cause,
    );
  }

  /// Creates a connection exception from a [TimeoutException].
  ///
  /// Indicates the server did not respond within the allowed duration.
  factory LmStudioConnectionException.timeout({
    required Uri uri,
    required TimeoutException cause,
  }) {
    final duration = cause.duration;
    final detail = duration != null ? ' after ${duration.inSeconds}s' : '';
    return LmStudioConnectionException(
      message:
          'Connection to $uri timed out$detail. '
          'Is LM Studio running and responsive?',
      uri: uri,
      cause: cause,
    );
  }

  /// Wraps an arbitrary transport-level exception as a connection error.
  ///
  /// Prefer the specific factories ([socketError], [httpError], [timeout])
  /// when the exception type is known. Use this for catch-all scenarios.
  factory LmStudioConnectionException.fromException({
    required Uri uri,
    required Object exception,
  }) {
    if (exception is SocketException) {
      return LmStudioConnectionException.socketError(
        uri: uri,
        cause: exception,
      );
    }
    if (exception is HttpException) {
      return LmStudioConnectionException.httpError(
        uri: uri,
        cause: exception,
      );
    }
    if (exception is TimeoutException) {
      return LmStudioConnectionException.timeout(
        uri: uri,
        cause: exception,
      );
    }
    return LmStudioConnectionException(
      message: 'Failed to communicate with $uri: $exception',
      uri: uri,
      cause: exception,
    );
  }

  /// A human-readable, actionable description of the connection failure.
  final String message;

  /// The target URI that could not be reached.
  final Uri uri;

  /// The underlying exception that caused this connection failure.
  ///
  /// May be a [SocketException], [HttpException], [TimeoutException],
  /// or any other transport-level error.
  final Object? cause;

  /// Whether this exception was caused by a [SocketException].
  bool get isSocketError => cause is SocketException;

  /// Whether this exception was caused by an [HttpException].
  bool get isHttpError => cause is HttpException;

  /// Whether this exception was caused by a [TimeoutException].
  bool get isTimeout => cause is TimeoutException;

  @override
  String toString() => 'LmStudioConnectionException: $message';
}

/// Exception thrown when the LM Studio API returns an error response.
///
/// Extends [AgentsCoreException] so callers can catch the entire library
/// hierarchy or narrow down to API-level errors specifically.
///
/// The [statusCode] reflects the HTTP response code, while [errorType] and
/// [errorMessage] carry the structured error payload from the server.
///
/// Convenience getters allow concise branching on common failure modes:
///
/// ```dart
/// try {
///   await client.chatCompletion(request);
/// } on LmStudioApiException catch (e) {
///   if (e.isModelNotFound) {
///     print('Model not available — choose another.');
///   } else if (e.isRateLimited) {
///     print('Slow down — retry after a pause.');
///   }
/// }
/// ```
class LmStudioApiException extends AgentsCoreException
    implements LmStudioHttpException {
  /// Creates an [LmStudioApiException].
  ///
  /// [statusCode] is the HTTP status code returned by the server.
  /// [errorType] categorises the error (e.g. `"not_found"`, `"invalid_request"`).
  /// [errorMessage] is a human-readable description passed to the superclass.
  ///
  /// [body], [method], and [path] are optional HTTP context fields inherited
  /// from [LmStudioHttpException]. They default to empty strings when the
  /// exception is constructed without HTTP request context.
  const LmStudioApiException({
    required this.statusCode,
    required this.errorType,
    required this.errorMessage,
    this.body = '',
    this.method = '',
    this.path = '',
  }) : super(errorMessage);

  /// The HTTP status code returned by the LM Studio API.
  @override
  final int statusCode;

  /// The error category as reported by the API (e.g. `"not_found"`).
  final String errorType;

  /// A human-readable description of the API error.
  final String errorMessage;

  /// The raw response body from the server.
  @override
  final String body;

  /// The HTTP method of the failed request (e.g. `GET`, `POST`).
  @override
  final String method;

  /// The request path that produced the error.
  @override
  final String path;

  /// Whether the requested model was not found (`404`).
  bool get isModelNotFound => statusCode == 404;

  /// Whether the request exceeded the model's context length (`400`).
  bool get isContextLengthExceeded => statusCode == 400;

  /// Whether the request was rate-limited (`429`).
  bool get isRateLimited => statusCode == 429;

  @override
  String toString() {
    final prefix = method.isNotEmpty ? '$method $path — ' : '';
    return 'LmStudioApiException: $prefix[$statusCode] $errorType — $errorMessage';
  }
}
