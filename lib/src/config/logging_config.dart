import 'logger.dart';

/// Configuration for library-wide logging behaviour.
///
/// Separates the logging concern from connectivity and Docker settings so that
/// logging can be independently toggled or replaced without touching other
/// configuration aspects.
///
/// The key distinction between [logger] and [effectiveLogger]:
/// - [logger] is the **configured** logger instance (always non-null).
/// - [effectiveLogger] is the **active** logger — returns a [SilentLogger]
///   when [loggingEnabled] is `false`, otherwise returns [logger].
///
/// Consumers of `agents_core` should use [effectiveLogger] rather than
/// [logger] directly to respect the global on/off toggle.
///
/// ```dart
/// final loggingConfig = LoggingConfig(
///   logger: StderrLogger(level: LogLevel.debug),
///   loggingEnabled: true,
/// );
///
/// loggingConfig.effectiveLogger.info('Starting agent…');
/// ```
///
/// To suppress all output (e.g. in tests):
///
/// ```dart
/// final silent = LoggingConfig(loggingEnabled: false);
/// ```
class LoggingConfig {
  /// Creates a [LoggingConfig].
  ///
  /// [logger] is the underlying logger used when logging is enabled.
  /// Defaults to a [StderrLogger] at [LogLevel.info].
  ///
  /// [loggingEnabled] controls whether the [effectiveLogger] forwards
  /// messages. When `false`, [effectiveLogger] returns a [SilentLogger].
  /// Defaults to `true`.
  LoggingConfig({Logger? logger, this.loggingEnabled = true})
    : _logger = logger ?? const StderrLogger();

  final Logger _logger;

  /// Whether logging is globally active.
  ///
  /// When `false`, [effectiveLogger] returns a [SilentLogger] regardless of
  /// the configured [logger]. This provides a single switch to suppress all
  /// library-wide output without replacing the underlying logger instance.
  ///
  /// Defaults to `true`.
  final bool loggingEnabled;

  /// The configured logger instance.
  ///
  /// This is the logger that will be used when [loggingEnabled] is `true`.
  /// To write log messages while respecting the [loggingEnabled] gate,
  /// use [effectiveLogger] instead.
  Logger get logger => _logger;

  /// The active logger, gated by [loggingEnabled].
  ///
  /// Returns [logger] when [loggingEnabled] is `true`.
  /// Returns a [SilentLogger] when [loggingEnabled] is `false`.
  ///
  /// Prefer this getter over [logger] in all internal library code to
  /// ensure the global toggle is always honoured.
  Logger get effectiveLogger => loggingEnabled ? _logger : const SilentLogger();

  /// Returns a copy of this configuration with the specified fields replaced.
  ///
  /// Unspecified fields retain their current values.
  LoggingConfig copyWith({Logger? logger, bool? loggingEnabled}) {
    return LoggingConfig(
      logger: logger ?? _logger,
      loggingEnabled: loggingEnabled ?? this.loggingEnabled,
    );
  }

  /// Two [LoggingConfig] instances are equal when [loggingEnabled] matches.
  ///
  /// The [logger] instance is excluded from equality comparisons because
  /// loggers are typically stateful singletons and do not implement their
  /// own value equality — including them would make equality dependent on
  /// instance identity rather than configuration semantics.
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LoggingConfig && other.loggingEnabled == loggingEnabled;
  }

  @override
  int get hashCode => loggingEnabled.hashCode;

  @override
  String toString() =>
      'LoggingConfig('
      'loggingEnabled: $loggingEnabled, '
      'logger: ${_logger.runtimeType}'
      ')';
}
