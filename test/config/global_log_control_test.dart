import 'dart:convert' show Encoding, utf8;
import 'dart:io';

import 'package:agents_core/agents_core.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Shared test infrastructure (mirrors logger_test.dart helper)
// ---------------------------------------------------------------------------

/// Minimal [Stdout] implementation that captures output in a [StringBuffer].
///
/// Used with [IOOverrides.runZoned] to intercept [stderr] writes made by
/// [StderrLogger] without polluting the test runner's output.
class _CapturedStdout implements Stdout {
  final StringBuffer _buf = StringBuffer();

  String get output => _buf.toString();

  @override
  Encoding encoding = utf8;

  @override
  void write(Object? object) => _buf.write(object);

  @override
  void writeAll(Iterable<dynamic> objects, [String separator = '']) {
    var first = true;
    for (final obj in objects) {
      if (!first) _buf.write(separator);
      _buf.write(obj);
      first = false;
    }
  }

  @override
  void writeCharCode(int charCode) => _buf.writeCharCode(charCode);

  @override
  void writeln([Object? object = '']) => _buf.writeln(object);

  @override
  void add(List<int> data) {}

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<List<int>> stream) => Future.value();

  @override
  Future<void> close() => Future.value();

  @override
  Future<void> get done => Future.value();

  @override
  Future<void> flush() => Future.value();

  @override
  bool get hasTerminal => false;

  @override
  int get terminalColumns => 80;

  @override
  int get terminalLines => 24;

  @override
  bool get supportsAnsiEscapes => false;

  @override
  String get lineTerminator => '\n';

  @override
  set lineTerminator(String value) {}

  @override
  IOSink get nonBlocking => this;
}

