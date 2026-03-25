// ignore_for_file: avoid_implementing_value_types

import 'dart:io';

import 'package:agents_core/agents_core.dart';
import 'package:test/test.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Fake DockerClient
// ─────────────────────────────────────────────────────────────────────────────

/// A fake [DockerClient] that never invokes a real process.
///
/// Records every [runContainer] call so tests can assert on the
/// exact arguments that were passed.
class _FakeDockerClient extends DockerClient {
  _FakeDockerClient({DockerRunResult? runResult, Object? throwOnRun})
    : _runResult =
          runResult ??
          const DockerRunResult(stdout: '', stderr: '', exitCode: 0),
      _throwOnRun = throwOnRun,
      super(dockerPath: '/fake/docker');

  final DockerRunResult _runResult;
  final Object? _throwOnRun;

  int runCount = 0;
  String? lastImage;
  List<String>? lastCommand;
  Map<String, String>? lastVolumes;
  String? lastWorkingDir;
  Duration? lastTimeout;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<bool> isImageAvailable(String image) async => true;

  @override
  Future<void> pullImage(String image) async {}

  @override
  Future<DockerRunResult> runContainer({
    required String image,
    required List<String> command,
    Map<String, String> volumes = const {},
    String? workingDir,
    Duration timeout = const Duration(seconds: 60),
    Map<String, String> environment = const {},
  }) async {
    runCount++;
    lastImage = image;
    lastCommand = List<String>.from(command);
    lastVolumes = Map<String, String>.from(volumes);
    lastWorkingDir = workingDir;
    lastTimeout = timeout;
    if (_throwOnRun != null) throw _throwOnRun;
    return _runResult;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

/// Creates a [FileContext] backed by a fresh temp directory.
///
/// Returns a record with the context and the temp [Directory] so the
/// caller can clean up with [tearDown].
({FileContext ctx, Directory dir}) _tempContext() {
  final dir = Directory.systemTemp.createTempSync('exec_py_test_');
  final ctx = FileContext(workspacePath: dir.path);
  return (ctx: ctx, dir: dir);
}

// ─────────────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  // ── executePythonToolDefinition ────────────────────────────────────────────

  group('executePythonToolDefinition', () {
    test('name is "execute_python"', () {
      expect(executePythonToolDefinition.name, 'execute_python');
    });

    test('description is non-empty', () {
      expect(executePythonToolDefinition.description, isNotEmpty);
    });

    test('"code" parameter is required', () {
      final required =
          executePythonToolDefinition.parameters['required'] as List;
      expect(required, contains('code'));
    });

    test('"requirements" parameter is optional (not in required list)', () {
      final required =
          executePythonToolDefinition.parameters['required'] as List;
      expect(required, isNot(contains('requirements')));
    });

    test('"code" parameter has type "string"', () {
      final props =
          executePythonToolDefinition.parameters['properties']
              as Map<String, dynamic>;
      expect(props['code']!['type'], 'string');
    });

    test('"requirements" parameter has type "array"', () {
      final props =
          executePythonToolDefinition.parameters['properties']
              as Map<String, dynamic>;
      expect(props['requirements']!['type'], 'array');
    });

    test('toJson() wraps under "function" key with type "function"', () {
      final json = executePythonToolDefinition.toJson();
      expect(json['type'], 'function');
      final fn = json['function'] as Map<String, dynamic>;
      expect(fn['name'], 'execute_python');
    });
  });

  // ── Handler — input validation ─────────────────────────────────────────────

  group('createExecutePythonHandler — input validation', () {
    late Directory tmpDir;
    late FileContext ctx;

    setUp(() {
      final result = _tempContext();
      tmpDir = result.dir;
      ctx = result.ctx;
    });

    tearDown(() => tmpDir.deleteSync(recursive: true));

    test('returns error string when "code" key is missing', () async {
      final handler = createExecutePythonHandler(
        context: ctx,
        dockerClient: _FakeDockerClient(),
      );
      final output = await handler(<String, dynamic>{});
      expect(output, contains('Error'));
      expect(output, contains('code'));
    });

    test('returns error string for empty "code"', () async {
      final handler = createExecutePythonHandler(
        context: ctx,
        dockerClient: _FakeDockerClient(),
      );
      final output = await handler({'code': ''});
      expect(output, contains('Error'));
    });

    test('returns error string for whitespace-only "code"', () async {
      final handler = createExecutePythonHandler(
        context: ctx,
        dockerClient: _FakeDockerClient(),
      );
      final output = await handler({'code': '   \n\t  '});
      expect(output, contains('Error'));
    });

    test('does NOT call docker when code is empty', () async {
      final fakeDocker = _FakeDockerClient();
      final handler = createExecutePythonHandler(
        context: ctx,
        dockerClient: fakeDocker,
      );
      await handler({'code': ''});
      expect(fakeDocker.runCount, 0);
    });
  });

  // ── Handler — command construction ────────────────────────────────────────

  group('createExecutePythonHandler — command construction', () {
    late Directory tmpDir;
    late FileContext ctx;

    setUp(() {
      final result = _tempContext();
      tmpDir = result.dir;
      ctx = result.ctx;
    });

    tearDown(() => tmpDir.deleteSync(recursive: true));

    test('without requirements: command starts with "python"', () async {
      final fakeDocker = _FakeDockerClient();
      final handler = createExecutePythonHandler(
        context: ctx,
        dockerClient: fakeDocker,
      );
      await handler({'code': 'print("hello")'});

      expect(fakeDocker.lastCommand, isNotNull);
      expect(fakeDocker.lastCommand!.first, 'python');
    });

    test(
      'without requirements: script path is /workspace/.tmp_exec_*.py',
      () async {
        final fakeDocker = _FakeDockerClient();
        final handler = createExecutePythonHandler(
          context: ctx,
          dockerClient: fakeDocker,
        );
        await handler({'code': 'print("hello")'});

        final scriptArg = fakeDocker.lastCommand![1];
        expect(scriptArg, startsWith('/workspace/.tmp_exec_'));
        expect(scriptArg, endsWith('.py'));
      },
    );

    test('without requirements: command has exactly 2 elements', () async {
      final fakeDocker = _FakeDockerClient();
      final handler = createExecutePythonHandler(
        context: ctx,
        dockerClient: fakeDocker,
      );
      await handler({'code': 'x = 1'});
      expect(fakeDocker.lastCommand, hasLength(2));
    });

    test('with requirements: command uses sh -c', () async {
      final fakeDocker = _FakeDockerClient();
      final handler = createExecutePythonHandler(
        context: ctx,
        dockerClient: fakeDocker,
      );
      await handler({
        'code': 'import numpy',
        'requirements': ['numpy'],
      });

      expect(fakeDocker.lastCommand![0], 'sh');
      expect(fakeDocker.lastCommand![1], '-c');
    });

    test('with requirements: sh -c string contains pip install', () async {
      final fakeDocker = _FakeDockerClient();
      final handler = createExecutePythonHandler(
        context: ctx,
        dockerClient: fakeDocker,
      );
      await handler({
        'code': 'import numpy, pandas',
        'requirements': ['numpy', 'pandas==2.1.0'],
      });

      final shCmd = fakeDocker.lastCommand![2];
      expect(shCmd, contains('pip install --quiet'));
      expect(shCmd, contains('numpy'));
      expect(shCmd, contains('pandas==2.1.0'));
    });

    test(
      'with requirements: sh -c string contains python script path',
      () async {
        final fakeDocker = _FakeDockerClient();
        final handler = createExecutePythonHandler(
          context: ctx,
          dockerClient: fakeDocker,
        );
        await handler({
          'code': 'print(1)',
          'requirements': ['requests'],
        });

        final shCmd = fakeDocker.lastCommand![2];
        expect(shCmd, contains('python /workspace/.tmp_exec_'));
        expect(shCmd, contains('.py'));
      },
    );

    test('with requirements: uses && to chain pip and python', () async {
      final fakeDocker = _FakeDockerClient();
      final handler = createExecutePythonHandler(
        context: ctx,
        dockerClient: fakeDocker,
      );
      await handler({
        'code': 'x=1',
        'requirements': ['six'],
      });

      final shCmd = fakeDocker.lastCommand![2];
      expect(shCmd, contains('&&'));
    });

    test('empty requirements list uses direct python command', () async {
      final fakeDocker = _FakeDockerClient();
      final handler = createExecutePythonHandler(
        context: ctx,
        dockerClient: fakeDocker,
      );
      await handler({'code': 'x=1', 'requirements': []});

      expect(fakeDocker.lastCommand!.first, 'python');
    });

    test('requirements as null uses direct python command', () async {
      final fakeDocker = _FakeDockerClient();
      final handler = createExecutePythonHandler(
        context: ctx,
        dockerClient: fakeDocker,
      );
      await handler({'code': 'x=1', 'requirements': null});

      expect(fakeDocker.lastCommand!.first, 'python');
    });

    test('volume maps workspace path to /workspace in container', () async {
      final fakeDocker = _FakeDockerClient();
      final handler = createExecutePythonHandler(
        context: ctx,
        dockerClient: fakeDocker,
      );
      await handler({'code': 'print(1)'});

      expect(fakeDocker.lastVolumes, isNotNull);
      expect(fakeDocker.lastVolumes!.containsKey(ctx.workspacePath), isTrue);
      expect(fakeDocker.lastVolumes![ctx.workspacePath], '/workspace');
    });

    test('workingDir is /workspace', () async {
      final fakeDocker = _FakeDockerClient();
      final handler = createExecutePythonHandler(
        context: ctx,
        dockerClient: fakeDocker,
      );
      await handler({'code': 'print(1)'});

      expect(fakeDocker.lastWorkingDir, '/workspace');
    });

    test('defaults to python:3.12-slim image', () async {
      final fakeDocker = _FakeDockerClient();
      final handler = createExecutePythonHandler(
        context: ctx,
        dockerClient: fakeDocker,
      );
      await handler({'code': 'x = 1'});

      expect(fakeDocker.lastImage, 'python:3.12-slim');
    });

    test('custom image is forwarded to runContainer', () async {
      final fakeDocker = _FakeDockerClient();
      final handler = createExecutePythonHandler(
        context: ctx,
        dockerClient: fakeDocker,
        image: 'python:3.11-alpine',
      );
      await handler({'code': 'x = 1'});

      expect(fakeDocker.lastImage, 'python:3.11-alpine');
    });

    test('custom timeout is forwarded to runContainer', () async {
      final fakeDocker = _FakeDockerClient();
      const customTimeout = Duration(seconds: 30);
      final handler = createExecutePythonHandler(
        context: ctx,
        dockerClient: fakeDocker,
        timeout: customTimeout,
      );
      await handler({'code': 'x = 1'});

      expect(fakeDocker.lastTimeout, customTimeout);
    });

    test('default timeout is 120 seconds', () async {
      final fakeDocker = _FakeDockerClient();
      final handler = createExecutePythonHandler(
        context: ctx,
        dockerClient: fakeDocker,
      );
      await handler({'code': 'x = 1'});

      expect(fakeDocker.lastTimeout, const Duration(seconds: 120));
    });
  });

  // ── Handler — result formatting ───────────────────────────────────────────

  group('createExecutePythonHandler — result formatting', () {
    late Directory tmpDir;
    late FileContext ctx;

    setUp(() {
      final result = _tempContext();
      tmpDir = result.dir;
      ctx = result.ctx;
    });

    tearDown(() => tmpDir.deleteSync(recursive: true));

    test('exit code 0: output contains "[OK] exit_code=0"', () async {
      final handler = createExecutePythonHandler(
        context: ctx,
        dockerClient: _FakeDockerClient(
          runResult: const DockerRunResult(
            stdout: 'hi',
            stderr: '',
            exitCode: 0,
          ),
        ),
      );
      final output = await handler({'code': 'print("hi")'});
      expect(output, contains('[OK] exit_code=0'));
    });

    test('non-zero exit code: output contains "[ERROR] exit_code=N"', () async {
      final handler = createExecutePythonHandler(
        context: ctx,
        dockerClient: _FakeDockerClient(
          runResult: const DockerRunResult(
            stdout: '',
            stderr: 'NameError',
            exitCode: 1,
          ),
        ),
      );
      final output = await handler({'code': 'undefined_var'});
      expect(output, contains('[ERROR] exit_code=1'));
    });

    test('exit code 2: output contains "[ERROR] exit_code=2"', () async {
      final handler = createExecutePythonHandler(
        context: ctx,
        dockerClient: _FakeDockerClient(
          runResult: const DockerRunResult(stdout: '', stderr: '', exitCode: 2),
        ),
      );
      final output = await handler({'code': 'x = 1'});
      expect(output, contains('[ERROR] exit_code=2'));
    });

    test('stdout is included in output when non-empty', () async {
      final handler = createExecutePythonHandler(
        context: ctx,
        dockerClient: _FakeDockerClient(
          runResult: const DockerRunResult(
            stdout: 'Hello, world!',
            stderr: '',
            exitCode: 0,
          ),
        ),
      );
      final output = await handler({'code': 'print("Hello, world!")'});
      expect(output, contains('--- stdout ---'));
      expect(output, contains('Hello, world!'));
    });

    test('stderr is included in output when non-empty', () async {
      final handler = createExecutePythonHandler(
        context: ctx,
        dockerClient: _FakeDockerClient(
          runResult: const DockerRunResult(
            stdout: '',
            stderr: 'Traceback...',
            exitCode: 1,
          ),
        ),
      );
      final output = await handler({'code': 'raise Exception()'});
      expect(output, contains('--- stderr ---'));
      expect(output, contains('Traceback...'));
    });

    test('both stdout and stderr appear when both non-empty', () async {
      final handler = createExecutePythonHandler(
        context: ctx,
        dockerClient: _FakeDockerClient(
          runResult: const DockerRunResult(
            stdout: 'partial output',
            stderr: 'some warning',
            exitCode: 0,
          ),
        ),
      );
      final output = await handler({'code': 'import warnings; print("ok")'});
      expect(output, contains('--- stdout ---'));
      expect(output, contains('--- stderr ---'));
      expect(output, contains('partial output'));
      expect(output, contains('some warning'));
    });

    test('no stdout or stderr: output contains "(no output)"', () async {
      final handler = createExecutePythonHandler(
        context: ctx,
        dockerClient: _FakeDockerClient(
          runResult: const DockerRunResult(stdout: '', stderr: '', exitCode: 0),
        ),
      );
      final output = await handler({'code': 'x = 1'});
      expect(output, contains('(no output)'));
    });

    test(
      'output does not have trailing newlines (trimRight applied)',
      () async {
        final handler = createExecutePythonHandler(
          context: ctx,
          dockerClient: _FakeDockerClient(
            runResult: const DockerRunResult(
              stdout: 'hi',
              stderr: '',
              exitCode: 0,
            ),
          ),
        );
        final output = await handler({'code': 'print("hi")'});
        expect(output, isNot(endsWith('\n')));
      },
    );

    test('output is a non-empty String', () async {
      final handler = createExecutePythonHandler(
        context: ctx,
        dockerClient: _FakeDockerClient(),
      );
      final output = await handler({'code': 'x = 1'});
      expect(output, isA<String>());
      expect(output, isNotEmpty);
    });
  });

  // ── Handler — cleanup ──────────────────────────────────────────────────────

  group('createExecutePythonHandler — temp file cleanup', () {
    late Directory tmpDir;
    late FileContext ctx;

    setUp(() {
      final result = _tempContext();
      tmpDir = result.dir;
      ctx = result.ctx;
    });

    tearDown(() => tmpDir.deleteSync(recursive: true));

    test(
      'temp file is removed from workspace after successful execution',
      () async {
        final handler = createExecutePythonHandler(
          context: ctx,
          dockerClient: _FakeDockerClient(),
        );
        await handler({'code': 'print("hello")'});

        final remaining = ctx
            .listFiles()
            .where((f) => f.contains('.tmp_exec_'))
            .toList();
        expect(remaining, isEmpty);
      },
    );

    test(
      'temp file is removed even when DockerNotAvailableException is thrown',
      () async {
        final handler = createExecutePythonHandler(
          context: ctx,
          dockerClient: _FakeDockerClient(
            throwOnRun: const DockerNotAvailableException(message: 'no docker'),
          ),
        );

        await expectLater(
          () => handler({'code': 'print("hello")'}),
          throwsA(isA<DockerNotAvailableException>()),
        );

        final remaining = ctx
            .listFiles()
            .where((f) => f.contains('.tmp_exec_'))
            .toList();
        expect(remaining, isEmpty);
      },
    );

    test(
      'temp file is removed even when DockerExecutionException is thrown',
      () async {
        final handler = createExecutePythonHandler(
          context: ctx,
          dockerClient: _FakeDockerClient(
            throwOnRun: const DockerExecutionException(
              message: 'container failed',
              exitCode: 125,
            ),
          ),
        );

        await expectLater(
          () => handler({'code': 'print("hello")'}),
          throwsA(isA<DockerExecutionException>()),
        );

        final remaining = ctx
            .listFiles()
            .where((f) => f.contains('.tmp_exec_'))
            .toList();
        expect(remaining, isEmpty);
      },
    );

    test(
      'workspace is empty after handler cleans up (no pre-existing files)',
      () async {
        final handler = createExecutePythonHandler(
          context: ctx,
          dockerClient: _FakeDockerClient(),
        );
        await handler({'code': 'x = 1'});

        expect(ctx.listFiles(), isEmpty);
      },
    );
  });

  // ── Handler — error propagation ───────────────────────────────────────────

  group('createExecutePythonHandler — error propagation', () {
    late Directory tmpDir;
    late FileContext ctx;

    setUp(() {
      final result = _tempContext();
      tmpDir = result.dir;
      ctx = result.ctx;
    });

    tearDown(() => tmpDir.deleteSync(recursive: true));

    test('DockerNotAvailableException is re-thrown (not swallowed)', () async {
      final handler = createExecutePythonHandler(
        context: ctx,
        dockerClient: _FakeDockerClient(
          throwOnRun: const DockerNotAvailableException(message: 'Docker down'),
        ),
      );
      await expectLater(
        () => handler({'code': 'print(1)'}),
        throwsA(isA<DockerNotAvailableException>()),
      );
    });

    test('DockerExecutionException is re-thrown (not swallowed)', () async {
      final handler = createExecutePythonHandler(
        context: ctx,
        dockerClient: _FakeDockerClient(
          throwOnRun: const DockerExecutionException(
            message: 'container failed to start',
            exitCode: 125,
          ),
        ),
      );
      await expectLater(
        () => handler({'code': 'print(1)'}),
        throwsA(isA<DockerExecutionException>()),
      );
    });

    test(
      'DockerNotAvailableException carries original cause in re-thrown exception',
      () async {
        const originalException = DockerNotAvailableException(
          message: 'specific message',
        );
        final handler = createExecutePythonHandler(
          context: ctx,
          dockerClient: _FakeDockerClient(throwOnRun: originalException),
        );

        Object? caught;
        try {
          await handler({'code': 'x = 1'});
        } catch (e) {
          caught = e;
        }
        expect(caught, same(originalException));
      },
    );

    test(
      'non-zero Python exit code (1) is returned as string, NOT thrown',
      () async {
        final handler = createExecutePythonHandler(
          context: ctx,
          dockerClient: _FakeDockerClient(
            runResult: const DockerRunResult(
              stdout: '',
              stderr: 'ZeroDivisionError',
              exitCode: 1,
            ),
          ),
        );
        // Should return a string, not throw
        final output = await handler({'code': '1/0'});
        expect(output, isA<String>());
        expect(output, contains('[ERROR]'));
      },
    );

    test(
      'exit code 127 (command not found) is returned as string, NOT thrown',
      () async {
        final handler = createExecutePythonHandler(
          context: ctx,
          dockerClient: _FakeDockerClient(
            runResult: const DockerRunResult(
              stdout: '',
              stderr: 'sh: 1: python: not found',
              exitCode: 127,
            ),
          ),
        );
        final output = await handler({'code': 'print(1)'});
        expect(output, contains('[ERROR] exit_code=127'));
      },
    );
  });
}
