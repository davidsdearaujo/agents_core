import 'dart:io' show Platform;

import 'logger.dart';

/// Top-level configuration for the agents_core library.
///
/// Use this class to customise cross-cutting concerns such as logging,
/// LM Studio connectivity, request timeouts, Docker images, workspace
/// paths, and API authentication. Every configurable default is intentionally
/// conservative so that creating a bare [AgentsCoreConfig] is safe for
/// production use.
///
/// ```dart
/// final config = AgentsCoreConfig(
///   lmStudioBaseUrl: Uri.parse('http://localhost:1234'),
///   defaultModel: 'my-model',
///   apiKey: 'lm-studio-api-key',
///   logger: StderrLogger(level: LogLevel.debug),
/// );
/// ```
class AgentsCoreConfig {
  /// Creates an [AgentsCoreConfig].
  ///
  /// [lmStudioBaseUrl] defaults to `http://localhost:1234`, the standard
  /// LM Studio local server address.
  ///
  /// [defaultModel] defaults to `'lmstudio-community/default'`.
  ///
  /// [requestTimeout] defaults to 60 seconds. This value is used as the
  /// HTTP connection timeout for outgoing requests.
  ///
  /// [dockerImage] defaults to `'python:3.12-slim'`.
  ///
  /// [workspacePath] defaults to `'/tmp/agents_workspace'`.
  ///
  /// [apiKey] is an optional API key used to authenticate requests to the
  /// LM Studio server. When provided, it is sent as a `Bearer` token in the
  /// `Authorization` header of outgoing HTTP requests. Defaults to `null`
  /// (no authentication). Can also be set via the `AGENTS_API_KEY`
  /// environment variable when using [AgentsCoreConfig.fromEnvironment].
  ///
  /// [logger] defaults to a [StderrLogger] at [LogLevel.info], which writes
  /// timestamped messages to stderr. Pass a [SilentLogger] to suppress output.
  AgentsCoreConfig({
    Uri? lmStudioBaseUrl,
    this.defaultModel = 'lmstudio-community/default',
    this.requestTimeout = const Duration(seconds: 60),
    this.dockerImage = 'python:3.12-slim',
    this.workspacePath = '/tmp/agents_workspace',
    this.apiKey,
    Logger? logger,
  })  : lmStudioBaseUrl =
            lmStudioBaseUrl ?? Uri.parse('http://localhost:1234'),
        logger = logger ?? const StderrLogger();

  /// Creates an [AgentsCoreConfig] from environment variables.
  ///
  /// When [environment] is provided, values are read from that map.
  /// When omitted, values are read from [Platform.environment].
  ///
  /// Env var mappings:
  /// - `LM_STUDIO_BASE_URL` → [lmStudioBaseUrl] (parsed as [Uri])
  /// - `AGENTS_DEFAULT_MODEL` → [defaultModel]
  /// - `AGENTS_DOCKER_IMAGE` → [dockerImage]
  /// - `AGENTS_WORKSPACE_PATH` → [workspacePath]
  /// - `AGENTS_REQUEST_TIMEOUT_SECONDS` → [requestTimeout] (parsed as int)
  /// - `AGENTS_API_KEY` → [apiKey]
  ///
  /// Invalid or missing values fall back to constructor defaults.
  factory AgentsCoreConfig.fromEnvironment({
    Map<String, String>? environment,
    Logger? logger,
  }) {
    final env = environment ?? Platform.environment;

    // Parse LM_STUDIO_BASE_URL — use default if absent or invalid.
    Uri? lmStudioBaseUrl;
    final baseUrlStr = env['LM_STUDIO_BASE_URL'];
    if (baseUrlStr != null && baseUrlStr.isNotEmpty) {
      try {
        lmStudioBaseUrl = Uri.parse(baseUrlStr);
      } on FormatException {
        // Invalid URI — fall through to default.
      }
    }

    // Parse AGENTS_REQUEST_TIMEOUT_SECONDS — use default if absent or invalid.
    Duration? requestTimeout;
    final timeoutStr = env['AGENTS_REQUEST_TIMEOUT_SECONDS'];
    if (timeoutStr != null && timeoutStr.isNotEmpty) {
      final seconds = int.tryParse(timeoutStr);
      if (seconds != null && seconds >= 0) {
        requestTimeout = Duration(seconds: seconds);
      }
    }

    return AgentsCoreConfig(
      lmStudioBaseUrl: lmStudioBaseUrl,
      defaultModel:
          env['AGENTS_DEFAULT_MODEL'] ?? 'lmstudio-community/default',
      requestTimeout: requestTimeout ?? const Duration(seconds: 60),
      dockerImage: env['AGENTS_DOCKER_IMAGE'] ?? 'python:3.12-slim',
      workspacePath: env['AGENTS_WORKSPACE_PATH'] ?? '/tmp/agents_workspace',
      apiKey: env['AGENTS_API_KEY'],
      logger: logger,
    );
  }

