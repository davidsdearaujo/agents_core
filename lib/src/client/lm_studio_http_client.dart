import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../config/agents_core_config.dart';
import '../exceptions/lm_studio_exceptions.dart';

/// HTTP client for communicating with an LM Studio server.
///
/// Wraps [HttpClient] from `dart:io` and provides a typed, JSON-oriented
/// API for the three request patterns used by LM Studio:
///
/// - [get] -- fetch a JSON object
/// - [post] -- send a JSON body and receive a JSON object
/// - [postStream] -- send a JSON body and receive an SSE text stream
///
/// The client reads its base URL and timeout from [AgentsCoreConfig] and
/// logs request activity through the configured [Logger].
///
/// Supports automatic retry with exponential backoff for transient network
/// failures ([SocketException], [TimeoutException]). Any non-2xx HTTP response
/// throws [LmStudioApiException] immediately without retry.
/// Inject [httpSend] and [delay] for deterministic testing.
///
/// Always call [dispose] when the client is no longer needed to free
/// the underlying socket resources.
///
/// ```dart
/// final client = LmStudioHttpClient(config: config);
/// final models = await client.get('/v1/models');
/// client.dispose();
/// ```
///
/// Alternatively, construct with just a base URL string:
///
/// ```dart
/// final client = LmStudioHttpClient(baseUrl: 'http://localhost:1234');
/// ```
class LmStudioHttpClient {
  /// Creates an [LmStudioHttpClient].
  ///
  /// Accepts an optional [config] for full control, or a [baseUrl] string
  /// for convenience. When [baseUrl] is provided and [config] is omitted,
  /// a default [AgentsCoreConfig] is created using the parsed URL.
  ///
  /// [maxRetries] controls how many times a failed request is retried
  /// (default 3). Set to 0 to disable retries entirely.
  ///
  /// [httpSend] replaces the underlying HTTP transport for testing.
  /// When provided, [get] and [post] delegate to it instead of the
  /// real [HttpClient].
  ///
  /// [delay] replaces [Future.delayed] for testing backoff timing
  /// without real sleeps.
  ///
  /// The underlying [HttpClient] connection timeout is set to
  /// [AgentsCoreConfig.requestTimeout].
  LmStudioHttpClient({
    AgentsCoreConfig? config,
    String? baseUrl,
    int maxRetries = 3,
    Future<({int statusCode, String body})> Function(
      String method,
      Uri url, {
      String? body,
    })?
    httpSend,
    Future<void> Function(Duration)? delay,
  }) : _config =
           config ??
           AgentsCoreConfig(
             lmStudioBaseUrl: baseUrl != null ? Uri.parse(baseUrl) : null,
           ),
       _maxRetries = maxRetries,
       _httpSend = httpSend,
       _delayFn = delay ?? Future.delayed,
       _client = HttpClient() {
    _client.connectionTimeout = _config.requestTimeout;
  }

  final AgentsCoreConfig _config;
  final HttpClient _client;
  final int _maxRetries;
  final Future<({int statusCode, String body})> Function(
    String method,
    Uri url, {
    String? body,
  })?
  _httpSend;
  final Future<void> Function(Duration) _delayFn;

  /// Sends an HTTP GET request to [path] and returns the decoded JSON body.
  ///
  /// The [path] is resolved relative to the configured
  /// [AgentsCoreConfig.lmStudioBaseUrl].
  ///
  /// Retries on transient network errors ([SocketException],
  /// [TimeoutException]) up to [maxRetries] times with exponential backoff.
  ///
  /// Throws [LmStudioApiException] immediately for any non-2xx HTTP response.
  /// Throws [LmStudioConnectionException] if a network error persists after
  /// all retries.
  Future<Map<String, dynamic>> get(String path) =>
      _executeWithRetry('GET', path);

