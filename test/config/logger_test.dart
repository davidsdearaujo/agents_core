import 'dart:convert' show Encoding, utf8;
import 'dart:io';

import 'package:agents_core/agents_core.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Test infrastructure
// ---------------------------------------------------------------------------

/// Minimal [Stdout] implementation that captures output in a [StringBuffer].
///
/// Used with [IOOverrides.runZoned] to intercept [stderr] writes made by
/// [StderrLogger] without polluting the test runner's output.
class _CapturedStdout implements Stdout {
  final StringBuffer _buf = StringBuffer();

  /// All text written to this sink since construction.
  String get output => _buf.toString();

  // ---- Encoding (IOSink) ----
  @override
  Encoding encoding = utf8;

  // ---- StringSink ----
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

  // ---- StreamSink<List<int>> ----
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

  // ---- Stdout-specific ----
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

  /// Non-blocking variant — returns this sink for simplicity in tests.
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

/// A concrete [Logger] subclass used in tests that verifies the abstract
/// interface can be implemented by user code and that level filtering works.
class _RecordingLogger extends Logger {
  final LogLevel _level;
  final List<String> debugMessages = [];
  final List<String> infoMessages = [];
  final List<String> warnMessages = [];
  final List<String> errorMessages = [];

  _RecordingLogger(this._level);

  @override
  LogLevel get level => _level;

  @override
  void debug(String message) {
    if (LogLevel.debug.index >= _level.index) debugMessages.add(message);
  }

  @override
  void info(String message) {
    if (LogLevel.info.index >= _level.index) infoMessages.add(message);
  }

  @override
  void warn(String message) {
    if (LogLevel.warn.index >= _level.index) warnMessages.add(message);
  }

