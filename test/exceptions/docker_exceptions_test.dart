import 'package:agents_core/agents_core.dart';
import 'package:test/test.dart';

void main() {
  group('DockerNotAvailableException', () {
    group('construction', () {
      test('can be instantiated with required message', () {
        const exception =
            DockerNotAvailableException(message: 'Docker not found');
        expect(exception, isNotNull);
      });

      test('stores the provided message', () {
        const msg = 'Docker daemon is not running';
        const exception = DockerNotAvailableException(message: msg);
        expect(exception.message, equals(msg));
      });

      test('can be instantiated with an empty message', () {
        const exception = DockerNotAvailableException(message: '');
        expect(exception.message, isEmpty);
      });

      test('cause defaults to null when not provided', () {
        const exception =
            DockerNotAvailableException(message: 'no cause');
        expect(exception.cause, isNull);
      });

      test('stores the provided cause', () {
        final cause = Exception('underlying error');
        final exception = DockerNotAvailableException(
          message: 'Docker not found',
          cause: cause,
        );
        expect(exception.cause, same(cause));
      });

      test('cause can be any Object', () {
        const exception = DockerNotAvailableException(
          message: 'test',
          cause: 'string cause',
        );
        expect(exception.cause, equals('string cause'));
      });

      test('can be const-constructed', () {
        const e1 = DockerNotAvailableException(message: 'const');
        const e2 = DockerNotAvailableException(message: 'const');
        expect(identical(e1, e2), isTrue);
      });
    });

    group('implements Exception', () {
      test('is an instance of Exception', () {
        const exception =
            DockerNotAvailableException(message: 'test');
        expect(exception, isA<Exception>());
      });

      test('can be caught as Exception', () {
        expect(
          () => throw const DockerNotAvailableException(message: 'thrown'),
          throwsA(isA<Exception>()),
        );
      });

      test('can be caught as DockerNotAvailableException', () {
        expect(
          () => throw const DockerNotAvailableException(message: 'thrown'),
          throwsA(isA<DockerNotAvailableException>()),
        );
      });

      test('can be caught in a try/catch block', () {
        String? caughtMessage;
        try {
          throw const DockerNotAvailableException(
            message: 'daemon offline',
          );
        } on DockerNotAvailableException catch (e) {
          caughtMessage = e.message;
        }
        expect(caughtMessage, equals('daemon offline'));
      });
    });

    group('toString()', () {
      test('includes the class name', () {
        const exception =
            DockerNotAvailableException(message: 'test');
        expect(exception.toString(), contains('DockerNotAvailableException'));
      });

      test('includes the message', () {
        const message = 'Docker is not installed';
        const exception = DockerNotAvailableException(message: message);
        expect(exception.toString(), contains(message));
      });

      test('returns a non-empty string', () {
        const exception =
            DockerNotAvailableException(message: 'any');
        expect(exception.toString(), isNotEmpty);
      });

      test('formats as "DockerNotAvailableException: <message>"', () {
        const msg = 'daemon not running';
        const exception = DockerNotAvailableException(message: msg);
        expect(
          exception.toString(),
          equals('DockerNotAvailableException: $msg'),
        );
      });
    });

    group('equality and identity', () {
      test('two instances with the same message are distinct', () {
        const e1 = DockerNotAvailableException(message: 'same');
        final e2 = DockerNotAvailableException(message: 'same');
        expect(identical(e1, e2), isFalse);
      });
    });
  });

  group('DockerExecutionException', () {
    group('construction', () {
      test('can be instantiated with required fields', () {
        const exception = DockerExecutionException(
          message: 'container failed',
          exitCode: 125,
        );
        expect(exception, isNotNull);
      });

      test('stores the provided message', () {
        const msg = 'Docker daemon error';
        const exception = DockerExecutionException(
          message: msg,
          exitCode: 1,
        );
        expect(exception.message, equals(msg));
      });

      test('stores the provided exitCode', () {
        const exception = DockerExecutionException(
          message: 'test',
          exitCode: 125,
        );
        expect(exception.exitCode, equals(125));
      });

      test('stderr defaults to empty string when not provided', () {
        const exception = DockerExecutionException(
          message: 'test',
          exitCode: 1,
        );
        expect(exception.stderr, isEmpty);
      });

      test('stores the provided stderr', () {
        const stderrOutput = 'Error: image not found';
        const exception = DockerExecutionException(
          message: 'test',
          exitCode: 1,
          stderr: stderrOutput,
        );
        expect(exception.stderr, equals(stderrOutput));
      });

      test('can be instantiated with an empty message', () {
        const exception = DockerExecutionException(
          message: '',
          exitCode: 0,
        );
        expect(exception.message, isEmpty);
      });

      test('stores zero exitCode', () {
        const exception = DockerExecutionException(
          message: 'test',
          exitCode: 0,
        );
        expect(exception.exitCode, equals(0));
      });

      test('stores negative exitCode', () {
        const exception = DockerExecutionException(
          message: 'killed',
          exitCode: -9,
        );
        expect(exception.exitCode, equals(-9));
      });

      test('stores large exitCode', () {
        const exception = DockerExecutionException(
          message: 'test',
          exitCode: 255,
        );
        expect(exception.exitCode, equals(255));
      });

      test('can be const-constructed', () {
        const e1 = DockerExecutionException(
          message: 'const',
          exitCode: 1,
        );
        const e2 = DockerExecutionException(
          message: 'const',
          exitCode: 1,
        );
        expect(identical(e1, e2), isTrue);
      });

      test('stderr can contain multiline output', () {
        const multilineStderr = 'line1\nline2\nline3';
        const exception = DockerExecutionException(
          message: 'test',
          exitCode: 1,
          stderr: multilineStderr,
        );
        expect(exception.stderr, equals(multilineStderr));
      });
    });

    group('implements Exception', () {
      test('is an instance of Exception', () {
        const exception = DockerExecutionException(
          message: 'test',
          exitCode: 1,
        );
        expect(exception, isA<Exception>());
      });

      test('can be caught as Exception', () {
        expect(
          () => throw const DockerExecutionException(
            message: 'thrown',
            exitCode: 1,
          ),
          throwsA(isA<Exception>()),
        );
      });

      test('can be caught as DockerExecutionException', () {
        expect(
          () => throw const DockerExecutionException(
            message: 'thrown',
            exitCode: 1,
          ),
          throwsA(isA<DockerExecutionException>()),
        );
      });

      test('can be caught in a try/catch block', () {
        int? caughtExitCode;
        try {
          throw const DockerExecutionException(
            message: 'test',
            exitCode: 125,
          );
        } on DockerExecutionException catch (e) {
          caughtExitCode = e.exitCode;
        }
        expect(caughtExitCode, equals(125));
      });
    });

    group('toString()', () {
      test('includes the class name', () {
        const exception = DockerExecutionException(
          message: 'test',
          exitCode: 1,
        );
        expect(exception.toString(), contains('DockerExecutionException'));
      });

      test('includes the message', () {
        const msg = 'image pull failed';
        const exception = DockerExecutionException(
          message: msg,
          exitCode: 1,
        );
        expect(exception.toString(), contains(msg));
      });

      test('includes the exitCode', () {
        const exception = DockerExecutionException(
          message: 'test',
          exitCode: 125,
        );
        expect(exception.toString(), contains('125'));
      });

      test('returns a non-empty string', () {
        const exception = DockerExecutionException(
          message: 'any',
          exitCode: 0,
        );
        expect(exception.toString(), isNotEmpty);
      });

      test('formats as "DockerExecutionException: <message> (exitCode=<n>)"',
          () {
        const msg = 'container creation failed';
        const code = 125;
        const exception = DockerExecutionException(
          message: msg,
          exitCode: code,
        );
        expect(
          exception.toString(),
          equals('DockerExecutionException: $msg (exitCode=$code)'),
        );
      });
    });

    group('equality and identity', () {
      test('two instances with the same fields are distinct objects', () {
        const e1 = DockerExecutionException(
          message: 'same',
          exitCode: 1,
          stderr: 'err',
        );
        final e2 = DockerExecutionException(
          message: 'same',
          exitCode: 1,
          stderr: 'err',
        );
        expect(identical(e1, e2), isFalse);
      });
    });
  });

  group('Docker exceptions hierarchy', () {
    test(
        'DockerNotAvailableException and DockerExecutionException '
        'are independent types', () {
      const notAvail =
          DockerNotAvailableException(message: 'not running');
      const execErr = DockerExecutionException(
        message: 'failed',
        exitCode: 1,
      );
      expect(notAvail, isNot(isA<DockerExecutionException>()));
      expect(execErr, isNot(isA<DockerNotAvailableException>()));
    });

    test('both implement Exception', () {
      const notAvail =
          DockerNotAvailableException(message: 'test');
      const execErr = DockerExecutionException(
        message: 'test',
        exitCode: 1,
      );
      expect(notAvail, isA<Exception>());
      expect(execErr, isA<Exception>());
    });
  });
}
