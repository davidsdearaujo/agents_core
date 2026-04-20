import 'dart:async';
import 'dart:io';

import 'package:agents_core/agents_core.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// A logger that records all log calls for verification.
class _RecordingLogger extends Logger {
  final List<({LogLevel level, String message})> entries = [];

  @override
  LogLevel get level => LogLevel.debug;

  @override
  void debug(String message) =>
      entries.add((level: LogLevel.debug, message: message));

  @override
  void info(String message) =>
      entries.add((level: LogLevel.info, message: message));

  @override
  void warn(String message) =>
      entries.add((level: LogLevel.warn, message: message));

  @override
  void error(String message) =>
      entries.add((level: LogLevel.error, message: message));

  List<String> messagesAt(LogLevel level) =>
      entries.where((e) => e.level == level).map((e) => e.message).toList();
}

void main() {
  // =========================================================================
  // DockerRunResult
  // =========================================================================
  group('DockerRunResult', () {
    group('construction', () {
      test('can be instantiated with all required fields', () {
        const result = DockerRunResult(
          stdout: 'output',
          stderr: '',
          exitCode: 0,
        );
        expect(result, isNotNull);
      });

      test('stores stdout', () {
        const result = DockerRunResult(
          stdout: 'hello world',
          stderr: '',
          exitCode: 0,
        );
        expect(result.stdout, equals('hello world'));
      });

      test('stores stderr', () {
        const result = DockerRunResult(
          stdout: '',
          stderr: 'error output',
          exitCode: 0,
        );
        expect(result.stderr, equals('error output'));
      });

      test('stores exitCode', () {
        const result = DockerRunResult(stdout: '', stderr: '', exitCode: 42);
        expect(result.exitCode, equals(42));
      });

      test('stores zero exitCode for success', () {
        const result = DockerRunResult(stdout: '', stderr: '', exitCode: 0);
        expect(result.exitCode, equals(0));
      });

      test('stores non-zero exitCode for failure', () {
        const result = DockerRunResult(
          stdout: '',
          stderr: 'script error',
          exitCode: 1,
        );
        expect(result.exitCode, equals(1));
      });

      test('can hold empty strings for stdout and stderr', () {
        const result = DockerRunResult(stdout: '', stderr: '', exitCode: 0);
        expect(result.stdout, isEmpty);
        expect(result.stderr, isEmpty);
      });

      test('can hold multiline stdout', () {
        const multiline = 'line1\nline2\nline3';
        const result = DockerRunResult(
          stdout: multiline,
          stderr: '',
          exitCode: 0,
        );
        expect(result.stdout, equals(multiline));
      });

      test('can hold multiline stderr', () {
        const multiline = 'err1\nerr2';
        const result = DockerRunResult(
          stdout: '',
          stderr: multiline,
          exitCode: 0,
        );
        expect(result.stderr, equals(multiline));
      });

      test('can hold both stdout and stderr simultaneously', () {
        const result = DockerRunResult(
          stdout: 'output',
          stderr: 'warning',
          exitCode: 0,
        );
        expect(result.stdout, equals('output'));
        expect(result.stderr, equals('warning'));
      });

      test('can be const-constructed', () {
        const r1 = DockerRunResult(stdout: 'a', stderr: 'b', exitCode: 0);
        const r2 = DockerRunResult(stdout: 'a', stderr: 'b', exitCode: 0);
        expect(identical(r1, r2), isTrue);
      });

      test('stores exit code 125 (Docker daemon error)', () {
        const result = DockerRunResult(
          stdout: '',
          stderr: 'daemon error',
          exitCode: 125,
        );
        expect(result.exitCode, equals(125));
      });

      test('stores exit code 126 (command cannot be invoked)', () {
        const result = DockerRunResult(
          stdout: '',
          stderr: 'permission denied',
          exitCode: 126,
        );
        expect(result.exitCode, equals(126));
      });

      test('stores exit code 127 (command not found)', () {
        const result = DockerRunResult(
          stdout: '',
          stderr: 'not found',
          exitCode: 127,
        );
        expect(result.exitCode, equals(127));
      });

      test('stores exit code 137 (killed / OOM)', () {
        const result = DockerRunResult(stdout: '', stderr: '', exitCode: 137);
        expect(result.exitCode, equals(137));
      });
    });
  });

  // =========================================================================
  // DockerClient — construction
  // =========================================================================
  group('DockerClient', () {
    group('construction', () {
      test('can be instantiated with no arguments', () {
        final client = DockerClient();
        expect(client, isNotNull);
      });

      test('dockerPath defaults to "docker"', () {
        final client = DockerClient();
        expect(client.dockerPath, equals('docker'));
      });

      test('accepts a custom dockerPath', () {
        final client = DockerClient(dockerPath: '/usr/local/bin/docker');
        expect(client.dockerPath, equals('/usr/local/bin/docker'));
      });

      test('accepts a custom logger', () {
        final logger = _RecordingLogger();
        final client = DockerClient(logger: logger);
        expect(client, isNotNull);
        // Logger is private so we verify it works indirectly.
      });

      test('uses SilentLogger when no logger is provided', () {
        // Simply verifies construction succeeds without a logger.
        final client = DockerClient();
        expect(client, isNotNull);
      });
    });

    // =========================================================================
    // DockerClient.isAvailable()
    // =========================================================================
    group('isAvailable()', () {
      test(
        'returns false when dockerPath points to a non-existent binary',
        () async {
          final client = DockerClient(
            dockerPath: '/non/existent/path/to/docker_binary_xyz_000',
          );
          final available = await client.isAvailable();
          expect(available, isFalse);
        },
      );

      test('returns a Future<bool>', () {
        final client = DockerClient(dockerPath: '/non/existent/docker_bin');
        expect(client.isAvailable(), isA<Future<bool>>());
      });
    });

    // =========================================================================
    // DockerClient.isImageAvailable()
    // =========================================================================
    group('isImageAvailable()', () {
      test('returns false when dockerPath is invalid', () async {
        final client = DockerClient(dockerPath: '/non/existent/docker_xyz_000');
        final available = await client.isImageAvailable('python:3.12-slim');
        expect(available, isFalse);
      });

      test('returns a Future<bool>', () {
        final client = DockerClient(dockerPath: '/non/existent/docker_bin');
        expect(client.isImageAvailable('any-image'), isA<Future<bool>>());
      });

      test('logs debug message when checking image', () async {
        final logger = _RecordingLogger();
        final client = DockerClient(
          dockerPath: '/non/existent/docker_xyz_000',
          logger: logger,
        );
        await client.isImageAvailable('myimage:latest');
        final debugMessages = logger.messagesAt(LogLevel.debug);
        expect(
          debugMessages.any((m) => m.contains('myimage:latest')),
          isTrue,
          reason: 'Should log a debug message containing the image name',
        );
      });
    });

    // =========================================================================
    // DockerClient.runContainer()
    // =========================================================================
    group('runContainer()', () {
      test(
        'throws DockerNotAvailableException when docker binary does not exist',
        () async {
          final client = DockerClient(
            dockerPath: '/non/existent/docker_xyz_000',
          );
          expect(
            () => client.runContainer(
              image: 'python:3.12-slim',
              command: ['python', '-c', 'print("hello")'],
            ),
            throwsA(isA<DockerNotAvailableException>()),
          );
        },
      );

      test(
        'DockerNotAvailableException has descriptive message when docker not found',
        () async {
          final client = DockerClient(
            dockerPath: '/non/existent/docker_xyz_000',
          );
          try {
            await client.runContainer(
              image: 'alpine',
              command: ['echo', 'test'],
            );
            fail('Expected DockerNotAvailableException');
          } on DockerNotAvailableException catch (e) {
            expect(e.message, isNotEmpty);
            expect(e.cause, isNotNull);
          }
        },
      );

      test('default timeout is 60 seconds', () async {
        // We verify that the API accepts no timeout parameter
        // (the default Duration(seconds: 60) is used internally).
        final client = DockerClient(dockerPath: '/non/existent/docker_xyz_000');
        // This will throw DockerNotAvailableException, but it proves
        // the call signature works without specifying timeout.
        expect(
          () => client.runContainer(image: 'alpine', command: ['echo', 'ok']),
          throwsA(isA<DockerNotAvailableException>()),
        );
      });

      test('accepts custom timeout', () async {
        final client = DockerClient(dockerPath: '/non/existent/docker_xyz_000');
        expect(
          () => client.runContainer(
            image: 'alpine',
            command: ['echo', 'ok'],
            timeout: const Duration(seconds: 10),
          ),
          throwsA(isA<DockerNotAvailableException>()),
        );
      });

      test('accepts volumes parameter', () async {
        final client = DockerClient(dockerPath: '/non/existent/docker_xyz_000');
        expect(
          () => client.runContainer(
            image: 'alpine',
            command: ['ls'],
            volumes: {'/tmp/host': '/container/path'},
          ),
          throwsA(isA<DockerNotAvailableException>()),
        );
      });

      test('accepts workingDir parameter', () async {
        final client = DockerClient(dockerPath: '/non/existent/docker_xyz_000');
        expect(
          () => client.runContainer(
            image: 'alpine',
            command: ['pwd'],
            workingDir: '/workspace',
          ),
          throwsA(isA<DockerNotAvailableException>()),
        );
      });

      test('accepts environment parameter', () async {
        final client = DockerClient(dockerPath: '/non/existent/docker_xyz_000');
        expect(
          () => client.runContainer(
            image: 'alpine',
            command: ['env'],
            environment: {'FOO': 'bar'},
          ),
          throwsA(isA<DockerNotAvailableException>()),
        );
      });

      test('logs debug messages about the run', () async {
        final logger = _RecordingLogger();
        final client = DockerClient(
          dockerPath: '/non/existent/docker_xyz_000',
          logger: logger,
        );
        try {
          await client.runContainer(
            image: 'python:3.12-slim',
            command: ['python', '-c', 'print(1)'],
          );
        } on DockerNotAvailableException {
          // expected
        }
        final debugMessages = logger.messagesAt(LogLevel.debug);
        expect(
          debugMessages.any((m) => m.contains('python:3.12-slim')),
          isTrue,
          reason: 'Should log a debug message containing the image name',
        );
      });

      test('returns Future<DockerRunResult>', () async {
        final dir = await Directory.systemTemp.createTemp('docker_ret_type_');
        final stub = File('${dir.path}/docker');
        await stub.writeAsString('#!/bin/sh\nexit 0\n');
        await Process.run('chmod', ['+x', stub.path]);

        final client = DockerClient(dockerPath: stub.path);
        final future = client.runContainer(image: 'alpine', command: ['echo']);
        expect(future, isA<Future<DockerRunResult>>());
        final result = await future;
        expect(result, isA<DockerRunResult>());
      });
    });

    // =========================================================================
    // DockerClient.runContainer() with a real shell script (echo)
    // =========================================================================
    group('runContainer() with echo-based docker stub', () {
      late String stubPath;

      setUpAll(() async {
        // Create a shell script that mimics a minimal "docker" CLI
        // for testing: it simply echoes arguments to stdout.
        final dir = await Directory.systemTemp.createTemp('docker_stub_');
        final stub = File('${dir.path}/docker');
        await stub.writeAsString(
          '#!/bin/sh\n'
          'echo "stub-stdout"\n'
          'echo "stub-stderr" >&2\n'
          'exit 0\n',
        );
        // Make executable
        await Process.run('chmod', ['+x', stub.path]);
        stubPath = stub.path;
      });

      test('returns DockerRunResult on successful docker run', () async {
        final client = DockerClient(dockerPath: stubPath);
        final result = await client.runContainer(
          image: 'test-image',
          command: ['echo', 'hello'],
        );
        expect(result, isA<DockerRunResult>());
        expect(result.exitCode, equals(0));
        expect(result.stdout, contains('stub-stdout'));
        expect(result.stderr, contains('stub-stderr'));
      });

      test('trims trailing whitespace from stdout', () async {
        final client = DockerClient(dockerPath: stubPath);
        final result = await client.runContainer(
          image: 'test-image',
          command: ['echo'],
        );
        // Our stub emits "stub-stdout\n" so trimRight removes trailing \n
        expect(result.stdout, isNot(endsWith('\n')));
      });

      test('trims trailing whitespace from stderr', () async {
        final client = DockerClient(dockerPath: stubPath);
        final result = await client.runContainer(
          image: 'test-image',
          command: ['echo'],
        );
        expect(result.stderr, isNot(endsWith('\n')));
      });
    });

    group('runContainer() with exit code 125 stub', () {
      late String stubPath;

      setUpAll(() async {
        final dir = await Directory.systemTemp.createTemp('docker_125_');
        final stub = File('${dir.path}/docker');
        await stub.writeAsString(
          '#!/bin/sh\n'
          'echo "daemon error" >&2\n'
          'exit 125\n',
        );
        await Process.run('chmod', ['+x', stub.path]);
        stubPath = stub.path;
      });

      test('throws DockerExecutionException on exit code 125', () async {
        final client = DockerClient(dockerPath: stubPath);
        expect(
          () => client.runContainer(image: 'bad-image', command: ['echo']),
          throwsA(isA<DockerExecutionException>()),
        );
      });

      test('DockerExecutionException on exit 125 has exitCode 125', () async {
        final client = DockerClient(dockerPath: stubPath);
        try {
          await client.runContainer(image: 'bad-image', command: ['echo']);
          fail('Expected DockerExecutionException');
        } on DockerExecutionException catch (e) {
          expect(e.exitCode, equals(125));
        }
      });

      test('DockerExecutionException on exit 125 has stderr', () async {
        final client = DockerClient(dockerPath: stubPath);
        try {
          await client.runContainer(image: 'bad-image', command: ['echo']);
          fail('Expected DockerExecutionException');
        } on DockerExecutionException catch (e) {
          expect(e.stderr, contains('daemon error'));
        }
      });

      test(
        'DockerExecutionException on exit 125 has descriptive message',
        () async {
          final client = DockerClient(dockerPath: stubPath);
          try {
            await client.runContainer(
              image: 'my-broken-image:latest',
              command: ['echo'],
            );
            fail('Expected DockerExecutionException');
          } on DockerExecutionException catch (e) {
            expect(e.message, isNotEmpty);
            expect(e.message, contains('my-broken-image:latest'));
          }
        },
      );
    });

    group('runContainer() with non-125 non-zero exit code stub', () {
      late String stubPath;

      setUpAll(() async {
        final dir = await Directory.systemTemp.createTemp('docker_app_err_');
        final stub = File('${dir.path}/docker');
        await stub.writeAsString(
          '#!/bin/sh\n'
          'echo "app output"\n'
          'echo "app error" >&2\n'
          'exit 1\n',
        );
        await Process.run('chmod', ['+x', stub.path]);
        stubPath = stub.path;
      });

      test(
        'returns DockerRunResult (not exception) for non-125 non-zero exit codes',
        () async {
          final client = DockerClient(dockerPath: stubPath);
          // Non-125 exits represent application-level errors inside the
          // container and should be returned, not thrown.
          final result = await client.runContainer(
            image: 'python:3.12-slim',
            command: ['python', '-c', 'raise Exception()'],
          );
          expect(result, isA<DockerRunResult>());
          expect(result.exitCode, equals(1));
          expect(result.stdout, contains('app output'));
          expect(result.stderr, contains('app error'));
        },
      );
    });

    group('runContainer() command construction', () {
      // Uses a stub that prints all its arguments so we can verify
      // the exact docker CLI arguments that DockerClient builds.
      late String stubPath;

      setUpAll(() async {
        final dir = await Directory.systemTemp.createTemp('docker_args_');
        final stub = File('${dir.path}/docker');
        // Print all arguments one per line so tests can inspect them.
        await stub.writeAsString(
          '#!/bin/sh\n'
          'for arg in "\$@"; do\n'
          '  echo "\$arg"\n'
          'done\n'
          'exit 0\n',
        );
        await Process.run('chmod', ['+x', stub.path]);
        stubPath = stub.path;
      });

      test('includes --rm flag', () async {
        final client = DockerClient(dockerPath: stubPath);
        final result = await client.runContainer(
          image: 'alpine',
          command: ['echo'],
        );
        expect(result.stdout, contains('--rm'));
      });

      test('includes --network=none flag', () async {
        final client = DockerClient(dockerPath: stubPath);
        final result = await client.runContainer(
          image: 'alpine',
          command: ['echo'],
        );
        expect(result.stdout, contains('--network=none'));
      });

      test('includes run subcommand', () async {
        final client = DockerClient(dockerPath: stubPath);
        final result = await client.runContainer(
          image: 'alpine',
          command: ['echo'],
        );
        final args = result.stdout.split('\n');
        expect(args.first, equals('run'));
      });

      test('includes volume mount -v flags', () async {
        final client = DockerClient(dockerPath: stubPath);
        final result = await client.runContainer(
          image: 'alpine',
          command: ['ls'],
          volumes: {'/host/path': '/container/path'},
        );
        final args = result.stdout.split('\n');
        expect(args, contains('-v'));
        expect(args, contains('/host/path:/container/path'));
      });

      test('includes multiple volume mounts', () async {
        final client = DockerClient(dockerPath: stubPath);
        final result = await client.runContainer(
          image: 'alpine',
          command: ['ls'],
          volumes: {'/host/a': '/container/a', '/host/b': '/container/b'},
        );
        final args = result.stdout.split('\n');
        expect(args, contains('/host/a:/container/a'));
        expect(args, contains('/host/b:/container/b'));
      });

      test('includes --workdir when workingDir is set', () async {
        final client = DockerClient(dockerPath: stubPath);
        final result = await client.runContainer(
          image: 'alpine',
          command: ['pwd'],
          workingDir: '/workspace',
        );
        final args = result.stdout.split('\n');
        expect(args, contains('--workdir'));
        expect(args, contains('/workspace'));
      });

      test('omits --workdir when workingDir is null', () async {
        final client = DockerClient(dockerPath: stubPath);
        final result = await client.runContainer(
          image: 'alpine',
          command: ['pwd'],
        );
        final args = result.stdout.split('\n');
        expect(args, isNot(contains('--workdir')));
      });

      test('includes --env for environment variables', () async {
        final client = DockerClient(dockerPath: stubPath);
        final result = await client.runContainer(
          image: 'alpine',
          command: ['env'],
          environment: {'MY_VAR': 'my_value'},
        );
        final args = result.stdout.split('\n');
        expect(args, contains('--env'));
        expect(args, contains('MY_VAR=my_value'));
      });

      test('includes multiple --env flags', () async {
        final client = DockerClient(dockerPath: stubPath);
        final result = await client.runContainer(
          image: 'alpine',
          command: ['env'],
          environment: {'A': '1', 'B': '2'},
        );
        final args = result.stdout.split('\n');
        expect(args, contains('A=1'));
        expect(args, contains('B=2'));
      });

      test('image name appears in args', () async {
        final client = DockerClient(dockerPath: stubPath);
        final result = await client.runContainer(
          image: 'python:3.12-slim',
          command: ['echo'],
        );
        final args = result.stdout.split('\n');
        expect(args, contains('python:3.12-slim'));
      });

      test('command appears after image name', () async {
        final client = DockerClient(dockerPath: stubPath);
        final result = await client.runContainer(
          image: 'alpine',
          command: ['python', '-c', 'print("hi")'],
        );
        final args = result.stdout.split('\n');
        final imageIdx = args.indexOf('alpine');
        final pythonIdx = args.indexOf('python');
        expect(pythonIdx, greaterThan(imageIdx));
        expect(args, contains('-c'));
        expect(args, contains('print("hi")'));
      });

      test('empty volumes map produces no -v flags', () async {
        final client = DockerClient(dockerPath: stubPath);
        final result = await client.runContainer(
          image: 'alpine',
          command: ['echo'],
          volumes: const {},
        );
        final args = result.stdout.split('\n');
        expect(args, isNot(contains('-v')));
      });

      test('empty environment map produces no --env flags', () async {
        final client = DockerClient(dockerPath: stubPath);
        final result = await client.runContainer(
          image: 'alpine',
          command: ['echo'],
          environment: const {},
        );
        final args = result.stdout.split('\n');
        expect(args, isNot(contains('--env')));
      });
    });

    // =========================================================================
    // DockerClient.pullImage()
    // =========================================================================
    group('pullImage()', () {
      test(
        'throws DockerNotAvailableException when docker binary missing',
        () async {
          final client = DockerClient(
            dockerPath: '/non/existent/docker_xyz_000',
          );
          expect(
            () => client.pullImage('alpine:latest'),
            throwsA(isA<DockerNotAvailableException>()),
          );
        },
      );

      test('succeeds when stub exits with 0', () async {
        final dir = await Directory.systemTemp.createTemp('docker_pull_ok_');
        final stub = File('${dir.path}/docker');
        await stub.writeAsString('#!/bin/sh\nexit 0\n');
        await Process.run('chmod', ['+x', stub.path]);

        final client = DockerClient(dockerPath: stub.path);
        // Should complete without throwing.
        await client.pullImage('alpine:latest');
      });

      test(
        'throws DockerExecutionException when pull fails (non-zero exit)',
        () async {
          final dir = await Directory.systemTemp.createTemp(
            'docker_pull_fail_',
          );
          final stub = File('${dir.path}/docker');
          await stub.writeAsString(
            '#!/bin/sh\n'
            'echo "Error: manifest not found" >&2\n'
            'exit 1\n',
          );
          await Process.run('chmod', ['+x', stub.path]);

          final client = DockerClient(dockerPath: stub.path);
          expect(
            () => client.pullImage('nonexistent-image:v999'),
            throwsA(isA<DockerExecutionException>()),
          );
        },
      );

      test(
        'DockerExecutionException from pullImage has stderr and exitCode',
        () async {
          final dir = await Directory.systemTemp.createTemp('docker_pull_err_');
          final stub = File('${dir.path}/docker');
          await stub.writeAsString(
            '#!/bin/sh\n'
            'echo "pull error details" >&2\n'
            'exit 1\n',
          );
          await Process.run('chmod', ['+x', stub.path]);

          final client = DockerClient(dockerPath: stub.path);
          try {
            await client.pullImage('bad-image');
            fail('Expected DockerExecutionException');
          } on DockerExecutionException catch (e) {
            expect(e.exitCode, equals(1));
            expect(e.stderr, contains('pull error details'));
            expect(e.message, contains('bad-image'));
          }
        },
      );

      test('logs info messages during pull', () async {
        final dir = await Directory.systemTemp.createTemp('docker_pull_log_');
        final stub = File('${dir.path}/docker');
        await stub.writeAsString('#!/bin/sh\nexit 0\n');
        await Process.run('chmod', ['+x', stub.path]);

        final logger = _RecordingLogger();
        final client = DockerClient(dockerPath: stub.path, logger: logger);
        await client.pullImage('myimage:v1');

        final infoMessages = logger.messagesAt(LogLevel.info);
        expect(
          infoMessages.any((m) => m.contains('myimage:v1')),
          isTrue,
          reason: 'Should log info containing the image name',
        );
      });
    });

    // =========================================================================
    // DockerClient logging integration
    // =========================================================================
    group('logging', () {
      test('uses SilentLogger by default (no output)', () async {
        // This test just verifies construction with no logger doesn't
        // cause errors when methods log.
        final client = DockerClient(dockerPath: '/non/existent/docker_xyz_000');
        try {
          await client.runContainer(image: 'alpine', command: ['echo']);
        } on DockerNotAvailableException {
          // expected
        }
        // No exception from logging means SilentLogger works.
      });

      test('debug log includes docker command details', () async {
        final dir = await Directory.systemTemp.createTemp('docker_dbg_');
        final stub = File('${dir.path}/docker');
        await stub.writeAsString('#!/bin/sh\nexit 0\n');
        await Process.run('chmod', ['+x', stub.path]);

        final logger = _RecordingLogger();
        final client = DockerClient(dockerPath: stub.path, logger: logger);
        await client.runContainer(
          image: 'alpine:3.18',
          command: ['sh', '-c', 'echo hi'],
        );

        final debugMessages = logger.messagesAt(LogLevel.debug);
        // Should log the full docker command
        expect(debugMessages.any((m) => m.contains('run')), isTrue);
        expect(debugMessages.any((m) => m.contains('alpine:3.18')), isTrue);
      });

      test('debug log includes exitCode after successful run', () async {
        final dir = await Directory.systemTemp.createTemp('docker_dbg2_');
        final stub = File('${dir.path}/docker');
        await stub.writeAsString('#!/bin/sh\nexit 0\n');
        await Process.run('chmod', ['+x', stub.path]);

        final logger = _RecordingLogger();
        final client = DockerClient(dockerPath: stub.path, logger: logger);
        await client.runContainer(image: 'alpine', command: ['echo']);

        final debugMessages = logger.messagesAt(LogLevel.debug);
        expect(
          debugMessages.any((m) => m.contains('exitCode=0')),
          isTrue,
          reason: 'Should log debug message with exitCode',
        );
      });
    });

    // =========================================================================
    // DockerClient.isAvailable() with stubs
    // =========================================================================
    group('isAvailable() with stubs', () {
      test('returns true when docker info succeeds (exit code 0)', () async {
        final dir = await Directory.systemTemp.createTemp('docker_avail_');
        final stub = File('${dir.path}/docker');
        await stub.writeAsString('#!/bin/sh\nexit 0\n');
        await Process.run('chmod', ['+x', stub.path]);

        final client = DockerClient(dockerPath: stub.path);
        expect(await client.isAvailable(), isTrue);
      });

      test('returns false when docker info fails (exit code 1)', () async {
        final dir = await Directory.systemTemp.createTemp('docker_unavail_');
        final stub = File('${dir.path}/docker');
        await stub.writeAsString('#!/bin/sh\nexit 1\n');
        await Process.run('chmod', ['+x', stub.path]);

        final client = DockerClient(dockerPath: stub.path);
        expect(await client.isAvailable(), isFalse);
      });
    });

    // =========================================================================
    // DockerClient.isImageAvailable() with stubs
    // =========================================================================
    group('isImageAvailable() with stubs', () {
      test('returns true when docker image inspect succeeds', () async {
        final dir = await Directory.systemTemp.createTemp('docker_img_ok_');
        final stub = File('${dir.path}/docker');
        await stub.writeAsString('#!/bin/sh\nexit 0\n');
        await Process.run('chmod', ['+x', stub.path]);

        final client = DockerClient(dockerPath: stub.path);
        expect(await client.isImageAvailable('alpine:latest'), isTrue);
      });

      test('returns false when docker image inspect fails', () async {
        final dir = await Directory.systemTemp.createTemp('docker_img_fail_');
        final stub = File('${dir.path}/docker');
        await stub.writeAsString('#!/bin/sh\nexit 1\n');
        await Process.run('chmod', ['+x', stub.path]);

        final client = DockerClient(dockerPath: stub.path);
        expect(await client.isImageAvailable('nonexistent:v999'), isFalse);
      });
    });
  });
}
