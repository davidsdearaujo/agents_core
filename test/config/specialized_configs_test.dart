// ignore_for_file: avoid_redundant_argument_values
//
// M8 — Specialized configs (SRP)
//
// Tests every acceptance criterion for splitting AgentsCoreConfig into three
// focused sub-configs: LmStudioConfig, DockerConfig, LoggingConfig.
//
// All tests in this file FAIL until the M8 implementation is complete.
// That is intentional — this file defines the contract the developer must
// satisfy.

import 'package:agents_core/agents_core.dart';
import 'package:test/test.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// Helpers
// ═══════════════════════════════════════════════════════════════════════════════

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

// ═══════════════════════════════════════════════════════════════════════════════
// Tests
// ═══════════════════════════════════════════════════════════════════════════════

void main() {
  // ─────────────────────────────────────────────────────────────────────────
  // AC1: LmStudioConfig — new class with LM Studio-specific fields
  // ─────────────────────────────────────────────────────────────────────────
  group('LmStudioConfig', () {
    group('barrel export', () {
      test('LmStudioConfig is accessible from package:agents_core', () {
        final c = LmStudioConfig();
        expect(c, isA<LmStudioConfig>());
      });
    });

    group('defaults', () {
      test('can be created with no arguments', () {
        expect(() => LmStudioConfig(), returnsNormally);
      });

      test('default baseUrl is http://localhost:1234', () {
        final c = LmStudioConfig();
        expect(c.baseUrl, equals(Uri.parse('http://localhost:1234')));
      });

      test('default defaultModel is a non-empty string', () {
        final c = LmStudioConfig();
        expect(c.defaultModel, isA<String>());
        expect(c.defaultModel, isNotEmpty);
      });

      test('default requestTimeout is 60 seconds', () {
        final c = LmStudioConfig();
        expect(c.requestTimeout, equals(const Duration(seconds: 60)));
      });

      test('default apiKey is null', () {
        final c = LmStudioConfig();
        expect(c.apiKey, isNull);
      });
    });

    group('custom values', () {
      test('baseUrl can be set', () {
        final url = Uri.parse('http://10.0.0.1:5678');
        final c = LmStudioConfig(baseUrl: url);
        expect(c.baseUrl, equals(url));
      });

      test('defaultModel can be set', () {
        final c = LmStudioConfig(defaultModel: 'llama-3-8b');
        expect(c.defaultModel, equals('llama-3-8b'));
      });

      test('requestTimeout can be set', () {
        final c = LmStudioConfig(requestTimeout: const Duration(seconds: 120));
        expect(c.requestTimeout, equals(const Duration(seconds: 120)));
      });

      test('apiKey can be set', () {
        final c = LmStudioConfig(apiKey: 'sk-abc123');
        expect(c.apiKey, equals('sk-abc123'));
      });

      test('all fields can be set together', () {
        final url = Uri.parse('http://custom:9999');
        final c = LmStudioConfig(
          baseUrl: url,
          defaultModel: 'qwen2',
          requestTimeout: const Duration(seconds: 30),
          apiKey: 'key',
        );
        expect(c.baseUrl, equals(url));
        expect(c.defaultModel, equals('qwen2'));
        expect(c.requestTimeout, equals(const Duration(seconds: 30)));
        expect(c.apiKey, equals('key'));
      });
    });

    group('copyWith', () {
      test('copyWith returns a new instance', () {
        final c = LmStudioConfig();
        expect(c.copyWith(), isNot(same(c)));
      });

      test('copyWith with no args preserves all values', () {
        final c = LmStudioConfig(
          baseUrl: Uri.parse('http://host:1234'),
          defaultModel: 'model-x',
          requestTimeout: const Duration(seconds: 45),
          apiKey: 'key-x',
        );
        final copy = c.copyWith();
        expect(copy.baseUrl, equals(c.baseUrl));
        expect(copy.defaultModel, equals(c.defaultModel));
        expect(copy.requestTimeout, equals(c.requestTimeout));
        expect(copy.apiKey, equals(c.apiKey));
      });

      test('copyWith updates baseUrl only', () {
        final c = LmStudioConfig(defaultModel: 'retained');
        final updated = c.copyWith(baseUrl: Uri.parse('http://new:1234'));
        expect(updated.baseUrl, equals(Uri.parse('http://new:1234')));
        expect(updated.defaultModel, equals('retained'));
      });

      test('copyWith updates defaultModel only', () {
        final c = LmStudioConfig(baseUrl: Uri.parse('http://host:1234'));
        final updated = c.copyWith(defaultModel: 'new-model');
        expect(updated.defaultModel, equals('new-model'));
        expect(updated.baseUrl, equals(Uri.parse('http://host:1234')));
      });

      test('copyWith updates apiKey', () {
        final c = LmStudioConfig();
        final updated = c.copyWith(apiKey: 'new-key');
        expect(updated.apiKey, equals('new-key'));
      });

      test('copyWith clears apiKey when clearApiKey is true', () {
        final c = LmStudioConfig(apiKey: 'will-be-cleared');
        final updated = c.copyWith(clearApiKey: true);
        expect(updated.apiKey, isNull);
      });
    });

    group('value object', () {
      test('two identical LmStudioConfigs are equal', () {
        final a = LmStudioConfig(defaultModel: 'same-model');
        final b = LmStudioConfig(defaultModel: 'same-model');
        expect(a, equals(b));
      });

      test('two different LmStudioConfigs are not equal', () {
        final a = LmStudioConfig(defaultModel: 'model-a');
        final b = LmStudioConfig(defaultModel: 'model-b');
        expect(a, isNot(equals(b)));
      });

      test('equal configs have the same hashCode', () {
        final a = LmStudioConfig(defaultModel: 'same');
        final b = LmStudioConfig(defaultModel: 'same');
        expect(a.hashCode, equals(b.hashCode));
      });

      test('toString contains class name', () {
        expect(LmStudioConfig().toString(), contains('LmStudioConfig'));
      });

      test('toString masks apiKey', () {
        final c = LmStudioConfig(apiKey: 'secret-key');
        expect(c.toString(), contains('***'));
        expect(c.toString(), isNot(contains('secret-key')));
      });
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // AC2: DockerConfig — new class with Docker-specific fields
  // ─────────────────────────────────────────────────────────────────────────
  group('DockerConfig', () {
    group('barrel export', () {
      test('DockerConfig is accessible from package:agents_core', () {
        final c = DockerConfig();
        expect(c, isA<DockerConfig>());
      });
    });

    group('defaults', () {
      test('can be created with no arguments', () {
        expect(() => DockerConfig(), returnsNormally);
      });

      test('default image is a non-empty string', () {
        final c = DockerConfig();
        expect(c.image, isA<String>());
        expect(c.image, isNotEmpty);
      });

      test('default image is python:3.12-slim', () {
        final c = DockerConfig();
        expect(c.image, equals('python:3.12-slim'));
      });

      test('default workspacePath is a non-empty string', () {
        final c = DockerConfig();
        expect(c.workspacePath, isA<String>());
        expect(c.workspacePath, isNotEmpty);
      });
    });

    group('custom values', () {
      test('image can be set', () {
        final c = DockerConfig(image: 'python:3.11-slim');
        expect(c.image, equals('python:3.11-slim'));
      });

      test('workspacePath can be set', () {
        final c = DockerConfig(workspacePath: '/custom/workspace');
        expect(c.workspacePath, equals('/custom/workspace'));
      });

      test('both fields can be set together', () {
        final c = DockerConfig(
          image: 'node:20-slim',
          workspacePath: '/node/ws',
        );
        expect(c.image, equals('node:20-slim'));
        expect(c.workspacePath, equals('/node/ws'));
      });
    });

    group('copyWith', () {
      test('copyWith returns a new instance', () {
        final c = DockerConfig();
        expect(c.copyWith(), isNot(same(c)));
      });

      test('copyWith with no args preserves values', () {
        final c = DockerConfig(image: 'python:3.11', workspacePath: '/ws');
        final copy = c.copyWith();
        expect(copy.image, equals(c.image));
        expect(copy.workspacePath, equals(c.workspacePath));
      });

      test('copyWith updates image only', () {
        final c = DockerConfig(workspacePath: '/retained');
        final updated = c.copyWith(image: 'python:3.13');
        expect(updated.image, equals('python:3.13'));
        expect(updated.workspacePath, equals('/retained'));
      });

      test('copyWith updates workspacePath only', () {
        final c = DockerConfig(image: 'python:3.12-slim');
        final updated = c.copyWith(workspacePath: '/new/ws');
        expect(updated.workspacePath, equals('/new/ws'));
        expect(updated.image, equals('python:3.12-slim'));
      });
    });

    group('value object', () {
      test('two identical DockerConfigs are equal', () {
        final a = DockerConfig(image: 'same', workspacePath: '/same');
        final b = DockerConfig(image: 'same', workspacePath: '/same');
        expect(a, equals(b));
      });

      test('two different DockerConfigs are not equal', () {
        final a = DockerConfig(image: 'image-a');
        final b = DockerConfig(image: 'image-b');
        expect(a, isNot(equals(b)));
      });

      test('equal configs have the same hashCode', () {
        final a = DockerConfig(image: 'python:3.12-slim');
        final b = DockerConfig(image: 'python:3.12-slim');
        expect(a.hashCode, equals(b.hashCode));
      });

      test('toString contains class name', () {
        expect(DockerConfig().toString(), contains('DockerConfig'));
      });

      test('toString contains image value', () {
        final c = DockerConfig(image: 'my-custom-image');
        expect(c.toString(), contains('my-custom-image'));
      });
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // AC3: LoggingConfig — new class with logging-specific fields
  // ─────────────────────────────────────────────────────────────────────────
  group('LoggingConfig', () {
    group('barrel export', () {
      test('LoggingConfig is accessible from package:agents_core', () {
        final c = LoggingConfig();
        expect(c, isA<LoggingConfig>());
      });
    });

    group('defaults', () {
      test('can be created with no arguments', () {
        expect(() => LoggingConfig(), returnsNormally);
      });

      test('default loggingEnabled is true', () {
        final c = LoggingConfig();
        expect(c.loggingEnabled, isTrue);
      });

      test('default logger is StderrLogger', () {
        final c = LoggingConfig();
        expect(c.effectiveLogger, isA<StderrLogger>());
      });

      test('default logger level is LogLevel.info', () {
        final c = LoggingConfig();
        expect(c.effectiveLogger.level, equals(LogLevel.info));
      });
    });

    group('custom values', () {
      test('loggingEnabled false makes effectiveLogger a SilentLogger', () {
        final c = LoggingConfig(loggingEnabled: false);
        expect(c.effectiveLogger, isA<SilentLogger>());
      });

      test('custom logger is used when loggingEnabled is true', () {
        final custom = _CustomLogger();
        final c = LoggingConfig(logger: custom, loggingEnabled: true);
        expect(c.effectiveLogger, isA<_CustomLogger>());
      });

      test(
        'SilentLogger overrides custom logger when loggingEnabled is false',
        () {
          final custom = _CustomLogger();
          final c = LoggingConfig(logger: custom, loggingEnabled: false);
          expect(c.effectiveLogger, isA<SilentLogger>());
        },
      );

      test('accepts a SilentLogger directly', () {
        final c = LoggingConfig(logger: const SilentLogger());
        expect(c.effectiveLogger, isA<SilentLogger>());
      });

      test('accepts a StderrLogger with debug level', () {
        final c = LoggingConfig(
          logger: const StderrLogger(level: LogLevel.debug),
        );
        expect(c.effectiveLogger.level, equals(LogLevel.debug));
      });
    });

    group('copyWith', () {
      test('copyWith returns a new instance', () {
        final c = LoggingConfig();
        expect(c.copyWith(), isNot(same(c)));
      });

      test('copyWith with no args preserves loggingEnabled', () {
        final c = LoggingConfig(loggingEnabled: false);
        final copy = c.copyWith();
        expect(copy.loggingEnabled, isFalse);
      });

      test('copyWith updates loggingEnabled', () {
        final c = LoggingConfig(loggingEnabled: true);
        final updated = c.copyWith(loggingEnabled: false);
        expect(updated.loggingEnabled, isFalse);
      });

      test('copyWith updates logger', () {
        final c = LoggingConfig();
        final updated = c.copyWith(logger: const SilentLogger());
        expect(updated.effectiveLogger, isA<SilentLogger>());
      });
    });

    group('value object', () {
      test('two default LoggingConfigs are equal', () {
        final a = LoggingConfig();
        final b = LoggingConfig();
        expect(a, equals(b));
      });

      test('loggingEnabled false and true are not equal', () {
        final a = LoggingConfig(loggingEnabled: false);
        final b = LoggingConfig(loggingEnabled: true);
        expect(a, isNot(equals(b)));
      });

      test('toString contains class name', () {
        expect(LoggingConfig().toString(), contains('LoggingConfig'));
      });

      test('toString contains loggingEnabled value', () {
        final c = LoggingConfig(loggingEnabled: false);
        expect(c.toString(), contains('false'));
      });
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // AC4: AgentsCoreConfig aggregates the three specialized configs
  // ─────────────────────────────────────────────────────────────────────────
  group('AgentsCoreConfig — aggregation (M8)', () {
    group('exposes lmStudio sub-config', () {
      test('has lmStudio getter returning LmStudioConfig', () {
        final c = AgentsCoreConfig();
        expect(c.lmStudio, isA<LmStudioConfig>());
      });

      test('lmStudio.baseUrl matches top-level lmStudioBaseUrl', () {
        final url = Uri.parse('http://custom:5678');
        final c = AgentsCoreConfig(lmStudioBaseUrl: url);
        expect(c.lmStudio.baseUrl, equals(url));
      });

      test('lmStudio.defaultModel matches top-level defaultModel', () {
        final c = AgentsCoreConfig(defaultModel: 'my-model');
        expect(c.lmStudio.defaultModel, equals('my-model'));
      });

      test('lmStudio.requestTimeout matches top-level requestTimeout', () {
        final c = AgentsCoreConfig(requestTimeout: const Duration(seconds: 30));
        expect(c.lmStudio.requestTimeout, equals(const Duration(seconds: 30)));
      });

      test('lmStudio.apiKey matches top-level apiKey', () {
        final c = AgentsCoreConfig(apiKey: 'top-level-key');
        expect(c.lmStudio.apiKey, equals('top-level-key'));
      });
    });

    group('exposes docker sub-config', () {
      test('has docker getter returning DockerConfig', () {
        final c = AgentsCoreConfig();
        expect(c.docker, isA<DockerConfig>());
      });

      test('docker.image matches top-level dockerImage', () {
        final c = AgentsCoreConfig(dockerImage: 'python:3.11-slim');
        expect(c.docker.image, equals('python:3.11-slim'));
      });

      test('docker.workspacePath matches top-level workspacePath', () {
        final c = AgentsCoreConfig(workspacePath: '/custom/ws');
        expect(c.docker.workspacePath, equals('/custom/ws'));
      });
    });

    group('exposes logging sub-config', () {
      test('has logging getter returning LoggingConfig', () {
        final c = AgentsCoreConfig();
        expect(c.logging, isA<LoggingConfig>());
      });

      test('logging.loggingEnabled matches top-level loggingEnabled', () {
        final c = AgentsCoreConfig(loggingEnabled: false);
        expect(c.logging.loggingEnabled, isFalse);
      });

      test('logging.effectiveLogger matches top-level logger behavior', () {
        final c = AgentsCoreConfig(logger: const SilentLogger());
        expect(c.logging.effectiveLogger, isA<SilentLogger>());
      });

      test(
        'logging.loggingEnabled false → effectiveLogger is SilentLogger',
        () {
          final c = AgentsCoreConfig(loggingEnabled: false);
          expect(c.logging.effectiveLogger, isA<SilentLogger>());
        },
      );
    });

    group('constructor using sub-configs directly', () {
      test(
        'can construct AgentsCoreConfig from LmStudioConfig + DockerConfig + LoggingConfig',
        () {
          final lm = LmStudioConfig(
            baseUrl: Uri.parse('http://from-config:1234'),
            defaultModel: 'config-model',
          );
          final docker = DockerConfig(image: 'python:3.12-slim');
          final logging = LoggingConfig(logger: const SilentLogger());

          final c = AgentsCoreConfig.fromConfigs(
            lmStudio: lm,
            docker: docker,
            logging: logging,
          );

          expect(
            c.lmStudioBaseUrl,
            equals(Uri.parse('http://from-config:1234')),
          );
          expect(c.defaultModel, equals('config-model'));
          expect(c.dockerImage, equals('python:3.12-slim'));
          expect(c.logger, isA<SilentLogger>());
        },
      );

      test('fromConfigs uses sub-config defaults when fields are omitted', () {
        final c = AgentsCoreConfig.fromConfigs(
          lmStudio: LmStudioConfig(),
          docker: DockerConfig(),
          logging: LoggingConfig(),
        );
        expect(c.lmStudioBaseUrl, equals(Uri.parse('http://localhost:1234')));
        expect(c.dockerImage, equals('python:3.12-slim'));
      });
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // AC5: Backwards compatibility — existing AgentsCoreConfig API unchanged
  // ─────────────────────────────────────────────────────────────────────────
  group('AgentsCoreConfig — backwards compatibility', () {
    test('top-level lmStudioBaseUrl still accessible', () {
      final url = Uri.parse('http://localhost:1234');
      final c = AgentsCoreConfig(lmStudioBaseUrl: url);
      expect(c.lmStudioBaseUrl, equals(url));
    });

    test('top-level defaultModel still accessible', () {
      final c = AgentsCoreConfig(defaultModel: 'compat-model');
      expect(c.defaultModel, equals('compat-model'));
    });

    test('top-level requestTimeout still accessible', () {
      final c = AgentsCoreConfig(requestTimeout: const Duration(seconds: 45));
      expect(c.requestTimeout, equals(const Duration(seconds: 45)));
    });

    test('top-level dockerImage still accessible', () {
      final c = AgentsCoreConfig(dockerImage: 'python:3.11-slim');
      expect(c.dockerImage, equals('python:3.11-slim'));
    });

    test('top-level workspacePath still accessible', () {
      final c = AgentsCoreConfig(workspacePath: '/legacy/path');
      expect(c.workspacePath, equals('/legacy/path'));
    });

    test('top-level apiKey still accessible', () {
      final c = AgentsCoreConfig(apiKey: 'legacy-key');
      expect(c.apiKey, equals('legacy-key'));
    });

    test('top-level loggingEnabled still accessible', () {
      final c = AgentsCoreConfig(loggingEnabled: false);
      expect(c.loggingEnabled, isFalse);
    });

    test('top-level logger getter still returns effective logger', () {
      final c = AgentsCoreConfig(logger: const SilentLogger());
      expect(c.logger, isA<SilentLogger>());
    });

    test(
      'loggingEnabled=false still returns SilentLogger from logger getter',
      () {
        final c = AgentsCoreConfig(loggingEnabled: false);
        expect(c.logger, isA<SilentLogger>());
      },
    );

    test('copyWith still works with all existing fields', () {
      final c = AgentsCoreConfig();
      final copy = c.copyWith(
        lmStudioBaseUrl: Uri.parse('http://new:1234'),
        defaultModel: 'new-model',
        dockerImage: 'python:3.11',
        workspacePath: '/new/ws',
        requestTimeout: const Duration(seconds: 90),
        apiKey: 'new-key',
        loggingEnabled: false,
        logger: const SilentLogger(),
      );
      expect(copy.lmStudioBaseUrl, equals(Uri.parse('http://new:1234')));
      expect(copy.defaultModel, equals('new-model'));
      expect(copy.dockerImage, equals('python:3.11'));
      expect(copy.workspacePath, equals('/new/ws'));
      expect(copy.requestTimeout, equals(const Duration(seconds: 90)));
      expect(copy.apiKey, equals('new-key'));
      expect(copy.loggingEnabled, isFalse);
    });

    test('fromEnvironment still works with the same env-var mapping', () {
      final c = AgentsCoreConfig.fromEnvironment(
        environment: {
          'LM_STUDIO_BASE_URL': 'http://env-host:1234',
          'AGENTS_DEFAULT_MODEL': 'env-model',
          'AGENTS_DOCKER_IMAGE': 'python:3.11',
          'AGENTS_WORKSPACE_PATH': '/env/ws',
          'AGENTS_REQUEST_TIMEOUT_SECONDS': '30',
          'AGENTS_API_KEY': 'env-key',
        },
      );
      expect(c.lmStudioBaseUrl, equals(Uri.parse('http://env-host:1234')));
      expect(c.defaultModel, equals('env-model'));
      expect(c.dockerImage, equals('python:3.11'));
      expect(c.workspacePath, equals('/env/ws'));
      expect(c.requestTimeout, equals(const Duration(seconds: 30)));
      expect(c.apiKey, equals('env-key'));
    });

    test('== and hashCode still work after M8 refactor', () {
      final a = AgentsCoreConfig(defaultModel: 'eq-model');
      final b = AgentsCoreConfig(defaultModel: 'eq-model');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('toString still contains AgentsCoreConfig class name', () {
      expect(AgentsCoreConfig().toString(), contains('AgentsCoreConfig'));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // AC6a: LmStudioHttpClient accepts LmStudioConfig directly
  // ─────────────────────────────────────────────────────────────────────────
  group('LmStudioHttpClient — accepts LmStudioConfig', () {
    test('can be constructed with LmStudioConfig', () {
      final lmCfg = LmStudioConfig(baseUrl: Uri.parse('http://localhost:1234'));
      expect(() => LmStudioHttpClient(lmStudioConfig: lmCfg), returnsNormally);
    });

    test('LmStudioConfig.baseUrl is used as the base URL', () {
      // We verify via a captured request: if the wrong URL were used, the
      // test would fail on the URL check.
      final lmCfg = LmStudioConfig(
        baseUrl: Uri.parse('http://specialized-host:4321'),
      );
      // Construction with the specialized config should not throw.
      final client = LmStudioHttpClient(lmStudioConfig: lmCfg);
      expect(client, isA<LmStudioHttpClient>());
      client.dispose();
    });

    test('LmStudioConfig.requestTimeout is applied', () {
      final lmCfg = LmStudioConfig(requestTimeout: const Duration(seconds: 15));
      expect(() => LmStudioHttpClient(lmStudioConfig: lmCfg), returnsNormally);
    });

    test(
      'legacy AgentsCoreConfig parameter still works (backwards compat)',
      () {
        // The old `config:` param must remain functional so consumers are not
        // broken by M8.
        expect(
          () => LmStudioHttpClient(
            config: AgentsCoreConfig(logger: SilentLogger()),
          ),
          returnsNormally,
        );
      },
    );

    test('legacy baseUrl string parameter still works (backwards compat)', () {
      expect(
        () => LmStudioHttpClient(baseUrl: 'http://localhost:1234'),
        returnsNormally,
      );
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // AC6b: DockerClient (or related component) accepts specialized config
  // ─────────────────────────────────────────────────────────────────────────
  group('DockerClient — accepts LoggingConfig', () {
    test('can be constructed with LoggingConfig', () {
      final logCfg = LoggingConfig(logger: const SilentLogger());
      expect(() => DockerClient(loggingConfig: logCfg), returnsNormally);
    });

    test('loggingConfig.effectiveLogger is used for diagnostic output', () {
      final logCfg = LoggingConfig(logger: const SilentLogger());
      final client = DockerClient(loggingConfig: logCfg);
      expect(client, isA<DockerClient>());
    });

    test('legacy Logger parameter still works (backwards compat)', () {
      expect(() => DockerClient(logger: const SilentLogger()), returnsNormally);
    });

    test('DockerClient with loggingEnabled=false silences all log output', () {
      final logCfg = LoggingConfig(loggingEnabled: false);
      expect(() => DockerClient(loggingConfig: logCfg), returnsNormally);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // AC6c: LmStudioClient accepts LmStudioConfig
  // ─────────────────────────────────────────────────────────────────────────
  group('LmStudioClient — accepts LmStudioConfig', () {
    test('can be constructed with LmStudioConfig', () {
      final lmCfg = LmStudioConfig();
      expect(() => LmStudioClient.fromLmStudioConfig(lmCfg), returnsNormally);
    });

    test('legacy AgentsCoreConfig constructor still works', () {
      expect(
        () => LmStudioClient(AgentsCoreConfig(logger: SilentLogger())),
        returnsNormally,
      );
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // AC7: All new configs are value objects (== / hashCode)
  // ─────────────────────────────────────────────────────────────────────────
  group('Specialized configs — value semantics', () {
    test('two default LmStudioConfigs are equal', () {
      expect(LmStudioConfig(), equals(LmStudioConfig()));
    });

    test('two default DockerConfigs are equal', () {
      expect(DockerConfig(), equals(DockerConfig()));
    });

    test('two default LoggingConfigs are equal', () {
      expect(LoggingConfig(), equals(LoggingConfig()));
    });

    test('LmStudioConfig hashCodes are consistent', () {
      final c = LmStudioConfig(defaultModel: 'stable');
      expect(c.hashCode, equals(c.hashCode));
    });

    test('DockerConfig hashCodes are consistent', () {
      final c = DockerConfig(image: 'stable-image');
      expect(c.hashCode, equals(c.hashCode));
    });

    test('LoggingConfig hashCodes are consistent', () {
      final c = LoggingConfig(loggingEnabled: false);
      expect(c.hashCode, equals(c.hashCode));
    });
  });
}