  /// Sends an HTTP POST request to [path] with a JSON [body] and returns
  /// the decoded JSON response.
  ///
  /// The [path] is resolved relative to the configured
  /// [AgentsCoreConfig.lmStudioBaseUrl].
  ///
  /// Retries on transient network errors ([SocketException],
  /// [TimeoutException]) up to [maxRetries] times with exponential backoff.
  ///
  /// Throws [LmStudioApiException] immediately for any non-2xx HTTP response.
  /// Throws [LmStudioConnectionException] if a network error persists after
  /// all retries.
  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body) =>
      _executeWithRetry('POST', path, requestBody: body);

  /// Sends an HTTP POST request to [path] with a JSON [body] and returns
  /// a [Stream] of SSE data strings.
  ///
  /// Each element in the returned stream is the raw `data:` payload from
  /// one Server-Sent Event line. The stream completes when the server
  /// sends `[DONE]` or closes the connection.
  ///
  /// The [path] is resolved relative to the configured
  /// [AgentsCoreConfig.lmStudioBaseUrl].
  ///
  /// Throws [LmStudioConnectionException] if the server cannot be reached
  /// (wraps [SocketException], [HttpException], [TimeoutException]).
  ///
  /// Throws [LmStudioApiException] if the initial response status is
  /// not 2xx.
  Stream<String> postStream(String path, Map<String, dynamic> body) async* {
    final uri = _resolve(path);
    _config.logger.debug('POST (stream) $uri');

    HttpClientResponse response;

    try {
      final request = await _client.postUrl(uri);
      request.headers.set(
        HttpHeaders.contentTypeHeader,
        ContentType.json.value,
      );
      request.headers.set(HttpHeaders.acceptHeader, 'text/event-stream');
      final key = _config.apiKey;
      if (key != null) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $key');
      }
      request.add(utf8.encode(json.encode(body)));

      response = await request.close();
    } on SocketException catch (e) {
      throw LmStudioConnectionException.socketError(uri: uri, cause: e);
    } on HttpException catch (e) {
      throw LmStudioConnectionException.httpError(uri: uri, cause: e);
    } on TimeoutException catch (e) {
      throw LmStudioConnectionException.timeout(uri: uri, cause: e);
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final errorBody = await response.transform(utf8.decoder).join();
      throw _parseApiException(response.statusCode, errorBody, 'POST', path);
    }

    yield* response
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .where((line) => line.startsWith('data: '))
        .map((line) => line.substring(6))
        .takeWhile((data) => data != '[DONE]');
  }

  /// Closes the underlying [HttpClient] and frees its resources.
  ///
  /// After calling [dispose], no further requests can be made with
  /// this instance.
  void dispose() {
    _config.logger.debug('Disposing LmStudioHttpClient');
    _client.close();
  }

  // ── Private helpers ──────────────────────────────────────────────────────

  /// Executes an HTTP request with automatic retry and exponential backoff.
  ///
  /// Only network-level errors ([SocketException], [TimeoutException]) are
  /// retried. Any non-2xx HTTP response throws [LmStudioApiException]
  /// immediately without retry.
  ///
  /// When retries are exhausted, the last network error is wrapped in
  /// [LmStudioConnectionException] for actionable diagnostics.
  ///
  /// Exponential backoff starts at 1 second and doubles per retry:
  /// 1 s → 2 s → 4 s → 8 s → …
  Future<Map<String, dynamic>> _executeWithRetry(
    String method,
    String path, {
    Map<String, dynamic>? requestBody,
  }) async {
    final uri = _resolve(path);
    _config.logger.debug('$method $uri');

    final encodedBody = requestBody != null ? json.encode(requestBody) : null;

    Object? lastError;

    for (var attempt = 0; attempt <= _maxRetries; attempt++) {
      try {
        final response = await _sendRequest(method, uri, body: encodedBody);

        if (response.statusCode >= 200 && response.statusCode < 300) {
          return _decodeJsonBody(response.body);
        }

        // Non-2xx — fail immediately with parsed API exception.
        throw _parseApiException(
          response.statusCode,
          response.body,
          method,
          path,
        );
      } on LmStudioApiException {
        rethrow;
      } on SocketException catch (e) {
        lastError = e;
      } on TimeoutException catch (e) {
        lastError = e;
      }

      // Network error — delay and retry if attempts remain.
      if (attempt < _maxRetries) {
        final retryNum = attempt + 1;
        _config.logger.warn(
          'Retrying request $method $path '
          '(attempt $retryNum of $_maxRetries)',
        );
        await _delayFn(Duration(seconds: 1 << attempt));
      }
    }

    // All retries exhausted — wrap in LmStudioConnectionException.
    _config.logger.error(
      'All retries exhausted for $method $path '
      'after $_maxRetries attempts',
    );

    throw LmStudioConnectionException.fromException(
      uri: uri,
      exception: lastError!,
    );
  }

  /// Sends a single HTTP request, delegating to the injected [_httpSend]
  /// or falling back to the real [HttpClient].
  ///
  /// Transport-level exceptions propagate unchanged so that
  /// [_executeWithRetry] can catch and retry them.
  Future<({int statusCode, String body})> _sendRequest(
    String method,
    Uri uri, {
    String? body,
  }) async {
    if (_httpSend != null) {
      return _httpSend(method, uri, body: body);
    }

    final HttpClientRequest request;
    if (method == 'GET') {
      request = await _client.getUrl(uri);
    } else {
      request = await _client.postUrl(uri);
    }

    _setJsonHeaders(request);
    if (body != null) request.add(utf8.encode(body));

    final response = await request.close();
    final responseBody = await response.transform(utf8.decoder).join();

    return (statusCode: response.statusCode, body: responseBody);
  }

  /// Resolves a [path] against the configured base URL.
  Uri _resolve(String path) => _config.lmStudioBaseUrl.resolve(path);

  /// Sets standard JSON request headers on [request].
  ///
  /// When [AgentsCoreConfig.apiKey] is non-null, an `Authorization: Bearer`
  /// header is added for LM Studio server authentication.
  void _setJsonHeaders(HttpClientRequest request) {
    request.headers.set(HttpHeaders.contentTypeHeader, ContentType.json.value);
    request.headers.set(HttpHeaders.acceptHeader, ContentType.json.value);
    final key = _config.apiKey;
    if (key != null) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $key');
    }
  }

  /// Decodes a JSON response [body], returning an empty map when the body
  /// is blank (e.g. HTTP 204 No Content).
  static Map<String, dynamic> _decodeJsonBody(String body) {
    if (body.trim().isEmpty) return <String, dynamic>{};
    return json.decode(body) as Map<String, dynamic>;
  }

  /// Parses a non-2xx response body into an [LmStudioApiException].
  ///
  /// Attempts to decode [body] as `{"error": {"type": "...", "message": "..."}}`.
  /// Returns empty strings for [errorType] and [errorMessage] when the JSON is
  /// malformed or the expected fields are absent.
  ///
  /// [method] and [path] provide HTTP request context for the exception.
  static LmStudioApiException _parseApiException(
    int statusCode,
    String body, [
    String method = '',
    String path = '',
  ]) {
    var errorType = '';
    var errorMessage = '';

    try {
      final decoded = json.decode(body);
      if (decoded is Map<String, dynamic>) {
        final error = decoded['error'];
        if (error is Map<String, dynamic>) {
          errorType = (error['type'] as String?) ?? '';
          errorMessage = (error['message'] as String?) ?? '';
        }
      }
    } on FormatException {
      // Malformed JSON — fall through with empty strings.
    }

    return LmStudioApiException(
      statusCode: statusCode,
      errorType: errorType,
      errorMessage: errorMessage,
      body: body,
      method: method,
      path: path,
    );
  }
}
