/// Configuration for the LM Studio HTTP client.
///
/// Encapsulates all LM Studio–specific connectivity settings: server URL,
/// request timeout, authentication, and the default model to use when
/// no explicit model is supplied by a request.
///
/// ```dart
/// final lmConfig = LmStudioConfig(
///   baseUrl: Uri.parse('http://192.168.1.10:1234'),
///   defaultModel: 'llama-3-8b',
///   requestTimeout: Duration(seconds: 120),
///   apiKey: 'my-api-key',
/// );
/// ```
///
/// Use [copyWith] to derive a modified configuration without mutating the
/// original:
///
/// ```dart
/// final debugConfig = lmConfig.copyWith(
///   baseUrl: Uri.parse('http://localhost:1234'),
/// );
/// ```
class LmStudioConfig {
  /// Creates an [LmStudioConfig].
  ///
  /// [baseUrl] is the base URL of the LM Studio server.
  /// Defaults to `http://localhost:1234`, the standard local address.
  ///
  /// [defaultModel] is the model identifier used when a request does not
  /// specify one explicitly.
  /// Defaults to `'lmstudio-community/default'`.
  ///
  /// [requestTimeout] is the HTTP connection timeout applied to every
  /// outgoing request.
  /// Defaults to 60 seconds.
  ///
  /// [apiKey] is an optional Bearer token sent in the `Authorization` header
  /// of every request. When `null`, no authentication header is added.
  LmStudioConfig({
    Uri? baseUrl,
    this.defaultModel = 'lmstudio-community/default',
    this.requestTimeout = const Duration(seconds: 60),
    this.apiKey,
  }) : baseUrl = baseUrl ?? Uri.parse('http://localhost:1234');

  /// The base URL of the LM Studio server.
  ///
  /// All HTTP requests are resolved relative to this URI.
  /// Defaults to `http://localhost:1234`.
  final Uri baseUrl;

  /// The default model identifier used when none is specified in a request.
  ///
  /// Defaults to `'lmstudio-community/default'`.
  final String defaultModel;

  /// The HTTP connection timeout applied to outgoing requests.
  ///
  /// Defaults to 60 seconds.
  final Duration requestTimeout;

  /// Optional API key for authenticating with the LM Studio server.
  ///
  /// When non-null, sent as a `Bearer` token in the `Authorization` header
  /// of every outgoing HTTP request. Defaults to `null` (no authentication).
  final String? apiKey;

  /// Returns a copy of this configuration with the specified fields replaced.
  ///
  /// Unspecified fields retain their current values.
  ///
  /// Use [clearApiKey] to explicitly set [apiKey] to `null`:
  ///
  /// ```dart
  /// final noAuth = config.copyWith(clearApiKey: true);
  /// ```
  LmStudioConfig copyWith({
    Uri? baseUrl,
    String? defaultModel,
    Duration? requestTimeout,
    String? apiKey,
    bool clearApiKey = false,
  }) {
    return LmStudioConfig(
      baseUrl: baseUrl ?? this.baseUrl,
      defaultModel: defaultModel ?? this.defaultModel,
      requestTimeout: requestTimeout ?? this.requestTimeout,
      apiKey: clearApiKey ? null : (apiKey ?? this.apiKey),
    );
  }

  /// Two [LmStudioConfig] instances are equal when all value fields match:
  /// [baseUrl], [defaultModel], [requestTimeout], and [apiKey].
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LmStudioConfig &&
        other.baseUrl == baseUrl &&
        other.defaultModel == defaultModel &&
        other.requestTimeout == requestTimeout &&
        other.apiKey == apiKey;
  }

  @override
  int get hashCode =>
      Object.hash(baseUrl, defaultModel, requestTimeout, apiKey);

  /// Returns a human-readable representation of this configuration.
  ///
  /// The [apiKey] value is masked as `***` when present to avoid
  /// accidentally leaking credentials in logs or stack traces.
  @override
  String toString() =>
      'LmStudioConfig('
      'baseUrl: $baseUrl, '
      'defaultModel: $defaultModel, '
      'requestTimeout: $requestTimeout, '
      'apiKey: ${apiKey != null ? '***' : 'null'}'
      ')';
}
