import 'package:agents_core/agents_core.dart';
import 'package:test/test.dart';

void main() {
  group('AgentsCoreConfig', () {
    // ------------------------------------------------------------------ //
    // Defaults                                                            //
    // ------------------------------------------------------------------ //
    group('defaults', () {
      test('can be created with no arguments', () {
        final config = AgentsCoreConfig();
        expect(config, isNotNull);
      });

      test('default logger is a StderrLogger', () {
        final config = AgentsCoreConfig();
        expect(config.logger, isA<StderrLogger>());
      });

      test('default StderrLogger level is LogLevel.info', () {
        final config = AgentsCoreConfig();
        expect(config.logger.level, equals(LogLevel.info));
      });

      test('default lmStudioBaseUrl is http://localhost:1234', () {
        final config = AgentsCoreConfig();
        expect(config.lmStudioBaseUrl, equals(Uri.parse('http://localhost:1234')));
      });

      test('default requestTimeout is 60 seconds', () {
        final config = AgentsCoreConfig();
        expect(config.requestTimeout, equals(const Duration(seconds: 60)));
      });

      test('default defaultModel is a non-empty string', () {
        final config = AgentsCoreConfig();
        expect(config.defaultModel, isA<String>());
        expect(config.defaultModel, isNotEmpty);
      });

      test('default dockerImage is a non-empty string', () {
        final config = AgentsCoreConfig();
        expect(config.dockerImage, isA<String>());
        expect(config.dockerImage, isNotEmpty);
      });

      test('default workspacePath is a non-empty string', () {
        final config = AgentsCoreConfig();
        expect(config.workspacePath, isA<String>());
        expect(config.workspacePath, isNotEmpty);
      });
    });

    // ------------------------------------------------------------------ //
    // Custom logger injection                                             //
    // ------------------------------------------------------------------ //
    group('custom logger', () {
      test('accepts a SilentLogger', () {
        final config = AgentsCoreConfig(logger: const SilentLogger());
        expect(config.logger, isA<SilentLogger>());
      });

      test('accepts a StderrLogger with debug level', () {
        final config = AgentsCoreConfig(
          logger: const StderrLogger(level: LogLevel.debug),
        );
        expect(config.logger.level, equals(LogLevel.debug));
      });

      test('accepts a StderrLogger with warn level', () {
        final config = AgentsCoreConfig(
          logger: const StderrLogger(level: LogLevel.warn),
        );
        expect(config.logger.level, equals(LogLevel.warn));
      });

      test('accepts a StderrLogger with error level', () {
        final config = AgentsCoreConfig(
          logger: const StderrLogger(level: LogLevel.error),
        );
        expect(config.logger.level, equals(LogLevel.error));
      });

      test('stores the provided logger instance', () {
        const customLogger = SilentLogger();
        final config = AgentsCoreConfig(logger: customLogger);
        expect(config.logger, same(customLogger));
      });

      test('accepts a custom Logger implementation', () {
        final custom = _CustomLogger();
        final config = AgentsCoreConfig(logger: custom);
        expect(config.logger, isA<_CustomLogger>());
      });
    });

    // ------------------------------------------------------------------ //
    // Interface compliance                                                //
    // ------------------------------------------------------------------ //
    group('interface compliance', () {
      test('logger field is a Logger', () {
        final config = AgentsCoreConfig();
        expect(config.logger, isA<Logger>());
      });
    });

    // ------------------------------------------------------------------ //
    // Configuration fields                                                //
    // ------------------------------------------------------------------ //
    group('configuration fields', () {
      test('lmStudioBaseUrl can be set via constructor', () {
        final url = Uri.parse('http://192.168.1.10:5678');
        final config = AgentsCoreConfig(lmStudioBaseUrl: url);
        expect(config.lmStudioBaseUrl, equals(url));
      });

      test('defaultModel can be set via constructor', () {
        const model = 'my-custom-model';
        final config = AgentsCoreConfig(defaultModel: model);
        expect(config.defaultModel, equals(model));
      });

      test('requestTimeout can be set via constructor', () {
        const timeout = Duration(seconds: 120);
        final config = AgentsCoreConfig(requestTimeout: timeout);
        expect(config.requestTimeout, equals(timeout));
      });

      test('dockerImage can be set via constructor', () {
        const image = 'python:3.11-slim';
        final config = AgentsCoreConfig(dockerImage: image);
        expect(config.dockerImage, equals(image));
      });

      test('workspacePath can be set via constructor', () {
        const path = '/custom/workspace';
        final config = AgentsCoreConfig(workspacePath: path);
        expect(config.workspacePath, equals(path));
      });

      test('all fields can be set together', () {
        final url = Uri.parse('http://10.0.0.1:1234');
        const model = 'qwen2-7b';
        const timeout = Duration(seconds: 30);
        const image = 'python:3.12-slim';
        const path = '/tmp/my_workspace';

        final config = AgentsCoreConfig(
          lmStudioBaseUrl: url,
          defaultModel: model,
          requestTimeout: timeout,
          dockerImage: image,
          workspacePath: path,
          logger: const SilentLogger(),
        );

        expect(config.lmStudioBaseUrl, equals(url));
        expect(config.defaultModel, equals(model));
        expect(config.requestTimeout, equals(timeout));
        expect(config.dockerImage, equals(image));
        expect(config.workspacePath, equals(path));
        expect(config.logger, isA<SilentLogger>());
      });
    });

    // ------------------------------------------------------------------ //
    // copyWith                                                            //
    // ------------------------------------------------------------------ //
    group('copyWith', () {
      test('returns a new AgentsCoreConfig instance', () {
        final config = AgentsCoreConfig();
        final copy = config.copyWith();
        expect(copy, isA<AgentsCoreConfig>());
      });

      test('copy is not the same object as original', () {
        final config = AgentsCoreConfig();
        final copy = config.copyWith();
        expect(copy, isNot(same(config)));
      });

      test('copy with no args has equal values to original', () {
        final config = AgentsCoreConfig(
          lmStudioBaseUrl: Uri.parse('http://localhost:1234'),
          defaultModel: 'some-model',
          requestTimeout: const Duration(seconds: 45),
          dockerImage: 'python:3.12-slim',
          workspacePath: '/tmp/ws',
        );
        final copy = config.copyWith();
        expect(copy.lmStudioBaseUrl, equals(config.lmStudioBaseUrl));
        expect(copy.defaultModel, equals(config.defaultModel));
        expect(copy.requestTimeout, equals(config.requestTimeout));
        expect(copy.dockerImage, equals(config.dockerImage));
        expect(copy.workspacePath, equals(config.workspacePath));
      });

      test('copyWith updates lmStudioBaseUrl', () {
        final config = AgentsCoreConfig();
        final newUrl = Uri.parse('http://192.168.0.1:9999');
        final copy = config.copyWith(lmStudioBaseUrl: newUrl);
        expect(copy.lmStudioBaseUrl, equals(newUrl));
      });

      test('copyWith lmStudioBaseUrl retains other fields', () {
        final config = AgentsCoreConfig(
          defaultModel: 'original-model',
          requestTimeout: const Duration(seconds: 30),
        );
        final copy = config.copyWith(
          lmStudioBaseUrl: Uri.parse('http://other:1234'),
        );
        expect(copy.defaultModel, equals('original-model'));
        expect(copy.requestTimeout, equals(const Duration(seconds: 30)));
      });

      test('copyWith updates defaultModel', () {
        final config = AgentsCoreConfig(defaultModel: 'old-model');
        final copy = config.copyWith(defaultModel: 'new-model');
        expect(copy.defaultModel, equals('new-model'));
      });

      test('copyWith defaultModel retains other fields', () {
        final config = AgentsCoreConfig(
          dockerImage: 'python:3.11',
          workspacePath: '/original/path',
        );
        final copy = config.copyWith(defaultModel: 'updated-model');
        expect(copy.dockerImage, equals('python:3.11'));
        expect(copy.workspacePath, equals('/original/path'));
      });

      test('copyWith updates requestTimeout', () {
        final config = AgentsCoreConfig(
          requestTimeout: const Duration(seconds: 10),
        );
        final copy = config.copyWith(requestTimeout: const Duration(seconds: 120));
        expect(copy.requestTimeout, equals(const Duration(seconds: 120)));
      });

      test('copyWith updates dockerImage', () {
        final config = AgentsCoreConfig(dockerImage: 'python:3.10');
        final copy = config.copyWith(dockerImage: 'python:3.12-slim');
        expect(copy.dockerImage, equals('python:3.12-slim'));
      });

      test('copyWith updates workspacePath', () {
        final config = AgentsCoreConfig(workspacePath: '/old/path');
        final copy = config.copyWith(workspacePath: '/new/path');
        expect(copy.workspacePath, equals('/new/path'));
      });

      test('copyWith updates logger', () {
        final config = AgentsCoreConfig();
        const newLogger = SilentLogger();
        final copy = config.copyWith(logger: newLogger);
        expect(copy.logger, isA<SilentLogger>());
      });

      test('copyWith can update multiple fields at once', () {
        final config = AgentsCoreConfig();
        final copy = config.copyWith(
          defaultModel: 'multi-updated-model',
          dockerImage: 'python:3.12-slim',
          workspacePath: '/multi/update',
          requestTimeout: const Duration(seconds: 90),
        );
        expect(copy.defaultModel, equals('multi-updated-model'));
        expect(copy.dockerImage, equals('python:3.12-slim'));
        expect(copy.workspacePath, equals('/multi/update'));
        expect(copy.requestTimeout, equals(const Duration(seconds: 90)));
      });

      test('original instance is unchanged after copyWith', () {
        final config = AgentsCoreConfig(
          defaultModel: 'unchanged-model',
          dockerImage: 'python:3.11',
          workspacePath: '/unchanged/path',
          requestTimeout: const Duration(seconds: 25),
        );
        // Perform a copyWith that modifies all fields.
        config.copyWith(
          defaultModel: 'changed-model',
          dockerImage: 'python:3.12',
          workspacePath: '/changed/path',
          requestTimeout: const Duration(seconds: 99),
        );
        // Original must be unaffected.
        expect(config.defaultModel, equals('unchanged-model'));
        expect(config.dockerImage, equals('python:3.11'));
        expect(config.workspacePath, equals('/unchanged/path'));
        expect(config.requestTimeout, equals(const Duration(seconds: 25)));
      });

      test('chained copyWith calls accumulate changes correctly', () {
        final config = AgentsCoreConfig(
          defaultModel: 'base-model',
          dockerImage: 'base-image',
        );
        final copy1 = config.copyWith(defaultModel: 'step1-model');
        final copy2 = copy1.copyWith(dockerImage: 'step2-image');
        expect(copy2.defaultModel, equals('step1-model'));
        expect(copy2.dockerImage, equals('step2-image'));
      });
    });

    // ------------------------------------------------------------------ //
    // fromEnvironment                                                     //
    // ------------------------------------------------------------------ //
    group('fromEnvironment', () {
      test('returns an AgentsCoreConfig when environment map is empty', () {
        final config = AgentsCoreConfig.fromEnvironment(environment: {});
        expect(config, isA<AgentsCoreConfig>());
      });

      test('uses defaults when environment map is empty', () {
        final config = AgentsCoreConfig.fromEnvironment(environment: {});
        expect(config.lmStudioBaseUrl, equals(Uri.parse('http://localhost:1234')));
        expect(config.requestTimeout, equals(const Duration(seconds: 60)));
        expect(config.defaultModel, isNotEmpty);
        expect(config.dockerImage, isNotEmpty);
        expect(config.workspacePath, isNotEmpty);
      });

      test('reads LM_STUDIO_BASE_URL from environment', () {
        final config = AgentsCoreConfig.fromEnvironment(
          environment: {'LM_STUDIO_BASE_URL': 'http://192.168.1.5:1234'},
        );
        expect(
          config.lmStudioBaseUrl,
          equals(Uri.parse('http://192.168.1.5:1234')),
        );
      });

      test('reads AGENTS_DEFAULT_MODEL from environment', () {
        final config = AgentsCoreConfig.fromEnvironment(
          environment: {'AGENTS_DEFAULT_MODEL': 'env-provided-model'},
        );
        expect(config.defaultModel, equals('env-provided-model'));
      });

      test('reads AGENTS_DOCKER_IMAGE from environment', () {
        final config = AgentsCoreConfig.fromEnvironment(
          environment: {'AGENTS_DOCKER_IMAGE': 'python:3.11-slim'},
        );
        expect(config.dockerImage, equals('python:3.11-slim'));
      });

      test('reads AGENTS_WORKSPACE_PATH from environment', () {
        final config = AgentsCoreConfig.fromEnvironment(
          environment: {'AGENTS_WORKSPACE_PATH': '/env/workspace'},
        );
        expect(config.workspacePath, equals('/env/workspace'));
      });

      test('reads AGENTS_REQUEST_TIMEOUT_SECONDS from environment', () {
        final config = AgentsCoreConfig.fromEnvironment(
          environment: {'AGENTS_REQUEST_TIMEOUT_SECONDS': '120'},
        );
        expect(config.requestTimeout, equals(const Duration(seconds: 120)));
      });

      test('ignores invalid AGENTS_REQUEST_TIMEOUT_SECONDS and uses default',
          () {
        final config = AgentsCoreConfig.fromEnvironment(
          environment: {'AGENTS_REQUEST_TIMEOUT_SECONDS': 'not-a-number'},
        );
        expect(config.requestTimeout, equals(const Duration(seconds: 60)));
      });

      test('reads all environment variables together', () {
        final config = AgentsCoreConfig.fromEnvironment(
          environment: {
            'LM_STUDIO_BASE_URL': 'http://10.0.0.1:5678',
            'AGENTS_DEFAULT_MODEL': 'all-env-model',
            'AGENTS_DOCKER_IMAGE': 'python:3.12',
            'AGENTS_WORKSPACE_PATH': '/all/env/workspace',
            'AGENTS_REQUEST_TIMEOUT_SECONDS': '30',
          },
        );
        expect(
          config.lmStudioBaseUrl,
          equals(Uri.parse('http://10.0.0.1:5678')),
        );
        expect(config.defaultModel, equals('all-env-model'));
        expect(config.dockerImage, equals('python:3.12'));
        expect(config.workspacePath, equals('/all/env/workspace'));
        expect(config.requestTimeout, equals(const Duration(seconds: 30)));
      });

      test('can pass a logger alongside the environment map', () {
        final config = AgentsCoreConfig.fromEnvironment(
          environment: {},
          logger: const SilentLogger(),
        );
        expect(config.logger, isA<SilentLogger>());
      });

      test('environment map overrides constructor-default but not explicit logger', () {
        // Logger passed explicitly should win over any env default.
        const explicit = StderrLogger(level: LogLevel.debug);
        final config = AgentsCoreConfig.fromEnvironment(
          environment: {},
          logger: explicit,
        );
        expect(config.logger.level, equals(LogLevel.debug));
      });

      test('uses Platform.environment when no environment map is provided', () {
        // Cannot control Platform.environment in a unit test, so we just
        // verify no exception is thrown and a valid config is returned.
        expect(
          () => AgentsCoreConfig.fromEnvironment(),
          returnsNormally,
        );
        final config = AgentsCoreConfig.fromEnvironment();
        expect(config, isA<AgentsCoreConfig>());
      });

      test('ignores unknown environment variables', () {
        // Unknown keys should be silently ignored, not throw.
        expect(
          () => AgentsCoreConfig.fromEnvironment(
            environment: {'UNKNOWN_KEY': 'some-value'},
          ),
          returnsNormally,
        );
      });
    });

    // ------------------------------------------------------------------ //
    // Value object overrides (==, hashCode, toString)                    //
    // ------------------------------------------------------------------ //
    group('value object overrides', () {
      // == operator
      test('two configs with identical values are equal', () {
        final a = AgentsCoreConfig(
          lmStudioBaseUrl: Uri.parse('http://localhost:1234'),
          defaultModel: 'same-model',
          requestTimeout: const Duration(seconds: 60),
          dockerImage: 'python:3.12-slim',
          workspacePath: '/tmp/workspace',
        );
        final b = AgentsCoreConfig(
          lmStudioBaseUrl: Uri.parse('http://localhost:1234'),
          defaultModel: 'same-model',
          requestTimeout: const Duration(seconds: 60),
          dockerImage: 'python:3.12-slim',
          workspacePath: '/tmp/workspace',
        );
        expect(a, equals(b));
      });

      test('config is equal to itself', () {
        final config = AgentsCoreConfig();
        // ignore: unrelated_type_equality_checks
        expect(config == config, isTrue);
      });

      test('two configs differ when lmStudioBaseUrl differs', () {
        final a = AgentsCoreConfig(
          lmStudioBaseUrl: Uri.parse('http://localhost:1234'),
        );
        final b = AgentsCoreConfig(
          lmStudioBaseUrl: Uri.parse('http://localhost:5678'),
        );
        expect(a, isNot(equals(b)));
      });

      test('two configs differ when defaultModel differs', () {
        final a = AgentsCoreConfig(defaultModel: 'model-a');
        final b = AgentsCoreConfig(defaultModel: 'model-b');
        expect(a, isNot(equals(b)));
      });

      test('two configs differ when requestTimeout differs', () {
        final a = AgentsCoreConfig(requestTimeout: const Duration(seconds: 30));
        final b = AgentsCoreConfig(requestTimeout: const Duration(seconds: 60));
        expect(a, isNot(equals(b)));
      });

      test('two configs differ when dockerImage differs', () {
        final a = AgentsCoreConfig(dockerImage: 'python:3.11');
        final b = AgentsCoreConfig(dockerImage: 'python:3.12');
        expect(a, isNot(equals(b)));
      });

      test('two configs differ when workspacePath differs', () {
        final a = AgentsCoreConfig(workspacePath: '/path/a');
        final b = AgentsCoreConfig(workspacePath: '/path/b');
        expect(a, isNot(equals(b)));
      });

      // hashCode
      test('equal configs have the same hashCode', () {
        final a = AgentsCoreConfig(
          lmStudioBaseUrl: Uri.parse('http://localhost:1234'),
          defaultModel: 'hash-model',
          requestTimeout: const Duration(seconds: 60),
          dockerImage: 'python:3.12-slim',
          workspacePath: '/tmp/workspace',
        );
        final b = AgentsCoreConfig(
          lmStudioBaseUrl: Uri.parse('http://localhost:1234'),
          defaultModel: 'hash-model',
          requestTimeout: const Duration(seconds: 60),
          dockerImage: 'python:3.12-slim',
          workspacePath: '/tmp/workspace',
        );
        expect(a.hashCode, equals(b.hashCode));
      });

      test('config hashCode is consistent across calls', () {
        final config = AgentsCoreConfig(defaultModel: 'consistent-model');
        final hash1 = config.hashCode;
        final hash2 = config.hashCode;
        expect(hash1, equals(hash2));
      });

      test('different configs usually have different hashCodes', () {
        final a = AgentsCoreConfig(defaultModel: 'model-alpha');
        final b = AgentsCoreConfig(defaultModel: 'model-beta');
        // Hash collisions are theoretically possible but very unlikely here.
        expect(a.hashCode, isNot(equals(b.hashCode)));
      });

      // toString
      test('toString returns a non-empty string', () {
        final config = AgentsCoreConfig();
        expect(config.toString(), isNotEmpty);
      });

      test('toString contains the class name', () {
        final config = AgentsCoreConfig();
        expect(config.toString(), contains('AgentsCoreConfig'));
      });

      test('toString contains lmStudioBaseUrl value', () {
        final config = AgentsCoreConfig(
          lmStudioBaseUrl: Uri.parse('http://localhost:1234'),
        );
        expect(config.toString(), contains('localhost:1234'));
      });

      test('toString contains defaultModel value', () {
        final config = AgentsCoreConfig(defaultModel: 'visible-model');
        expect(config.toString(), contains('visible-model'));
      });

      test('toString contains workspacePath value', () {
        final config = AgentsCoreConfig(workspacePath: '/visible/path');
        expect(config.toString(), contains('/visible/path'));
      });
    });
  });
}

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

/// Minimal concrete [Logger] used to verify that [AgentsCoreConfig] accepts
/// any [Logger] implementation, not just the built-in ones.
class _CustomLogger extends Logger {
  @override
  LogLevel get level => LogLevel.debug;

  @override
  void debug(String message) {}

  @override
  void info(String message) {}

  @override
  void warn(String message) {}

  @override
  void error(String message) {}
}
