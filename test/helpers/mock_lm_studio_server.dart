import 'dart:async';
import 'dart:convert';
import 'dart:io';

// ─────────────────────────────────────────────────────────────────────────────
// Public response types
// ─────────────────────────────────────────────────────────────────────────────

/// A pre-canned response stub for [MockLmStudioServer].
///
/// Use the named constructors to build a JSON, SSE-streaming, or error
/// response:
///
/// ```dart
/// // Successful JSON response (200)
/// MockResponse.json(body: {'id': 'cmpl-1', 'choices': []})
///
/// // SSE streaming response
/// MockResponse.sse(chunks: [{'delta': 'Hello'}, {'delta': ' world'}])
///
/// // Error response (non-2xx)
/// MockResponse.error(
///   statusCode: 429,
///   body: {'error': {'type': 'rate_limited', 'message': 'too many requests'}},
/// )
/// ```
class MockResponse {
  const MockResponse._({
    required this.statusCode,
    this.jsonBody,
    this.sseChunks,
  });

  /// Creates a successful JSON response.
  ///
  /// [statusCode] defaults to 200.
  /// [body] is JSON-encoded and returned as the response body.
  factory MockResponse.json({
    int statusCode = 200,
    required Map<String, dynamic> body,
  }) =>
      MockResponse._(statusCode: statusCode, jsonBody: body);

  /// Creates an SSE (Server-Sent Events) streaming response.
  ///
  /// Each map in [chunks] is JSON-encoded and emitted as a `data: <json>`
  /// event line. A terminal `data: [DONE]` event is appended automatically.
  ///
  /// The response status is always 200 for SSE.
  factory MockResponse.sse({
    required List<Map<String, dynamic>> chunks,
  }) =>
      MockResponse._(statusCode: HttpStatus.ok, sseChunks: chunks);

  /// Creates an error (non-2xx) JSON response.
  factory MockResponse.error({
    required int statusCode,
    required Map<String, dynamic> body,
  }) =>
      MockResponse._(statusCode: statusCode, jsonBody: body);

  /// The HTTP status code to return.
  final int statusCode;

  /// The JSON body to return (for JSON and error responses).
  final Map<String, dynamic>? jsonBody;

  /// SSE data chunks to stream (for SSE responses).
  final List<Map<String, dynamic>>? sseChunks;

  /// Whether this is an SSE streaming response.
  bool get isSse => sseChunks != null;
}

// ─────────────────────────────────────────────────────────────────────────────
// RecordedRequest
// ─────────────────────────────────────────────────────────────────────────────

/// An HTTP request that was received by [MockLmStudioServer].
///
/// Every field is snapshotted eagerly so assertions can be made after the
/// server has closed.
class RecordedRequest {
  const RecordedRequest({
    required this.method,
    required this.path,
    required this.body,
    required this.headers,
  });

  /// The HTTP method (e.g. `GET`, `POST`).
  final String method;

  /// The request path (e.g. `/v1/chat/completions`).
  final String path;

  /// The raw UTF-8 decoded request body.
  ///
  /// Empty string `''` for requests that sent no body.
  final String body;

  /// A snapshot of the request headers.
  ///
  /// Keys are lower-cased header names; values are lists of header values
  /// (a header may appear multiple times per HTTP spec).
  final Map<String, List<String>> headers;

  /// Decodes [body] as JSON.
  ///
  /// Throws [FormatException] if [body] is not valid JSON.
  Map<String, dynamic> get jsonBody =>
      json.decode(body) as Map<String, dynamic>;

  @override
  String toString() => 'RecordedRequest($method $path)';
}

// ─────────────────────────────────────────────────────────────────────────────
// Internal stub record
// ─────────────────────────────────────────────────────────────────────────────

class _Stub {
  _Stub({this.method, this.path, required this.response});

  /// If non-null, only matches requests with this HTTP method.
  final String? method;

  /// If non-null, only matches requests at this exact path.
  final String? path;

  /// The response to emit when matched.
  final MockResponse response;

  bool matches(String requestMethod, String requestPath) =>
      (method == null || method == requestMethod) &&
      (path == null || path == requestPath);
}

// ─────────────────────────────────────────────────────────────────────────────
// MockLmStudioServer
// ─────────────────────────────────────────────────────────────────────────────

