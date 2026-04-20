import 'dart:io' show Platform;

import 'docker_config.dart';
import 'logger.dart';
import 'lm_studio_config.dart';
import 'logging_config.dart';

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
///
/// To globally disable all logging:
///
/// ```dart
/// final config = AgentsCoreConfig(loggingEnabled: false);
/// ```
///
/// Logging can also be disabled via the `AGENTS_LOGGING_ENABLED`
/// environment variable (set to `"false"` or `"0"`) when using
/// [AgentsCoreConfig.fromEnvironment].
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
  /// [loggingEnabled] controls whether logging is globally active. When
  /// `false`, the [logger] getter returns a [SilentLogger] regardless of
  /// the configured logger instance. Defaults to `true` (logging active).
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
    this.loggingEnabled = true,
    Logger? logger,
  }) : lmStudioBaseUrl = lmStudioBaseUrl ?? Uri.parse('http://localhost:1234'),
       _logger = logger ?? const StderrLogger();

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
  /// - `AGENTS_LOGGING_ENABLED` → [loggingEnabled] (`"false"` or `"0"` to
  ///   disable; any other value or absent → enabled)
  ///
  /// Invalid or missing values fall back to constructor defaults.
  factory AgentsCoreConfig.fromEnvironment({
    Map<String, String>? environment,
    bool? loggingEnabled,
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

    // Parse AGENTS_LOGGING_ENABLED — explicit parameter wins over env var.
    final resolvedLoggingEnabled = loggingEnabled ?? _parseLoggingEnabled(env);

    return AgentsCoreConfig(
      lmStudioBaseUrl: lmStudioBaseUrl,
      defaultModel: env['AGENTS_DEFAULT_MODEL'] ?? 'lmstudio-community/default',
      requestTimeout: requestTimeout ?? const Duration(seconds: 60),
      dockerImage: env['AGENTS_DOCKER_IMAGE'] ?? 'python:3.12-slim',
      workspacePath: env['AGENTS_WORKSPACE_PATH'] ?? '/tmp/agents_workspace',
      apiKey: env['AGENTS_API_KEY'],
      loggingEnabled: resolvedLoggingEnabled,
      logger: logger,
    );
  }

  /// Creates an [AgentsCoreConfig] from three focused sub-configs.
  ///
  /// This is the preferred constructor when building configuration from
  /// specialised objects injected independently.
  ///
  /// All flat top-level fields ([lmStudioBaseUrl], [defaultModel],
  /// [requestTimeout], [dockerImage], [workspacePath], [apiKey],
  /// [loggingEnabled], and the internal logger) are populated from
  /// the sub-config values, so all existing accessors continue to work.
  ///
  /// ```dart
  /// final config = AgentsCoreConfig.fromConfigs(
  ///   lmStudio: LmStudioConfig(baseUrl: Uri.parse('http://localhost:1234')),
  ///   docker: DockerConfig(),
  ///   logging: LoggingConfig(loggingEnabled: false),
  /// );
  /// ```
  factory AgentsCoreConfig.fromConfigs({
    required LmStudioConfig lmStudio,
    required DockerConfig docker,
    required LoggingConfig logging,
  }) {
    return AgentsCoreConfig(
      lmStudioBaseUrl: lmStudio.baseUrl,
      defaultModel: lmStudio.defaultModel,
      requestTimeout: lmStudio.requestTimeout,
      apiKey: lmStudio.apiKey,
      dockerImage: docker.image,
      workspacePath: docker.workspacePath,
      loggingEnabled: logging.loggingEnabled,
      logger: logging.logger,
    );
  }

  /// Parses `AGENTS_LOGGING_ENABLED` from [env].
  ///
  /// Returns `false` when the value is `"false"` or `"0"` (case-insensitive).
  /// Returns `true` for any other value or when the key is absent.
  static bool _parseLoggingEnabled(Map<String, String> env) {
    final value = env['AGENTS_LOGGING_ENABLED'];
    if (value == null) return true;
    final lower = value.trim().toLowerCase();
    return lower != 'false' && lower != '0';
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

  /// Whether logging is globally enabled.
  ///
  /// When `false`, the [logger] getter returns a [SilentLogger] regardless
  /// of the configured logger instance. This provides a single switch to
  /// suppress all library-wide diagnostic output without replacing the
  /// logger itself.
  ///
  /// Defaults to `true` (logging active). Can also be controlled via the
  /// `AGENTS_LOGGING_ENABLED` environment variable (set to `"false"` or
  /// `"0"` to disable) when using [AgentsCoreConfig.fromEnvironment].
  final bool loggingEnabled;

  /// The configured logger instance (before the [loggingEnabled] gate).
  final Logger _logger;

  /// The logger used across the library for diagnostic output.
  ///
  /// When [loggingEnabled] is `false`, a [SilentLogger] is returned
  /// regardless of the configured logger instance. This allows callers
  /// to use `config.logger` unconditionally — the global toggle is
  /// applied transparently.
  Logger get logger => loggingEnabled ? _logger : const SilentLogger();

  /// Returns an [LmStudioConfig] built from this configuration's LM Studio
  /// fields.
  ///
  /// The returned sub-config reflects the current values of [lmStudioBaseUrl],
  /// [defaultModel], [requestTimeout], and [apiKey]. It can be passed
  /// directly to components that accept [LmStudioConfig].
  LmStudioConfig get lmStudio => LmStudioConfig(
    baseUrl: lmStudioBaseUrl,
    defaultModel: defaultModel,
    requestTimeout: requestTimeout,
    apiKey: apiKey,
  );

  /// Returns a [DockerConfig] built from this configuration's Docker fields.
  ///
  /// The returned sub-config reflects the current values of [dockerImage]
  /// and [workspacePath]. It can be passed directly to components that
  /// accept [DockerConfig].
  DockerConfig get docker =>
      DockerConfig(image: dockerImage, workspacePath: workspacePath);

  /// Returns a [LoggingConfig] built from this configuration's logging fields.
  ///
  /// The returned sub-config reflects the current values of [loggingEnabled]
  /// and the internal logger instance. It can be passed directly to
  /// components that accept [LoggingConfig].
  LoggingConfig get logging =>
      LoggingConfig(logger: _logger, loggingEnabled: loggingEnabled);

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
    bool? loggingEnabled,
    Logger? logger,
  }) {
    return AgentsCoreConfig(
      lmStudioBaseUrl: lmStudioBaseUrl ?? this.lmStudioBaseUrl,
      defaultModel: defaultModel ?? this.defaultModel,
      requestTimeout: requestTimeout ?? this.requestTimeout,
      dockerImage: dockerImage ?? this.dockerImage,
      workspacePath: workspacePath ?? this.workspacePath,
      apiKey: clearApiKey ? null : (apiKey ?? this.apiKey),
      loggingEnabled: loggingEnabled ?? this.loggingEnabled,
      logger: logger ?? _logger,
    );
  }

  /// Two [AgentsCoreConfig] instances are equal when all seven value fields
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
        other.apiKey == apiKey &&
        other.loggingEnabled == loggingEnabled;
  }

  @override
  int get hashCode => Object.hash(
    lmStudioBaseUrl,
    defaultModel,
    requestTimeout,
    dockerImage,
    workspacePath,
    apiKey,
    loggingEnabled,
  );

  @override
  String toString() =>
      'AgentsCoreConfig('
      'lmStudioBaseUrl: $lmStudioBaseUrl, '
      'defaultModel: $defaultModel, '
      'requestTimeout: $requestTimeout, '
      'dockerImage: $dockerImage, '
      'workspacePath: $workspacePath, '
      'apiKey: ${apiKey != null ? '***' : 'null'}, '
      'loggingEnabled: $loggingEnabled'
      ')';
}
