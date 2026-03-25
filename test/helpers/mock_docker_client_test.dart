import 'package:agents_core/agents_core.dart';
import 'package:test/test.dart';

import 'mock_docker_client.dart';

void main() {
  // ── helpers ──────────────────────────────────────────────────────────────

  DockerRunResult okResult({
    String stdout = 'ok',
    String stderr = '',
    int exitCode = 0,
  }) =>
      DockerRunResult(stdout: stdout, stderr: stderr, exitCode: exitCode);

  Future<DockerRunResult> runMock(
    MockDockerClient docker, {
    String image = 'python:3.12-slim',
    List<String> command = const ['python', '-c', 'print("hi")'],
    Map<String, String> volumes = const {},
    String? workingDir,
    Duration timeout = const Duration(seconds: 60),
    Map<String, String> environment = const {},
  }) =>
      docker.runContainer(
        image: image,
        command: command,
        volumes: volumes,
        workingDir: workingDir,
        timeout: timeout,
        environment: environment,
      );

  // ── group: construction ───────────────────────────────────────────────────

  group('MockDockerClient — construction', () {
    test('creates instance with defaults', () {
      final docker = MockDockerClient();
      expect(docker.isDockerAvailable, isTrue);
      expect(docker.runContainerCalls, isEmpty);
      expect(docker.isImageAvailableCalls, isEmpty);
      expect(docker.pullImageCalls, isEmpty);
      expect(docker.pendingResponseCount, 0);
    });

    test('isDockerAvailable can be set to false at construction', () {
      final docker = MockDockerClient(isDockerAvailable: false);
      expect(docker.isDockerAvailable, isFalse);
    });
  });

  // ── group: isAvailable ────────────────────────────────────────────────────

  group('isAvailable()', () {
    test('returns true when isDockerAvailable is true', () async {
      final docker = MockDockerClient(isDockerAvailable: true);
      expect(await docker.isAvailable(), isTrue);
    });

    test('returns false when isDockerAvailable is false', () async {
      final docker = MockDockerClient(isDockerAvailable: false);
      expect(await docker.isAvailable(), isFalse);
    });

    test('can be toggled at runtime', () async {
      final docker = MockDockerClient();
      expect(await docker.isAvailable(), isTrue);
      docker.isDockerAvailable = false;
      expect(await docker.isAvailable(), isFalse);
    });
  });

  // ── group: isImageAvailable ───────────────────────────────────────────────

  group('isImageAvailable()', () {
    test('returns true by default (defaultImageAvailable = true)', () async {
      final docker = MockDockerClient();
      expect(await docker.isImageAvailable('python:3.12-slim'), isTrue);
    });

    test('returns false when defaultImageAvailable = false', () async {
      final docker = MockDockerClient(defaultImageAvailable: false);
      expect(await docker.isImageAvailable('python:3.12-slim'), isFalse);
    });

    test('overrides per-image via imageAvailability constructor param', () async {
      final docker = MockDockerClient(
        imageAvailability: {
          'python:3.12-slim': false,
          'ubuntu:22.04': true,
        },
      );
      expect(await docker.isImageAvailable('python:3.12-slim'), isFalse);
      expect(await docker.isImageAvailable('ubuntu:22.04'), isTrue);
    });

    test('setImageAvailable() overrides per-image at runtime', () async {
      final docker = MockDockerClient();
      docker.setImageAvailable('missing-image', available: false);
      expect(await docker.isImageAvailable('missing-image'), isFalse);
      docker.setImageAvailable('missing-image');
      expect(await docker.isImageAvailable('missing-image'), isTrue);
    });

    test('records every call in isImageAvailableCalls', () async {
      final docker = MockDockerClient();
      await docker.isImageAvailable('img-a');
      await docker.isImageAvailable('img-b');
      await docker.isImageAvailable('img-a');
      expect(docker.isImageAvailableCalls, ['img-a', 'img-b', 'img-a']);
    });
  });

  // ── group: pullImage ──────────────────────────────────────────────────────

  group('pullImage()', () {
    test('records pulled image names', () async {
      final docker = MockDockerClient();
      await docker.pullImage('python:3.12-slim');
      await docker.pullImage('ubuntu:22.04');
      expect(docker.pullImageCalls, ['python:3.12-slim', 'ubuntu:22.04']);
    });

    test('throws DockerNotAvailableException when Docker unavailable', () async {
      final docker = MockDockerClient(isDockerAvailable: false);
      expect(
        () => docker.pullImage('python:3.12-slim'),
        throwsA(isA<DockerNotAvailableException>()),
      );
    });

    test('succeeds silently when Docker is available', () async {
      final docker = MockDockerClient();
      await expectLater(
        docker.pullImage('python:3.12-slim'),
        completes,
      );
    });
  });

  // ── group: enqueueResult ──────────────────────────────────────────────────

  group('runContainer() — enqueueResult()', () {
    test('returns queued DockerRunResult', () async {
      final docker = MockDockerClient();
      final expected = okResult(stdout: 'Hello, world!');
      docker.enqueueResult(expected);

      final result = await runMock(docker);
      expect(result.stdout, 'Hello, world!');
      expect(result.stderr, '');
      expect(result.exitCode, 0);
    });

    test('returns results in FIFO order', () async {
      final docker = MockDockerClient();
      docker.enqueueResult(okResult(stdout: 'first'));
      docker.enqueueResult(okResult(stdout: 'second'));
      docker.enqueueResult(okResult(stdout: 'third'));

      expect((await runMock(docker)).stdout, 'first');
      expect((await runMock(docker)).stdout, 'second');
      expect((await runMock(docker)).stdout, 'third');
    });

    test('enqueueSuccess() queues a zero-exit result', () async {
      final docker = MockDockerClient();
      docker.enqueueSuccess(stdout: 'done', stderr: 'warn', exitCode: 0);

      final result = await runMock(docker);
      expect(result.stdout, 'done');
      expect(result.stderr, 'warn');
      expect(result.exitCode, 0);
    });

    test('supports non-zero exit codes (application-level errors)', () async {
      final docker = MockDockerClient();
      docker.enqueueResult(okResult(exitCode: 1, stderr: 'SyntaxError'));

      final result = await runMock(docker);
      expect(result.exitCode, 1);
      expect(result.stderr, 'SyntaxError');
    });

    test('pendingResponseCount decreases after each call', () async {
      final docker = MockDockerClient();
      docker.enqueueResult(okResult());
      docker.enqueueResult(okResult());
      expect(docker.pendingResponseCount, 2);

      await runMock(docker);
      expect(docker.pendingResponseCount, 1);

      await runMock(docker);
      expect(docker.pendingResponseCount, 0);
    });
  });

  // ── group: enqueueException ───────────────────────────────────────────────

  group('runContainer() — enqueueException()', () {
    test('throws queued DockerNotAvailableException', () async {
      final docker = MockDockerClient();
      docker.enqueueException(
        const DockerNotAvailableException(message: 'daemon not running'),
      );

      expect(
        () => runMock(docker),
        throwsA(
          isA<DockerNotAvailableException>().having(
            (e) => e.message,
            'message',
            'daemon not running',
          ),
        ),
      );
    });

    test('throws queued DockerExecutionException', () async {
      final docker = MockDockerClient();
      docker.enqueueException(
        const DockerExecutionException(
          message: 'container failed to start',
          exitCode: 125,
          stderr: 'Error response from daemon',
        ),
      );

      expect(
        () => runMock(docker),
        throwsA(
          isA<DockerExecutionException>()
              .having((e) => e.exitCode, 'exitCode', 125)
              .having((e) => e.stderr, 'stderr', 'Error response from daemon'),
        ),
      );
    });

    test('enqueueNotAvailable() convenience queues DockerNotAvailableException',
        () async {
      final docker = MockDockerClient();
      docker.enqueueNotAvailable(message: 'no docker here');

      expect(
        () => runMock(docker),
        throwsA(
          isA<DockerNotAvailableException>()
              .having((e) => e.message, 'message', 'no docker here'),
        ),
      );
    });

    test('exceptions and results can be interleaved in the queue', () async {
      final docker = MockDockerClient();
      docker.enqueueResult(okResult(stdout: 'before'));
      docker.enqueueException(
        const DockerExecutionException(
          message: 'oops',
          exitCode: 125,
        ),
      );
      docker.enqueueResult(okResult(stdout: 'after'));

      expect((await runMock(docker)).stdout, 'before');
      expect(
        () => runMock(docker),
        throwsA(isA<DockerExecutionException>()),
      );
      expect((await runMock(docker)).stdout, 'after');
    });
  });

  // ── group: Docker unavailable guard ──────────────────────────────────────

  group('runContainer() — Docker unavailable guard', () {
    test('throws DockerNotAvailableException when isDockerAvailable is false',
        () async {
      final docker = MockDockerClient(isDockerAvailable: false);
      docker.enqueueResult(okResult()); // queued result is ignored

      expect(
        () => runMock(docker),
        throwsA(isA<DockerNotAvailableException>()),
      );
    });

    test('still records the call even when Docker is unavailable', () async {
      final docker = MockDockerClient(isDockerAvailable: false);

      try {
        await runMock(docker, image: 'python:3.12-slim');
      } on DockerNotAvailableException {
        // expected
      }

      expect(docker.runContainerCalls, hasLength(1));
      expect(docker.runContainerCalls.first.image, 'python:3.12-slim');
    });

    test('throws StateError when queue is empty and Docker is available',
        () async {
      final docker = MockDockerClient();

      expect(
        () => runMock(docker),
        throwsA(isA<StateError>()),
      );
    });
  });

  // ── group: call recording ─────────────────────────────────────────────────

  group('runContainer() — call recording', () {
    test('records image and command', () async {
      final docker = MockDockerClient();
      docker.enqueueResult(okResult());

      await runMock(
        docker,
        image: 'python:3.12-slim',
        command: ['python', '-c', 'print("hi")'],
      );

      final call = docker.runContainerCalls.first;
      expect(call.image, 'python:3.12-slim');
      expect(call.command, ['python', '-c', 'print("hi")']);
    });

    test('records volumes', () async {
      final docker = MockDockerClient();
      docker.enqueueResult(okResult());

      await runMock(
        docker,
        volumes: {'/tmp/host': '/container/path'},
      );

      expect(docker.runContainerCalls.first.volumes, {'/tmp/host': '/container/path'});
    });

    test('records workingDir', () async {
      final docker = MockDockerClient();
      docker.enqueueResult(okResult());

      await runMock(docker, workingDir: '/workspace');

      expect(docker.runContainerCalls.first.workingDir, '/workspace');
    });

    test('records null workingDir when not specified', () async {
      final docker = MockDockerClient();
      docker.enqueueResult(okResult());

      await runMock(docker);

      expect(docker.runContainerCalls.first.workingDir, isNull);
    });

    test('records timeout', () async {
      final docker = MockDockerClient();
      docker.enqueueResult(okResult());

      await runMock(docker, timeout: const Duration(seconds: 30));

      expect(
        docker.runContainerCalls.first.timeout,
        const Duration(seconds: 30),
      );
    });

    test('records environment variables', () async {
      final docker = MockDockerClient();
      docker.enqueueResult(okResult());

      await runMock(docker, environment: {'MY_VAR': 'hello', 'OTHER': 'world'});

      expect(
        docker.runContainerCalls.first.environment,
        {'MY_VAR': 'hello', 'OTHER': 'world'},
      );
    });

    test('accumulates multiple calls', () async {
      final docker = MockDockerClient();
      docker.enqueueResult(okResult());
      docker.enqueueResult(okResult());

      await runMock(docker, image: 'img-1');
      await runMock(docker, image: 'img-2');

      expect(docker.runContainerCalls, hasLength(2));
      expect(docker.runContainerCalls[0].image, 'img-1');
      expect(docker.runContainerCalls[1].image, 'img-2');
    });

    test('lastRunContainerCall returns null when no calls made', () {
      final docker = MockDockerClient();
      expect(docker.lastRunContainerCall, isNull);
    });

    test('lastRunContainerCall returns the most recent call', () async {
      final docker = MockDockerClient();
      docker.enqueueResult(okResult());
      docker.enqueueResult(okResult());

      await runMock(docker, image: 'img-1');
      await runMock(docker, image: 'img-2');

      expect(docker.lastRunContainerCall!.image, 'img-2');
    });
  });

  // ── group: reset() ────────────────────────────────────────────────────────

  group('reset()', () {
    test('clears all recorded calls', () async {
      final docker = MockDockerClient();
      docker.enqueueResult(okResult());
      await runMock(docker);
      await docker.isImageAvailable('img');
      await docker.pullImage('img');

      docker.reset();

      expect(docker.runContainerCalls, isEmpty);
      expect(docker.isImageAvailableCalls, isEmpty);
      expect(docker.pullImageCalls, isEmpty);
    });

    test('clears the response queue', () async {
      final docker = MockDockerClient();
      docker.enqueueResult(okResult());
      docker.enqueueResult(okResult());
      expect(docker.pendingResponseCount, 2);

      docker.reset();

      expect(docker.pendingResponseCount, 0);
    });

    test('mock is usable again after reset', () async {
      final docker = MockDockerClient();
      docker.enqueueResult(okResult(stdout: 'first'));
      await runMock(docker);

      docker.reset();

      docker.enqueueResult(okResult(stdout: 'second'));
      final result = await runMock(docker);
      expect(result.stdout, 'second');
      expect(docker.runContainerCalls, hasLength(1));
    });
  });

  // ── group: RecordedRunContainerCall ───────────────────────────────────────

  group('RecordedRunContainerCall', () {
    test('toString includes image and command', () async {
      final docker = MockDockerClient();
      docker.enqueueResult(okResult());

      await runMock(
        docker,
        image: 'python:3.12-slim',
        command: ['python', '--version'],
      );

      final str = docker.runContainerCalls.first.toString();
      expect(str, contains('python:3.12-slim'));
      expect(str, contains('python'));
      expect(str, contains('--version'));
    });
  });
}