/// Runs [fn] with stderr redirected to a [_CapturedStdout] and returns the
/// captured output string.
String captureStderr(void Function() fn) {
  final fake = _CapturedStdout();
  IOOverrides.runZoned(fn, stderr: () => fake);
  return fake.output;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // ------------------------------------------------------------------ //
  // 1. Default state — logs are enabled by default                      //
  // ------------------------------------------------------------------ //
  group('global log control — default state (logs enabled)', () {
    test('AgentsCoreConfig.loggingEnabled defaults to true', () {
      final config = AgentsCoreConfig();
      expect(config.loggingEnabled, isTrue);
    });

    test('AgentsCoreConfig with explicit loggingEnabled: true stores true', () {
      final config = AgentsCoreConfig(loggingEnabled: true);
      expect(config.loggingEnabled, isTrue);
    });

    test('default config logger emits output to stderr (logs active)', () {
      final config = AgentsCoreConfig(
        logger: const StderrLogger(level: LogLevel.debug),
      );
      final out = captureStderr(() => config.logger.info('hello-enabled'));
      expect(out, contains('hello-enabled'));
    });

    test(
      'default config with loggingEnabled: true passes through logger messages',
      () {
        final config = AgentsCoreConfig(loggingEnabled: true);
        // Replace default logger with debug level so we can capture output.
        final debugConfig = config.copyWith(
          logger: const StderrLogger(level: LogLevel.debug),
        );
        final out = captureStderr(() => debugConfig.logger.info('logs-on'));
        expect(out, contains('logs-on'));
      },
    );

    test('default StderrLogger emits warn messages when logging enabled', () {
      final config = AgentsCoreConfig(
        loggingEnabled: true,
        logger: const StderrLogger(level: LogLevel.debug),
      );
      final out = captureStderr(() => config.logger.warn('warn-visible'));
      expect(out, contains('warn-visible'));
    });

    test('default StderrLogger emits error messages when logging enabled', () {
      final config = AgentsCoreConfig(
        loggingEnabled: true,
        logger: const StderrLogger(level: LogLevel.debug),
      );
      final out = captureStderr(() => config.logger.error('error-visible'));
      expect(out, contains('error-visible'));
    });

    test('default StderrLogger emits debug messages when logging enabled', () {
      final config = AgentsCoreConfig(
        loggingEnabled: true,
        logger: const StderrLogger(level: LogLevel.debug),
      );
      final out = captureStderr(() => config.logger.debug('debug-visible'));
      expect(out, contains('debug-visible'));
    });
  });

  // ------------------------------------------------------------------ //
  // 2. Disabling logs                                                    //
  // ------------------------------------------------------------------ //
  group('global log control — disabling logs', () {
    test('AgentsCoreConfig(loggingEnabled: false).loggingEnabled is false', () {
      final config = AgentsCoreConfig(loggingEnabled: false);
      expect(config.loggingEnabled, isFalse);
    });

    test('disabled config logger produces no stderr output on info()', () {
      final config = AgentsCoreConfig(loggingEnabled: false);
      final out = captureStderr(() => config.logger.info('should-be-silent'));
      expect(out, isEmpty);
    });

    test('disabled config logger produces no stderr output on debug()', () {
      final config = AgentsCoreConfig(loggingEnabled: false);
      final out = captureStderr(() => config.logger.debug('silent-debug'));
      expect(out, isEmpty);
    });

    test('disabled config logger produces no stderr output on warn()', () {
      final config = AgentsCoreConfig(loggingEnabled: false);
      final out = captureStderr(() => config.logger.warn('silent-warn'));
      expect(out, isEmpty);
    });

    test('disabled config logger produces no stderr output on error()', () {
      final config = AgentsCoreConfig(loggingEnabled: false);
      final out = captureStderr(() => config.logger.error('silent-error'));
      expect(out, isEmpty);
    });

    test('disabled config suppresses ALL four message levels', () {
      final config = AgentsCoreConfig(loggingEnabled: false);
      final out = captureStderr(() {
        config.logger.debug('d');
        config.logger.info('i');
        config.logger.warn('w');
        config.logger.error('e');
      });
      expect(out, isEmpty);
    });

    test('disabled config logger does not throw when called', () {
      final config = AgentsCoreConfig(loggingEnabled: false);
      expect(() {
        config.logger.debug('d');
        config.logger.info('i');
        config.logger.warn('w');
        config.logger.error('e');
      }, returnsNormally);
    });

    test('disabling with explicit StderrLogger still suppresses output', () {
      final config = AgentsCoreConfig(
        loggingEnabled: false,
        logger: const StderrLogger(level: LogLevel.debug),
      );
      final out = captureStderr(() => config.logger.info('suppressed'));
      expect(out, isEmpty);
    });

    test('disabling overrides even debug-level StderrLogger', () {
      final config = AgentsCoreConfig(
        loggingEnabled: false,
        logger: const StderrLogger(level: LogLevel.debug),
      );
      final out = captureStderr(() => config.logger.debug('no-output'));
      expect(out, isEmpty);
    });
  });

  // ------------------------------------------------------------------ //
  // 3. Re-enabling logs                                                  //
  // ------------------------------------------------------------------ //
  group('global log control — re-enabling logs', () {
    test('copyWith(loggingEnabled: true) re-enables logs', () {
      final disabled = AgentsCoreConfig(loggingEnabled: false);
      final reEnabled = disabled.copyWith(
        loggingEnabled: true,
        logger: const StderrLogger(level: LogLevel.debug),
      );
      expect(reEnabled.loggingEnabled, isTrue);
    });

    test('re-enabled config logger emits output again', () {
      final disabled = AgentsCoreConfig(loggingEnabled: false);
      final reEnabled = disabled.copyWith(
        loggingEnabled: true,
        logger: const StderrLogger(level: LogLevel.debug),
      );
      final out = captureStderr(() => reEnabled.logger.info('restored'));
      expect(out, contains('restored'));
    });

    test('re-enabled config emits all four message levels', () {
      final disabled = AgentsCoreConfig(loggingEnabled: false);
      final reEnabled = disabled.copyWith(
        loggingEnabled: true,
        logger: const StderrLogger(level: LogLevel.debug),
      );
      final out = captureStderr(() {
        reEnabled.logger.debug('dbg');
        reEnabled.logger.info('inf');
        reEnabled.logger.warn('wrn');
        reEnabled.logger.error('err');
      });
      expect(out, contains('dbg'));
      expect(out, contains('inf'));
      expect(out, contains('wrn'));
      expect(out, contains('err'));
    });

    test('disabling then re-enabling does not affect the original config', () {
      final original = AgentsCoreConfig(
        loggingEnabled: true,
        logger: const StderrLogger(level: LogLevel.debug),
      );
      // Disabling creates a NEW config — the original remains enabled.
      final _ = original.copyWith(loggingEnabled: false);
      expect(original.loggingEnabled, isTrue);
      final out = captureStderr(() => original.logger.info('still-active'));
      expect(out, contains('still-active'));
    });

    test(
      'multiple toggle: disable → enable → disable retains correct flag each step',
      () {
        final base = AgentsCoreConfig(
          logger: const StderrLogger(level: LogLevel.debug),
        );
        final step1 = base.copyWith(loggingEnabled: false);
        final step2 = step1.copyWith(loggingEnabled: true);
        final step3 = step2.copyWith(loggingEnabled: false);

        expect(step1.loggingEnabled, isFalse);
        expect(step2.loggingEnabled, isTrue);
        expect(step3.loggingEnabled, isFalse);
      },
    );
  });

  // ------------------------------------------------------------------ //
  // 4. Edge cases — toggling at runtime                                 //
  // ------------------------------------------------------------------ //
  group('global log control — edge cases', () {
    test(
      'toggling between two configs produces correct interleaved output',
      () {
        final enabled = AgentsCoreConfig(
          loggingEnabled: true,
          logger: const StderrLogger(level: LogLevel.debug),
        );
        final disabled = AgentsCoreConfig(
          loggingEnabled: false,
          logger: const StderrLogger(level: LogLevel.debug),
        );

        final out = captureStderr(() {
          enabled.logger.info('message-A');
          disabled.logger.info('message-B'); // should NOT appear
          enabled.logger.info('message-C');
        });

        expect(out, contains('message-A'));
        expect(out, isNot(contains('message-B')));
        expect(out, contains('message-C'));
      },
    );

    test('disabled config: no output across 20 rapid successive calls', () {
      final config = AgentsCoreConfig(loggingEnabled: false);
      final out = captureStderr(() {
        for (var i = 0; i < 20; i++) {
          config.logger.info('msg-$i');
        }
      });
      expect(out, isEmpty);
    });

    test('enabled config: output present for all rapid successive calls', () {
      final config = AgentsCoreConfig(
        loggingEnabled: true,
        logger: const StderrLogger(level: LogLevel.debug),
      );
      final out = captureStderr(() {
        for (var i = 0; i < 5; i++) {
          config.logger.info('item-$i');
        }
      });
      for (var i = 0; i < 5; i++) {
        expect(out, contains('item-$i'));
      }
    });

    test('SilentLogger stays silent even when loggingEnabled is true', () {
      // SilentLogger always suppresses output — loggingEnabled does not override.
      final config = AgentsCoreConfig(
        loggingEnabled: true,
        logger: const SilentLogger(),
      );
      final out = captureStderr(() => config.logger.info('still-silent'));
      expect(out, isEmpty);
    });

    test('loggingEnabled false with SilentLogger: remains silent', () {
      final config = AgentsCoreConfig(
        loggingEnabled: false,
        logger: const SilentLogger(),
      );
      final out = captureStderr(() => config.logger.error('definitely-silent'));
      expect(out, isEmpty);
    });

    test('disabling does not mutate the passed-in Logger instance', () {
      // The original Logger is untouched; only config.logger gates output.
      const original = StderrLogger(level: LogLevel.debug);
      final config = AgentsCoreConfig(loggingEnabled: false, logger: original);
      // Direct call to the original logger still emits.
      final outFromOriginal = captureStderr(() => original.info('direct-call'));
      expect(outFromOriginal, contains('direct-call'));
      // Through config.logger the gate suppresses it.
      final outFromConfig = captureStderr(
        () => config.logger.info('config-call'),
      );
      expect(outFromConfig, isEmpty);
    });

    test('multiple configs can have independent loggingEnabled settings', () {
      final configA = AgentsCoreConfig(
        loggingEnabled: true,
        logger: const StderrLogger(level: LogLevel.debug),
      );
      final configB = AgentsCoreConfig(loggingEnabled: false);

      final outA = captureStderr(() => configA.logger.info('from-a'));
      final outB = captureStderr(() => configB.logger.info('from-b'));

      expect(outA, contains('from-a'));
      expect(outB, isEmpty);
    });
  });

  // ------------------------------------------------------------------ //
  // 5. Environment variable — AGENTS_LOGGING_ENABLED                   //
  // ------------------------------------------------------------------ //
  group('global log control — environment variable', () {
    test('fromEnvironment defaults loggingEnabled to true (no env var)', () {
      final config = AgentsCoreConfig.fromEnvironment(environment: {});
      expect(config.loggingEnabled, isTrue);
    });

    test(
      "fromEnvironment with AGENTS_LOGGING_ENABLED='false' disables logging",
      () {
        final config = AgentsCoreConfig.fromEnvironment(
          environment: {'AGENTS_LOGGING_ENABLED': 'false'},
        );
        expect(config.loggingEnabled, isFalse);
      },
    );

    test(
      "fromEnvironment with AGENTS_LOGGING_ENABLED='true' enables logging",
      () {
        final config = AgentsCoreConfig.fromEnvironment(
          environment: {'AGENTS_LOGGING_ENABLED': 'true'},
        );
        expect(config.loggingEnabled, isTrue);
      },
    );

    test(
      "fromEnvironment with AGENTS_LOGGING_ENABLED='FALSE' (uppercase) disables logging",
      () {
        final config = AgentsCoreConfig.fromEnvironment(
          environment: {'AGENTS_LOGGING_ENABLED': 'FALSE'},
        );
        expect(config.loggingEnabled, isFalse);
      },
    );

    test(
      "fromEnvironment with AGENTS_LOGGING_ENABLED='0' disables logging",
      () {
        final config = AgentsCoreConfig.fromEnvironment(
          environment: {'AGENTS_LOGGING_ENABLED': '0'},
        );
        expect(config.loggingEnabled, isFalse);
      },
    );

    test('fromEnvironment disabled via env var: logger produces no output', () {
      final config = AgentsCoreConfig.fromEnvironment(
        environment: {'AGENTS_LOGGING_ENABLED': 'false'},
      );
      final out = captureStderr(() => config.logger.info('env-suppressed'));
      expect(out, isEmpty);
    });

    test('fromEnvironment enabled via env var: logger produces output', () {
      final config = AgentsCoreConfig.fromEnvironment(
        environment: {'AGENTS_LOGGING_ENABLED': 'true'},
        logger: const StderrLogger(level: LogLevel.debug),
      );
      final out = captureStderr(() => config.logger.info('env-visible'));
      expect(out, contains('env-visible'));
    });

    test(
      'fromEnvironment without AGENTS_LOGGING_ENABLED: loggingEnabled defaults to true',
      () {
        final config = AgentsCoreConfig.fromEnvironment(
          environment: {'AGENTS_DEFAULT_MODEL': 'some-model'},
        );
        expect(config.loggingEnabled, isTrue);
      },
    );

    test(
      'explicit loggingEnabled parameter overrides env var (param=true, var=false)',
      () {
        // Explicit parameter wins over the environment variable.
        final config = AgentsCoreConfig.fromEnvironment(
          environment: {'AGENTS_LOGGING_ENABLED': 'false'},
          loggingEnabled: true,
        );
        expect(config.loggingEnabled, isTrue);
      },
    );

    test(
      'explicit loggingEnabled parameter overrides env var (param=false, var=true)',
      () {
        final config = AgentsCoreConfig.fromEnvironment(
          environment: {'AGENTS_LOGGING_ENABLED': 'true'},
          loggingEnabled: false,
        );
        expect(config.loggingEnabled, isFalse);
      },
    );
  });

  // ------------------------------------------------------------------ //
  // 6. copyWith — loggingEnabled field                                  //
  // ------------------------------------------------------------------ //
  group('global log control — copyWith', () {
    test('copyWith(loggingEnabled: false) produces disabled config', () {
      final config = AgentsCoreConfig();
      final copy = config.copyWith(loggingEnabled: false);
      expect(copy.loggingEnabled, isFalse);
    });

    test('copyWith(loggingEnabled: true) produces enabled config', () {
      final config = AgentsCoreConfig(loggingEnabled: false);
      final copy = config.copyWith(loggingEnabled: true);
      expect(copy.loggingEnabled, isTrue);
    });

    test(
      'copyWith without loggingEnabled retains original value (enabled)',
      () {
        final config = AgentsCoreConfig(loggingEnabled: true);
        final copy = config.copyWith(defaultModel: 'new-model');
        expect(copy.loggingEnabled, isTrue);
      },
    );

    test(
      'copyWith without loggingEnabled retains original value (disabled)',
      () {
        final config = AgentsCoreConfig(loggingEnabled: false);
        final copy = config.copyWith(defaultModel: 'new-model');
        expect(copy.loggingEnabled, isFalse);
      },
    );

    test('copyWith(loggingEnabled: false) suppresses logger output', () {
      final enabled = AgentsCoreConfig(
        loggingEnabled: true,
        logger: const StderrLogger(level: LogLevel.debug),
      );
      final disabled = enabled.copyWith(loggingEnabled: false);
      final out = captureStderr(() => disabled.logger.info('now-silent'));
      expect(out, isEmpty);
    });

    test('copyWith(loggingEnabled: true) restores logger output', () {
      final disabled = AgentsCoreConfig(loggingEnabled: false);
      final enabled = disabled.copyWith(
        loggingEnabled: true,
        logger: const StderrLogger(level: LogLevel.debug),
      );
      final out = captureStderr(() => enabled.logger.info('now-active'));
      expect(out, contains('now-active'));
    });

    test(
      'chained copyWith: disable → enable → disable accumulates correctly',
      () {
        final base = AgentsCoreConfig(loggingEnabled: false);
        final step1 = base.copyWith(loggingEnabled: true);
        final step2 = step1.copyWith(loggingEnabled: false);
        final step3 = step2.copyWith(loggingEnabled: true);
        expect(step1.loggingEnabled, isTrue);
        expect(step2.loggingEnabled, isFalse);
        expect(step3.loggingEnabled, isTrue);
      },
    );

    test(
      'copyWith preserves all other fields when only loggingEnabled changes',
      () {
        final config = AgentsCoreConfig(
          lmStudioBaseUrl: Uri.parse('http://10.0.0.1:4321'),
          defaultModel: 'keep-model',
          requestTimeout: const Duration(seconds: 30),
          dockerImage: 'python:3.11',
          workspacePath: '/keep/path',
          apiKey: 'keep-key',
          loggingEnabled: true,
        );
        final copy = config.copyWith(loggingEnabled: false);
        expect(copy.lmStudioBaseUrl, equals(Uri.parse('http://10.0.0.1:4321')));
        expect(copy.defaultModel, equals('keep-model'));
        expect(copy.requestTimeout, equals(const Duration(seconds: 30)));
        expect(copy.dockerImage, equals('python:3.11'));
        expect(copy.workspacePath, equals('/keep/path'));
        expect(copy.apiKey, equals('keep-key'));
        expect(copy.loggingEnabled, isFalse);
      },
    );
  });

  // ------------------------------------------------------------------ //
  // 7. Value object — ==, hashCode, toString                           //
  // ------------------------------------------------------------------ //
  group('global log control — value object overrides', () {
    // == operator
    test('two configs with same loggingEnabled are equal', () {
      final a = AgentsCoreConfig(loggingEnabled: true);
      final b = AgentsCoreConfig(loggingEnabled: true);
      expect(a, equals(b));
    });

    test('configs with different loggingEnabled are not equal', () {
      final a = AgentsCoreConfig(loggingEnabled: true);
      final b = AgentsCoreConfig(loggingEnabled: false);
      expect(a, isNot(equals(b)));
    });

    test(
      'default config (loggingEnabled=true) equals explicit true config',
      () {
        final a = AgentsCoreConfig();
        final b = AgentsCoreConfig(loggingEnabled: true);
        expect(a, equals(b));
      },
    );

    // hashCode
    test('enabled and disabled configs produce different hashCodes', () {
      final a = AgentsCoreConfig(loggingEnabled: true);
      final b = AgentsCoreConfig(loggingEnabled: false);
      expect(a.hashCode, isNot(equals(b.hashCode)));
    });

    test('two enabled configs produce the same hashCode', () {
      final a = AgentsCoreConfig(loggingEnabled: true);
      final b = AgentsCoreConfig(loggingEnabled: true);
      expect(a.hashCode, equals(b.hashCode));
    });

    test('hashCode is consistent across multiple calls', () {
      final config = AgentsCoreConfig(loggingEnabled: false);
      expect(config.hashCode, equals(config.hashCode));
    });

    // toString
    test('toString includes the loggingEnabled field name', () {
      final config = AgentsCoreConfig(loggingEnabled: false);
      expect(config.toString(), contains('loggingEnabled'));
    });

    test('toString shows false when logging is disabled', () {
      final config = AgentsCoreConfig(loggingEnabled: false);
      expect(config.toString(), contains('false'));
    });

    test('toString shows true when logging is enabled', () {
      final config = AgentsCoreConfig(loggingEnabled: true);
      expect(config.toString(), contains('true'));
    });
  });

  // ------------------------------------------------------------------ //
  // 8. Backward compatibility — existing behaviour unaffected           //
  // ------------------------------------------------------------------ //
  group('global log control — backward compatibility', () {
    test('AgentsCoreConfig() has loggingEnabled=true by default', () {
      final config = AgentsCoreConfig();
      expect(config.loggingEnabled, isTrue);
    });

    test('existing StderrLogger still emits with default config', () {
      final config = AgentsCoreConfig(
        logger: const StderrLogger(level: LogLevel.debug),
      );
      final out = captureStderr(() => config.logger.info('backward-compat'));
      expect(out, contains('backward-compat'));
    });

    test(
      'SilentLogger config stays silent regardless of loggingEnabled=true',
      () {
        final config = AgentsCoreConfig(
          loggingEnabled: true,
          logger: const SilentLogger(),
        );
        final out = captureStderr(() => config.logger.info('should-be-silent'));
        expect(out, isEmpty);
      },
    );

    test(
      'all original constructor fields still accepted alongside loggingEnabled',
      () {
        final config = AgentsCoreConfig(
          lmStudioBaseUrl: Uri.parse('http://localhost:1234'),
          defaultModel: 'my-model',
          requestTimeout: const Duration(seconds: 60),
          dockerImage: 'python:3.12-slim',
          workspacePath: '/tmp/workspace',
          apiKey: 'my-key',
          logger: const SilentLogger(),
          loggingEnabled: false,
        );
        expect(config.loggingEnabled, isFalse);
        expect(config.apiKey, equals('my-key'));
        expect(config.defaultModel, equals('my-model'));
      },
    );

    test(
      'fromEnvironment without AGENTS_LOGGING_ENABLED still reads all other vars',
      () {
        final config = AgentsCoreConfig.fromEnvironment(
          environment: {
            'AGENTS_DEFAULT_MODEL': 'compat-model',
            'AGENTS_WORKSPACE_PATH': '/compat/path',
          },
        );
        expect(config.loggingEnabled, isTrue);
        expect(config.defaultModel, equals('compat-model'));
        expect(config.workspacePath, equals('/compat/path'));
      },
    );

    test('existing copyWith calls without loggingEnabled continue to work', () {
      final config = AgentsCoreConfig(defaultModel: 'old-model');
      final copy = config.copyWith(defaultModel: 'new-model');
      expect(copy.defaultModel, equals('new-model'));
      expect(copy.loggingEnabled, isTrue); // default retained
    });
  });
}