  /// The base URL of the LM Studio server.
  ///
  /// All HTTP client requests are resolved relative to this URI.
  /// Defaults to `http://localhost:1234`.
  final Uri lmStudioBaseUrl;

  /// The default model identifier used for LM Studio requests.
  ///
  /// Defaults to `'lmstudio-community/default'`.
  final String defaultModel;

  /// The timeout applied to HTTP connections.
  ///
  /// Defaults to 60 seconds.
  final Duration requestTimeout;

  /// The Docker image used for sandboxed code execution.
  ///
  /// Defaults to `'python:3.12-slim'`.
  final String dockerImage;

  /// The workspace path for agent file operations.
  ///
  /// Defaults to `'/tmp/agents_workspace'`.
  final String workspacePath;

  /// Optional API key for authenticating requests to the LM Studio server.
  ///
  /// When non-null, the key is sent as a `Bearer` token in the
  /// `Authorization` header of every outgoing HTTP request. This is useful
  /// when the LM Studio server is deployed behind an API gateway or
  /// reverse proxy that requires authentication.
  ///
  /// Defaults to `null` (no authentication). Can also be populated
  /// automatically via the `AGENTS_API_KEY` environment variable when
  /// using [AgentsCoreConfig.fromEnvironment].
  final String? apiKey;

  /// The logger used across the library for diagnostic output.
  final Logger logger;

  /// Returns a new [AgentsCoreConfig] with the specified fields replaced.
  ///
  /// Fields that are not provided retain their original values.
  AgentsCoreConfig copyWith({
    Uri? lmStudioBaseUrl,
    String? defaultModel,
    Duration? requestTimeout,
    String? dockerImage,
    String? workspacePath,
    String? apiKey,
    bool clearApiKey = false,
    Logger? logger,
  }) {
    return AgentsCoreConfig(
      lmStudioBaseUrl: lmStudioBaseUrl ?? this.lmStudioBaseUrl,
      defaultModel: defaultModel ?? this.defaultModel,
      requestTimeout: requestTimeout ?? this.requestTimeout,
      dockerImage: dockerImage ?? this.dockerImage,
      workspacePath: workspacePath ?? this.workspacePath,
      apiKey: clearApiKey ? null : (apiKey ?? this.apiKey),
      logger: logger ?? this.logger,
    );
  }

  /// Two [AgentsCoreConfig] instances are equal when all six value fields
  /// match. The [logger] is excluded from equality comparisons because
  /// loggers are stateful singletons, not value objects.
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AgentsCoreConfig &&
        other.lmStudioBaseUrl == lmStudioBaseUrl &&
        other.defaultModel == defaultModel &&
        other.requestTimeout == requestTimeout &&
        other.dockerImage == dockerImage &&
        other.workspacePath == workspacePath &&
        other.apiKey == apiKey;
  }

  @override
  int get hashCode => Object.hash(
        lmStudioBaseUrl,
        defaultModel,
        requestTimeout,
        dockerImage,
        workspacePath,
        apiKey,
      );

  @override
  String toString() =>
      'AgentsCoreConfig('
      'lmStudioBaseUrl: $lmStudioBaseUrl, '
      'defaultModel: $defaultModel, '
      'requestTimeout: $requestTimeout, '
      'dockerImage: $dockerImage, '
      'workspacePath: $workspacePath, '
      'apiKey: ${apiKey != null ? '***' : 'null'}'
      ')';
}