/// A lightweight fake LM Studio HTTP server for integration and unit tests.
///
/// Binds to a random port on the loopback interface, accepts a FIFO queue of
/// stub responses, and records every incoming request so tests can make
/// detailed assertions.
///
/// ## Lifecycle
///
/// ```dart
/// late MockLmStudioServer server;
///
/// setUp(() async => server = await MockLmStudioServer.start());
/// tearDown(() => server.close());
/// ```
///
/// ## Stub registration
///
/// Call [enqueue] before the request you want to intercept:
///
/// ```dart
/// server.enqueue(
///   method: 'POST',
///   path: '/v1/chat/completions',
///   response: MockResponse.json(body: {'id': 'cmpl-1', 'choices': []}),
/// );
/// ```
///
/// Stubs are matched and consumed in FIFO order. Set [method] or [path] to
/// `null` to match any method or any path respectively.
///
/// ## Request assertions
///
/// ```dart
/// expect(server.requests, hasLength(1));
/// expect(server.requests.first.method, equals('POST'));
/// expect(server.requests.first.path, equals('/v1/chat/completions'));
/// expect(server.requests.first.jsonBody['model'], equals('llama3'));
/// ```
///
/// ## SSE (streaming) responses
///
/// Use [MockResponse.sse] to return Server-Sent Events. The server sends
/// each chunk as `data: <json>` followed by a blank line, then appends the
/// `data: [DONE]` sentinel that [LmStudioHttpClient.postStream] recognises.
///
/// ```dart
/// server.enqueue(
///   response: MockResponse.sse(chunks: [
///     {'choices': [{'delta': {'content': 'Hello'}}]},
///     {'choices': [{'delta': {'content': ' world'}}]},
///   ]),
/// );
/// ```
class MockLmStudioServer {
  MockLmStudioServer._(this._server) {
    _server.listen(_handleRequest);
  }

  final HttpServer _server;
  final List<_Stub> _stubs = [];
  final List<RecordedRequest> _requests = [];

  // ── Public API ─────────────────────────────────────────────────────────────

  /// The TCP port the server is listening on.
  int get port => _server.port;

  /// The base URL for this server — `http://127.0.0.1:<port>`.
  String get baseUrl => 'http://127.0.0.1:$port';

  /// Every request received by this server, in arrival order.
  ///
  /// Returns an unmodifiable view. Call [clearRequests] to reset.
  List<RecordedRequest> get requests => List.unmodifiable(_requests);

  /// The number of stubs that have been enqueued but not yet consumed.
  int get pendingStubCount => _stubs.length;

  /// Starts a [MockLmStudioServer] bound to a random available loopback port.
  ///
  /// Calling code is responsible for invoking [close] when the server is no
  /// longer needed (typically in a `tearDown` block).
  static Future<MockLmStudioServer> start() async {
    final server =
        await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    return MockLmStudioServer._(server);
  }

  /// Enqueues a stub response to be returned for the next matching request.
  ///
  /// [method] filters by HTTP method (`GET`, `POST`, …); `null` matches any.
  /// [path] filters by request path; `null` matches any.
  /// [response] is the [MockResponse] to return when the stub is triggered.
  ///
  /// Stubs are matched in FIFO order — the first enqueued stub whose
  /// [method] and [path] match the incoming request is consumed.
  void enqueue({
    String? method,
    String? path,
    required MockResponse response,
  }) {
    _stubs.add(_Stub(method: method, path: path, response: response));
  }

  /// Removes all recorded requests.
  void clearRequests() => _requests.clear();

  /// Closes the underlying [HttpServer] and frees the socket.
  ///
  /// After this call the server stops accepting new connections. Any
  /// in-flight requests may be aborted.
  Future<void> close() => _server.close(force: true);

  // ── Internal request handling ───────────────────────────────────────────────

  Future<void> _handleRequest(HttpRequest request) async {
    // Eagerly drain and decode the request body.
    final bodyBytes = await request.fold<List<int>>(
      <int>[],
      (acc, chunk) => acc..addAll(chunk),
    );
    final body = utf8.decode(bodyBytes);

    // Snapshot headers into a plain Map so RecordedRequest is fully immutable.
    final headers = <String, List<String>>{};
    request.headers.forEach((name, values) => headers[name] = List.of(values));

    _requests.add(RecordedRequest(
      method: request.method,
      path: request.uri.path,
      body: body,
      headers: headers,
    ));

    // Find the first matching stub (FIFO).
    final stubIndex = _stubs
        .indexWhere((s) => s.matches(request.method, request.uri.path));

    if (stubIndex == -1) {
      // No matching stub — fail fast with a descriptive 500 so tests break
      // immediately with a clear signal rather than a confusing connection
      // error or hanging future.
      request.response
        ..statusCode = HttpStatus.internalServerError
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({
          'error':
              'MockLmStudioServer: no stub registered for '
              '${request.method} ${request.uri.path}',
        }));
      await request.response.close();
      return;
    }

    final stub = _stubs.removeAt(stubIndex);
    await _writeResponse(request.response, stub.response);
  }

  Future<void> _writeResponse(HttpResponse res, MockResponse mock) async {
    if (mock.isSse) {
      res
        ..statusCode = HttpStatus.ok
        ..headers.set(HttpHeaders.contentTypeHeader, 'text/event-stream')
        ..headers.set(HttpHeaders.cacheControlHeader, 'no-cache')
        ..headers.set(HttpHeaders.connectionHeader, 'keep-alive');

      for (final chunk in mock.sseChunks!) {
        res.add(utf8.encode('data: ${jsonEncode(chunk)}\n\n'));
      }
      // SSE sentinel recognised by LmStudioHttpClient.postStream
      res.add(utf8.encode('data: [DONE]\n\n'));
    } else {
      res
        ..statusCode = mock.statusCode
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(mock.jsonBody!));
    }
    await res.close();
  }
}