  @override
  void error(String message) {
    if (LogLevel.error.index >= _level.index) errorMessages.add(message);
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // ------------------------------------------------------------------ //
  // LogLevel enum                                                        //
  // ------------------------------------------------------------------ //
  group('LogLevel', () {
    test('has exactly four levels', () {
      expect(LogLevel.values, hasLength(4));
    });

    test('debug is the lowest level (index 0)', () {
      expect(LogLevel.debug.index, equals(0));
    });

    test('info is index 1', () {
      expect(LogLevel.info.index, equals(1));
    });

    test('warn is index 2', () {
      expect(LogLevel.warn.index, equals(2));
    });

    test('error is the highest level (index 3)', () {
      expect(LogLevel.error.index, equals(3));
    });

    test('ordering: debug < info < warn < error', () {
      expect(LogLevel.debug.index, lessThan(LogLevel.info.index));
      expect(LogLevel.info.index, lessThan(LogLevel.warn.index));
      expect(LogLevel.warn.index, lessThan(LogLevel.error.index));
    });
  });

  // ------------------------------------------------------------------ //
  // Logger (abstract interface)                                          //
  // ------------------------------------------------------------------ //
  group('Logger (abstract interface)', () {
    test('can be subclassed with a custom level', () {
      final logger = _RecordingLogger(LogLevel.debug);
      expect(logger.level, equals(LogLevel.debug));
    });

    test('subclass receives debug messages at LogLevel.debug', () {
      final logger = _RecordingLogger(LogLevel.debug);
      logger.debug('d');
      expect(logger.debugMessages, contains('d'));
    });

    test('subclass suppresses debug messages at LogLevel.info', () {
      final logger = _RecordingLogger(LogLevel.info);
      logger.debug('suppressed');
      expect(logger.debugMessages, isEmpty);
    });

    test('subclass passes warn messages at LogLevel.warn', () {
      final logger = _RecordingLogger(LogLevel.warn);
      logger.warn('w');
      expect(logger.warnMessages, contains('w'));
    });

    test('subclass suppresses info messages at LogLevel.warn', () {
      final logger = _RecordingLogger(LogLevel.warn);
      logger.info('suppressed');
      expect(logger.infoMessages, isEmpty);
    });

    test('subclass receives only error messages at LogLevel.error', () {
      final logger = _RecordingLogger(LogLevel.error);
      logger.debug('d');
      logger.info('i');
      logger.warn('w');
      logger.error('e');
      expect(logger.debugMessages, isEmpty);
      expect(logger.infoMessages, isEmpty);
      expect(logger.warnMessages, isEmpty);
      expect(logger.errorMessages, contains('e'));
    });
  });

  // ------------------------------------------------------------------ //
  // StderrLogger                                                         //
  // ------------------------------------------------------------------ //
  group('StderrLogger', () {
    group('construction', () {
      test('default level is LogLevel.info', () {
        const logger = StderrLogger();
        expect(logger.level, equals(LogLevel.info));
      });

      test('level can be overridden via constructor', () {
        const logger = StderrLogger(level: LogLevel.debug);
        expect(logger.level, equals(LogLevel.debug));
      });

      test('is a Logger', () {
        const logger = StderrLogger();
        expect(logger, isA<Logger>());
      });
    });

    group('level filtering', () {
      test('with level=warn, debug message is NOT emitted to stderr', () {
        const logger = StderrLogger(level: LogLevel.warn);
        final out = captureStderr(() => logger.debug('should be silent'));
        expect(out, isEmpty);
      });

      test('with level=warn, info message is NOT emitted to stderr', () {
        const logger = StderrLogger(level: LogLevel.warn);
        final out = captureStderr(() => logger.info('should be silent'));
        expect(out, isEmpty);
      });

      test('with level=warn, warn message IS emitted to stderr', () {
        const logger = StderrLogger(level: LogLevel.warn);
        final out = captureStderr(() => logger.warn('visible'));
        expect(out, contains('visible'));
      });

      test('with level=warn, error message IS emitted to stderr', () {
        const logger = StderrLogger(level: LogLevel.warn);
        final out = captureStderr(() => logger.error('visible'));
        expect(out, contains('visible'));
      });

      test('with level=debug, all four severity messages are emitted', () {
        const logger = StderrLogger(level: LogLevel.debug);
        final out = captureStderr(() {
          logger.debug('dbg');
          logger.info('inf');
          logger.warn('wrn');
          logger.error('err');
        });
        expect(out, contains('dbg'));
        expect(out, contains('inf'));
        expect(out, contains('wrn'));
        expect(out, contains('err'));
      });

      test('with level=error, only error message is emitted', () {
        const logger = StderrLogger(level: LogLevel.error);
        final out = captureStderr(() {
          logger.debug('d');
          logger.info('i');
          logger.warn('w');
          logger.error('e');
        });
        expect(out, isNot(contains('[DEBUG]')));
        expect(out, isNot(contains('[INFO]')));
        expect(out, isNot(contains('[WARN]')));
        expect(out, contains('e'));
      });

      test(
          'with level=info, debug is suppressed but info/warn/error are emitted',
          () {
        const logger = StderrLogger(level: LogLevel.info);
        final out = captureStderr(() {
          logger.debug('dbg-hidden');
          logger.info('inf-visible');
          logger.warn('wrn-visible');
          logger.error('err-visible');
        });
        expect(out, isNot(contains('dbg-hidden')));
        expect(out, contains('inf-visible'));
        expect(out, contains('wrn-visible'));
        expect(out, contains('err-visible'));
      });
    });

    group('output format', () {
      test('emitted message contains the original text', () {
        const logger = StderrLogger(level: LogLevel.debug);
        final out = captureStderr(() => logger.info('hello world'));
        expect(out, contains('hello world'));
      });

      test('emitted message contains [DEBUG] label for debug()', () {
        const logger = StderrLogger(level: LogLevel.debug);
        final out = captureStderr(() => logger.debug('x'));
        expect(out, contains('[DEBUG]'));
      });

      test('emitted message contains [INFO] label for info()', () {
        const logger = StderrLogger(level: LogLevel.debug);
        final out = captureStderr(() => logger.info('x'));
        expect(out, contains('[INFO]'));
      });

      test('emitted message contains [WARN] label for warn()', () {
        const logger = StderrLogger(level: LogLevel.debug);
        final out = captureStderr(() => logger.warn('x'));
        expect(out, contains('[WARN]'));
      });

      test('emitted message contains [ERROR] label for error()', () {
        const logger = StderrLogger(level: LogLevel.debug);
        final out = captureStderr(() => logger.error('x'));
        expect(out, contains('[ERROR]'));
      });

      test('emitted message contains a UTC ISO-8601 timestamp', () {
        const logger = StderrLogger(level: LogLevel.debug);
        final out = captureStderr(() => logger.info('ts-check'));
        // Timestamps look like 2026-03-25T12:30:45.123Z
        expect(out, matches(RegExp(r'\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}')));
      });
    });
  });

  // ------------------------------------------------------------------ //
  // SilentLogger                                                         //
  // ------------------------------------------------------------------ //
  group('SilentLogger', () {
    group('construction', () {
      test('can be instantiated', () {
        const logger = SilentLogger();
        expect(logger, isNotNull);
      });

      test('is a Logger', () {
        const logger = SilentLogger();
        expect(logger, isA<Logger>());
      });

      test('level is LogLevel.error', () {
        const logger = SilentLogger();
        expect(logger.level, equals(LogLevel.error));
      });
    });

    group('emits nothing', () {
      test('debug() does not throw', () {
        const logger = SilentLogger();
        expect(() => logger.debug('msg'), returnsNormally);
      });

      test('info() does not throw', () {
        const logger = SilentLogger();
        expect(() => logger.info('msg'), returnsNormally);
      });

      test('warn() does not throw', () {
        const logger = SilentLogger();
        expect(() => logger.warn('msg'), returnsNormally);
      });

      test('error() does not throw', () {
        const logger = SilentLogger();
        expect(() => logger.error('msg'), returnsNormally);
      });

      test('debug() produces no stderr output', () {
        const logger = SilentLogger();
        final out = captureStderr(() => logger.debug('silent'));
        expect(out, isEmpty);
      });

      test('info() produces no stderr output', () {
        const logger = SilentLogger();
        final out = captureStderr(() => logger.info('silent'));
        expect(out, isEmpty);
      });

      test('warn() produces no stderr output', () {
        const logger = SilentLogger();
        final out = captureStderr(() => logger.warn('silent'));
        expect(out, isEmpty);
      });

      test('error() produces no stderr output', () {
        const logger = SilentLogger();
        final out = captureStderr(() => logger.error('silent'));
        expect(out, isEmpty);
      });

      test('calling all methods with repeated messages produces no output', () {
        const logger = SilentLogger();
        final out = captureStderr(() {
          for (var i = 0; i < 5; i++) {
            logger.debug('d$i');
            logger.info('i$i');
            logger.warn('w$i');
            logger.error('e$i');
          }
        });
        expect(out, isEmpty);
      });
    });
  });
}
