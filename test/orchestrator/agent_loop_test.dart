// ignore_for_file: avoid_implementing_value_types

import 'dart:io';

import 'package:agents_core/agents_core.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// A fake [Agent] whose [run] method returns from a queue of results (or
/// throws from a queue of errors).
///
/// Tracks call count, captured tasks, and captured contexts for assertions.
class _FakeAgent extends Agent {
  _FakeAgent({
    super.name = 'fake',
    List<AgentResult>? results,
    List<Object>? errors,
  }) : _results = results ?? const [],
       _errors = errors ?? const [],
       super(
         client: LmStudioClient(AgentsCoreConfig(logger: const SilentLogger())),
         config: AgentsCoreConfig(logger: const SilentLogger()),
       );

  /// Convenience: create a fake that always returns the same result.
  _FakeAgent.single({
    String name = 'fake',
    AgentResult result = const AgentResult(output: 'fake output'),
  }) : this(name: name, results: [result]);

  /// Convenience: create a fake that always throws the same error.
  _FakeAgent.throwing({String name = 'fake', required Object error})
    : this(name: name, errors: [error]);

  final List<AgentResult> _results;
  final List<Object> _errors;

  final List<String> capturedTasks = [];
  final List<FileContext?> capturedContexts = [];
  int callCount = 0;

  @override
  Future<AgentResult> run(String task, {FileContext? context}) async {
    final index = callCount;
    callCount++;
    capturedTasks.add(task);
    capturedContexts.add(context);

    // If there are errors queued for this index, throw them.
    if (_errors.isNotEmpty && index < _errors.length) {
      throw _errors[index];
    }

    // Return from the results queue, or default.
    if (_results.isNotEmpty) {
      return _results[index % _results.length];
    }
    return const AgentResult(output: 'fake output');
  }
}

/// Creates a [FileContext] backed by a temp directory.
({FileContext ctx, Directory dir}) _tempContext() {
  final dir = Directory.systemTemp.createTempSync('agent_loop_test_');
  final ctx = FileContext(workspacePath: dir.path);
  return (ctx: ctx, dir: dir);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // ── AgentLoopIteration ──────────────────────────────────────────────────

  group('AgentLoopIteration', () {
    test('stores index', () {
      final pr = const AgentResult(output: 'producer out');
      final rr = const AgentResult(output: 'reviewer out');
      final iteration = AgentLoopIteration(
        index: 2,
        producerResult: pr,
        reviewerResult: rr,
      );
      expect(iteration.index, 2);
    });

    test('stores producerResult', () {
      final pr = const AgentResult(output: 'produced', tokensUsed: 100);
      final rr = const AgentResult(output: 'reviewed');
      final iteration = AgentLoopIteration(
        index: 0,
        producerResult: pr,
        reviewerResult: rr,
      );
      expect(iteration.producerResult.output, 'produced');
      expect(iteration.producerResult.tokensUsed, 100);
    });

    test('stores reviewerResult', () {
      final pr = const AgentResult(output: 'produced');
      final rr = const AgentResult(output: 'reviewed', tokensUsed: 50);
      final iteration = AgentLoopIteration(
        index: 0,
        producerResult: pr,
        reviewerResult: rr,
      );
      expect(iteration.reviewerResult.output, 'reviewed');
      expect(iteration.reviewerResult.tokensUsed, 50);
    });

    test('index is zero-based', () {
      final iteration = AgentLoopIteration(
        index: 0,
        producerResult: const AgentResult(output: ''),
        reviewerResult: const AgentResult(output: ''),
      );
      expect(iteration.index, 0);
    });
  });

  // ── AgentLoopResult ─────────────────────────────────────────────────────

  group('AgentLoopResult', () {
    test('stores iterations list', () {
      final iter1 = AgentLoopIteration(
        index: 0,
        producerResult: const AgentResult(output: 'p0'),
        reviewerResult: const AgentResult(output: 'r0'),
      );
      final iter2 = AgentLoopIteration(
        index: 1,
        producerResult: const AgentResult(output: 'p1'),
        reviewerResult: const AgentResult(output: 'r1'),
      );
      final result = AgentLoopResult(
        iterations: [iter1, iter2],
        accepted: true,
        duration: const Duration(seconds: 5),
        totalTokensUsed: 200,
      );
      expect(result.iterations, hasLength(2));
      expect(result.iterations[0].index, 0);
      expect(result.iterations[1].index, 1);
    });

    test('stores accepted flag — true', () {
      final result = AgentLoopResult(
        iterations: [],
        accepted: true,
        duration: Duration.zero,
        totalTokensUsed: 0,
      );
      expect(result.accepted, isTrue);
    });

    test('stores accepted flag — false', () {
      final result = AgentLoopResult(
        iterations: [],
        accepted: false,
        duration: Duration.zero,
        totalTokensUsed: 0,
      );
      expect(result.accepted, isFalse);
    });

    test('stores duration', () {
      final result = AgentLoopResult(
        iterations: [],
        accepted: true,
        duration: const Duration(milliseconds: 1234),
        totalTokensUsed: 0,
      );
      expect(result.duration, const Duration(milliseconds: 1234));
    });

    test('stores totalTokensUsed', () {
      final result = AgentLoopResult(
        iterations: [],
        accepted: true,
        duration: Duration.zero,
        totalTokensUsed: 42,
      );
      expect(result.totalTokensUsed, 42);
    });

    // Convenience getters

    test('iterationCount returns number of iterations', () {
      final iterations = List.generate(
        3,
        (i) => AgentLoopIteration(
          index: i,
          producerResult: const AgentResult(output: 'p'),
          reviewerResult: const AgentResult(output: 'r'),
        ),
      );
      final result = AgentLoopResult(
        iterations: iterations,
        accepted: true,
        duration: Duration.zero,
        totalTokensUsed: 0,
      );
      expect(result.iterationCount, 3);
    });

    test('iterationCount is 0 for empty iterations', () {
      final result = AgentLoopResult(
        iterations: [],
        accepted: false,
        duration: Duration.zero,
        totalTokensUsed: 0,
      );
      expect(result.iterationCount, 0);
    });

    test(
      'lastProducerResult returns the producer result from last iteration',
      () {
        final iterations = [
          AgentLoopIteration(
            index: 0,
            producerResult: const AgentResult(output: 'p0'),
            reviewerResult: const AgentResult(output: 'r0'),
          ),
          AgentLoopIteration(
            index: 1,
            producerResult: const AgentResult(output: 'p1-final'),
            reviewerResult: const AgentResult(output: 'r1'),
          ),
        ];
        final result = AgentLoopResult(
          iterations: iterations,
          accepted: true,
          duration: Duration.zero,
          totalTokensUsed: 0,
        );
        expect(result.lastProducerResult.output, 'p1-final');
      },
    );

    test(
      'lastReviewerResult returns the reviewer result from last iteration',
      () {
        final iterations = [
          AgentLoopIteration(
            index: 0,
            producerResult: const AgentResult(output: 'p0'),
            reviewerResult: const AgentResult(output: 'r0'),
          ),
          AgentLoopIteration(
            index: 1,
            producerResult: const AgentResult(output: 'p1'),
            reviewerResult: const AgentResult(output: 'r1-final'),
          ),
        ];
        final result = AgentLoopResult(
          iterations: iterations,
          accepted: true,
          duration: Duration.zero,
          totalTokensUsed: 0,
        );
        expect(result.lastReviewerResult.output, 'r1-final');
      },
    );

    test('reachedMaxIterations is true when accepted is false', () {
      final result = AgentLoopResult(
        iterations: [],
        accepted: false,
        duration: Duration.zero,
        totalTokensUsed: 0,
      );
      expect(result.reachedMaxIterations, isTrue);
    });

    test('reachedMaxIterations is false when accepted is true', () {
      final result = AgentLoopResult(
        iterations: [],
        accepted: true,
        duration: Duration.zero,
        totalTokensUsed: 0,
      );
      expect(result.reachedMaxIterations, isFalse);
    });
  });

  // ── AgentLoop construction ──────────────────────────────────────────────

  group('AgentLoop construction', () {
    late Directory tempDir;
    late FileContext ctx;

    setUp(() {
      final result = _tempContext();
      tempDir = result.dir;
      ctx = result.ctx;
    });

    tearDown(() => tempDir.deleteSync(recursive: true));

    test('accepts required parameters', () {
      expect(
        () => AgentLoop(
          context: ctx,
          producer: _FakeAgent(name: 'producer'),
          reviewer: _FakeAgent(name: 'reviewer'),
          isAccepted: (result, iteration) => true,
        ),
        returnsNormally,
      );
    });

    test('exposes context', () {
      final loop = AgentLoop(
        context: ctx,
        producer: _FakeAgent(name: 'producer'),
        reviewer: _FakeAgent(name: 'reviewer'),
        isAccepted: (result, iteration) => true,
      );
      expect(loop.context, same(ctx));
    });

    test('exposes producer agent', () {
      final producer = _FakeAgent(name: 'my-producer');
      final loop = AgentLoop(
        context: ctx,
        producer: producer,
        reviewer: _FakeAgent(name: 'reviewer'),
        isAccepted: (result, iteration) => true,
      );
      expect(loop.producer, same(producer));
    });

    test('exposes reviewer agent', () {
      final reviewer = _FakeAgent(name: 'my-reviewer');
      final loop = AgentLoop(
        context: ctx,
        producer: _FakeAgent(name: 'producer'),
        reviewer: reviewer,
        isAccepted: (result, iteration) => true,
      );
      expect(loop.reviewer, same(reviewer));
    });

    test('maxIterations defaults to 5', () {
      final loop = AgentLoop(
        context: ctx,
        producer: _FakeAgent(name: 'producer'),
        reviewer: _FakeAgent(name: 'reviewer'),
        isAccepted: (result, iteration) => true,
      );
      expect(loop.maxIterations, 5);
    });

    test('maxIterations can be set to custom value', () {
      final loop = AgentLoop(
        context: ctx,
        producer: _FakeAgent(name: 'producer'),
        reviewer: _FakeAgent(name: 'reviewer'),
        isAccepted: (result, iteration) => true,
        maxIterations: 10,
      );
      expect(loop.maxIterations, 10);
    });

    test('accepts optional buildProducerPrompt', () {
      expect(
        () => AgentLoop(
          context: ctx,
          producer: _FakeAgent(name: 'producer'),
          reviewer: _FakeAgent(name: 'reviewer'),
          isAccepted: (result, iteration) => true,
          buildProducerPrompt: (task, ctx, iter, prev) async => task,
        ),
        returnsNormally,
      );
    });

    test('accepts optional buildReviewerPrompt', () {
      expect(
        () => AgentLoop(
          context: ctx,
          producer: _FakeAgent(name: 'producer'),
          reviewer: _FakeAgent(name: 'reviewer'),
          isAccepted: (result, iteration) => true,
          buildReviewerPrompt: (task, ctx, iter, pr) async => 'review',
        ),
        returnsNormally,
      );
    });
  });

  // ── AgentLoop.run() — happy path (accepted on first iteration) ─────────

  group('AgentLoop.run() — accepted on first iteration', () {
    late Directory tempDir;
    late FileContext ctx;

    setUp(() {
      final result = _tempContext();
      tempDir = result.dir;
      ctx = result.ctx;
    });

    tearDown(() => tempDir.deleteSync(recursive: true));

    test(
      'runs producer then reviewer once when accepted immediately',
      () async {
        final producer = _FakeAgent.single(
          name: 'producer',
          result: const AgentResult(output: 'code', tokensUsed: 100),
        );
        final reviewer = _FakeAgent.single(
          name: 'reviewer',
          result: const AgentResult(output: 'LGTM', tokensUsed: 50),
        );

        final loop = AgentLoop(
          context: ctx,
          producer: producer,
          reviewer: reviewer,
          isAccepted: (result, iteration) => true,
        );

        final result = await loop.run('Write a function');

        expect(producer.callCount, 1);
        expect(reviewer.callCount, 1);
        expect(result.accepted, isTrue);
        expect(result.iterationCount, 1);
      },
    );

    test(
      'returns correct AgentLoopResult when accepted first iteration',
      () async {
        final producerResult = const AgentResult(
          output: 'produced code',
          tokensUsed: 200,
        );
        final reviewerResult = const AgentResult(
          output: 'looks good',
          tokensUsed: 100,
        );

        final producer = _FakeAgent.single(
          name: 'producer',
          result: producerResult,
        );
        final reviewer = _FakeAgent.single(
          name: 'reviewer',
          result: reviewerResult,
        );

        final loop = AgentLoop(
          context: ctx,
          producer: producer,
          reviewer: reviewer,
          isAccepted: (result, iteration) => true,
        );

        final result = await loop.run('task');

        expect(result.accepted, isTrue);
        expect(result.reachedMaxIterations, isFalse);
        expect(result.iterationCount, 1);
        expect(result.iterations[0].index, 0);
        expect(result.iterations[0].producerResult.output, 'produced code');
        expect(result.iterations[0].reviewerResult.output, 'looks good');
        expect(result.totalTokensUsed, 300); // 200 + 100
        expect(result.duration.inMicroseconds, greaterThanOrEqualTo(0));
      },
    );

    test('passes original task to producer on iteration 0', () async {
      final producer = _FakeAgent.single(name: 'producer');
      final reviewer = _FakeAgent.single(name: 'reviewer');

      final loop = AgentLoop(
        context: ctx,
        producer: producer,
        reviewer: reviewer,
        isAccepted: (result, iteration) => true,
      );

      await loop.run('Build a widget');

      expect(producer.capturedTasks.first, 'Build a widget');
    });

    test('passes FileContext to both producer and reviewer', () async {
      final producer = _FakeAgent.single(name: 'producer');
      final reviewer = _FakeAgent.single(name: 'reviewer');

      final loop = AgentLoop(
        context: ctx,
        producer: producer,
        reviewer: reviewer,
        isAccepted: (result, iteration) => true,
      );

      await loop.run('task');

      expect(producer.capturedContexts.first, same(ctx));
      expect(reviewer.capturedContexts.first, same(ctx));
    });

    test(
      'builds default reviewer prompt from task and producer output',
      () async {
        final producer = _FakeAgent.single(
          name: 'producer',
          result: const AgentResult(output: 'my code output'),
        );
        final reviewer = _FakeAgent.single(name: 'reviewer');

        final loop = AgentLoop(
          context: ctx,
          producer: producer,
          reviewer: reviewer,
          isAccepted: (result, iteration) => true,
        );

        await loop.run('Write tests');

        final reviewerTask = reviewer.capturedTasks.first;
        expect(reviewerTask, contains('Review the following output'));
        expect(reviewerTask, contains('Write tests'));
        expect(reviewerTask, contains('my code output'));
      },
    );
  });

  // ── AgentLoop.run() — multi-iteration (accepted after N iterations) ────

  group('AgentLoop.run() — multi-iteration', () {
    late Directory tempDir;
    late FileContext ctx;

    setUp(() {
      final result = _tempContext();
      tempDir = result.dir;
      ctx = result.ctx;
    });

    tearDown(() => tempDir.deleteSync(recursive: true));

    test('loops until isAccepted returns true', () async {
      var acceptOnIteration = 2;
      final producer = _FakeAgent(
        name: 'producer',
        results: [
          const AgentResult(output: 'v1', tokensUsed: 10),
          const AgentResult(output: 'v2', tokensUsed: 20),
          const AgentResult(output: 'v3', tokensUsed: 30),
        ],
      );
      final reviewer = _FakeAgent(
        name: 'reviewer',
        results: [
          const AgentResult(output: 'needs work', tokensUsed: 5),
          const AgentResult(output: 'still needs work', tokensUsed: 5),
          const AgentResult(output: 'approved', tokensUsed: 5),
        ],
      );

      final loop = AgentLoop(
        context: ctx,
        producer: producer,
        reviewer: reviewer,
        isAccepted: (result, iteration) => iteration == acceptOnIteration,
      );

      final result = await loop.run('task');

      expect(result.accepted, isTrue);
      expect(result.iterationCount, 3); // iterations 0, 1, 2
      expect(producer.callCount, 3);
      expect(reviewer.callCount, 3);
    });

    test('iteration indices are zero-based and sequential', () async {
      final producer = _FakeAgent(
        name: 'producer',
        results: [
          const AgentResult(output: 'v1'),
          const AgentResult(output: 'v2'),
        ],
      );
      final reviewer = _FakeAgent(
        name: 'reviewer',
        results: [
          const AgentResult(output: 'no'),
          const AgentResult(output: 'yes'),
        ],
      );

      final loop = AgentLoop(
        context: ctx,
        producer: producer,
        reviewer: reviewer,
        isAccepted: (result, iteration) => iteration == 1,
      );

      final result = await loop.run('task');

      expect(result.iterations[0].index, 0);
      expect(result.iterations[1].index, 1);
    });

    test(
      'default producer prompt on iteration 1+ includes reviewer feedback',
      () async {
        final producer = _FakeAgent(
          name: 'producer',
          results: [
            const AgentResult(output: 'v1'),
            const AgentResult(output: 'v2'),
          ],
        );
        final reviewer = _FakeAgent(
          name: 'reviewer',
          results: [
            const AgentResult(output: 'Fix the off-by-one error'),
            const AgentResult(output: 'LGTM'),
          ],
        );

        final loop = AgentLoop(
          context: ctx,
          producer: producer,
          reviewer: reviewer,
          isAccepted: (result, iteration) => iteration == 1,
        );

        await loop.run('Write sorting function');

        // Iteration 0: original task
        expect(producer.capturedTasks[0], 'Write sorting function');

        // Iteration 1: original task + reviewer feedback
        final secondPrompt = producer.capturedTasks[1];
        expect(secondPrompt, contains('Write sorting function'));
        expect(secondPrompt, contains('Previous review feedback'));
        expect(secondPrompt, contains('Fix the off-by-one error'));
        expect(secondPrompt, contains('Please address the feedback'));
      },
    );

    test('totalTokensUsed sums all producer and reviewer tokens', () async {
      final producer = _FakeAgent(
        name: 'producer',
        results: [
          const AgentResult(output: 'v1', tokensUsed: 100),
          const AgentResult(output: 'v2', tokensUsed: 150),
        ],
      );
      final reviewer = _FakeAgent(
        name: 'reviewer',
        results: [
          const AgentResult(output: 'no', tokensUsed: 30),
          const AgentResult(output: 'yes', tokensUsed: 20),
        ],
      );

      final loop = AgentLoop(
        context: ctx,
        producer: producer,
        reviewer: reviewer,
        isAccepted: (result, iteration) => iteration == 1,
      );

      final result = await loop.run('task');

      expect(result.totalTokensUsed, 300); // 100+30+150+20
    });

    test('lastProducerResult is from the final iteration', () async {
      final producer = _FakeAgent(
        name: 'producer',
        results: [
          const AgentResult(output: 'first attempt'),
          const AgentResult(output: 'second attempt'),
        ],
      );
      final reviewer = _FakeAgent(
        name: 'reviewer',
        results: [
          const AgentResult(output: 'reject'),
          const AgentResult(output: 'accept'),
        ],
      );

      final loop = AgentLoop(
        context: ctx,
        producer: producer,
        reviewer: reviewer,
        isAccepted: (result, iteration) => iteration == 1,
      );

      final result = await loop.run('task');

      expect(result.lastProducerResult.output, 'second attempt');
    });

    test('lastReviewerResult is from the final iteration', () async {
      final producer = _FakeAgent(
        name: 'producer',
        results: [
          const AgentResult(output: 'v1'),
          const AgentResult(output: 'v2'),
        ],
      );
      final reviewer = _FakeAgent(
        name: 'reviewer',
        results: [
          const AgentResult(output: 'reject'),
          const AgentResult(output: 'final accept'),
        ],
      );

      final loop = AgentLoop(
        context: ctx,
        producer: producer,
        reviewer: reviewer,
        isAccepted: (result, iteration) => iteration == 1,
      );

      final result = await loop.run('task');

      expect(result.lastReviewerResult.output, 'final accept');
    });
  });

  // ── AgentLoop.run() — maxIterations safety limit ────────────────────────

  group('AgentLoop.run() — maxIterations safety limit', () {
    late Directory tempDir;
    late FileContext ctx;

    setUp(() {
      final result = _tempContext();
      tempDir = result.dir;
      ctx = result.ctx;
    });

    tearDown(() => tempDir.deleteSync(recursive: true));

    test('stops after maxIterations when never accepted', () async {
      final producer = _FakeAgent.single(
        name: 'producer',
        result: const AgentResult(output: 'attempt'),
      );
      final reviewer = _FakeAgent.single(
        name: 'reviewer',
        result: const AgentResult(output: 'rejected'),
      );

      final loop = AgentLoop(
        context: ctx,
        producer: producer,
        reviewer: reviewer,
        isAccepted: (result, iteration) => false, // never accept
        maxIterations: 3,
      );

      final result = await loop.run('task');

      expect(result.accepted, isFalse);
      expect(result.reachedMaxIterations, isTrue);
      expect(result.iterationCount, 3);
      expect(producer.callCount, 3);
      expect(reviewer.callCount, 3);
    });

    test('maxIterations = 1 runs exactly one iteration', () async {
      final producer = _FakeAgent.single(name: 'producer');
      final reviewer = _FakeAgent.single(name: 'reviewer');

      final loop = AgentLoop(
        context: ctx,
        producer: producer,
        reviewer: reviewer,
        isAccepted: (result, iteration) => false,
        maxIterations: 1,
      );

      final result = await loop.run('task');

      expect(result.iterationCount, 1);
      expect(result.accepted, isFalse);
      expect(producer.callCount, 1);
      expect(reviewer.callCount, 1);
    });

    test('default maxIterations = 5 runs up to 5 iterations', () async {
      final producer = _FakeAgent.single(name: 'producer');
      final reviewer = _FakeAgent.single(name: 'reviewer');

      final loop = AgentLoop(
        context: ctx,
        producer: producer,
        reviewer: reviewer,
        isAccepted: (result, iteration) => false,
        // default maxIterations = 5
      );

      final result = await loop.run('task');

      expect(result.iterationCount, 5);
      expect(result.accepted, isFalse);
      expect(producer.callCount, 5);
      expect(reviewer.callCount, 5);
    });

    test('accepted on last iteration still sets accepted = true', () async {
      final producer = _FakeAgent.single(name: 'producer');
      final reviewer = _FakeAgent.single(name: 'reviewer');

      final loop = AgentLoop(
        context: ctx,
        producer: producer,
        reviewer: reviewer,
        isAccepted: (result, iteration) => iteration == 2, // accept on last
        maxIterations: 3,
      );

      final result = await loop.run('task');

      expect(result.accepted, isTrue);
      expect(result.reachedMaxIterations, isFalse);
      expect(result.iterationCount, 3);
    });
  });

  // ── AgentLoop.run() — isAccepted callback ──────────────────────────────

  group('AgentLoop.run() — isAccepted callback', () {
    late Directory tempDir;
    late FileContext ctx;

    setUp(() {
      final result = _tempContext();
      tempDir = result.dir;
      ctx = result.ctx;
    });

    tearDown(() => tempDir.deleteSync(recursive: true));

    test('receives the reviewerResult from current iteration', () async {
      final capturedResults = <AgentResult>[];

      final producer = _FakeAgent.single(name: 'producer');
      final reviewer = _FakeAgent(
        name: 'reviewer',
        results: [
          const AgentResult(output: 'feedback-0'),
          const AgentResult(output: 'feedback-1'),
        ],
      );

      final loop = AgentLoop(
        context: ctx,
        producer: producer,
        reviewer: reviewer,
        isAccepted: (result, iteration) {
          capturedResults.add(result);
          return iteration == 1;
        },
        maxIterations: 5,
      );

      await loop.run('task');

      expect(capturedResults, hasLength(2));
      expect(capturedResults[0].output, 'feedback-0');
      expect(capturedResults[1].output, 'feedback-1');
    });

    test('receives the correct iteration index', () async {
      final capturedIterations = <int>[];

      final producer = _FakeAgent.single(name: 'producer');
      final reviewer = _FakeAgent.single(name: 'reviewer');

      final loop = AgentLoop(
        context: ctx,
        producer: producer,
        reviewer: reviewer,
        isAccepted: (result, iteration) {
          capturedIterations.add(iteration);
          return iteration == 2;
        },
        maxIterations: 5,
      );

      await loop.run('task');

      expect(capturedIterations, [0, 1, 2]);
    });

    test('can inspect reviewer output to decide acceptance', () async {
      final producer = _FakeAgent.single(name: 'producer');
      final reviewer = _FakeAgent(
        name: 'reviewer',
        results: [
          const AgentResult(output: 'REJECTED'),
          const AgentResult(output: 'REJECTED'),
          const AgentResult(output: 'APPROVED'),
        ],
      );

      final loop = AgentLoop(
        context: ctx,
        producer: producer,
        reviewer: reviewer,
        isAccepted: (result, iteration) => result.output.contains('APPROVED'),
        maxIterations: 5,
      );

      final result = await loop.run('task');

      expect(result.accepted, isTrue);
      expect(result.iterationCount, 3);
    });
  });

  // ── AgentLoop.run() — custom buildProducerPrompt ────────────────────────

  group('AgentLoop.run() — custom buildProducerPrompt', () {
    late Directory tempDir;
    late FileContext ctx;

    setUp(() {
      final result = _tempContext();
      tempDir = result.dir;
      ctx = result.ctx;
    });

    tearDown(() => tempDir.deleteSync(recursive: true));

    test('uses custom prompt builder for producer on iteration 0', () async {
      final producer = _FakeAgent.single(name: 'producer');
      final reviewer = _FakeAgent.single(name: 'reviewer');

      final loop = AgentLoop(
        context: ctx,
        producer: producer,
        reviewer: reviewer,
        isAccepted: (result, iteration) => true,
        buildProducerPrompt: (task, ctx, iteration, prev) async {
          return 'CUSTOM: $task (iteration $iteration)';
        },
      );

      await loop.run('Build widget');

      expect(
        producer.capturedTasks.first,
        'CUSTOM: Build widget (iteration 0)',
      );
    });

    test(
      'custom prompt builder receives previousReviewerResult on iter 1+',
      () async {
        AgentResult? capturedPreviousResult;

        final producer = _FakeAgent(
          name: 'producer',
          results: [
            const AgentResult(output: 'v1'),
            const AgentResult(output: 'v2'),
          ],
        );
        final reviewer = _FakeAgent(
          name: 'reviewer',
          results: [
            const AgentResult(output: 'fix the bug'),
            const AgentResult(output: 'approved'),
          ],
        );

        final loop = AgentLoop(
          context: ctx,
          producer: producer,
          reviewer: reviewer,
          isAccepted: (result, iteration) => iteration == 1,
          buildProducerPrompt: (task, ctx, iteration, prev) async {
            if (iteration == 1) {
              capturedPreviousResult = prev;
            }
            return 'custom prompt iter $iteration';
          },
        );

        await loop.run('task');

        expect(capturedPreviousResult, isNotNull);
        expect(capturedPreviousResult!.output, 'fix the bug');
      },
    );

    test(
      'custom prompt builder receives null previousReviewerResult on iter 0',
      () async {
        AgentResult? capturedPreviousResult = const AgentResult(
          output: 'sentinel',
        );

        final producer = _FakeAgent.single(name: 'producer');
        final reviewer = _FakeAgent.single(name: 'reviewer');

        final loop = AgentLoop(
          context: ctx,
          producer: producer,
          reviewer: reviewer,
          isAccepted: (result, iteration) => true,
          buildProducerPrompt: (task, ctx, iteration, prev) async {
            capturedPreviousResult = prev;
            return 'custom prompt';
          },
        );

        await loop.run('task');

        expect(capturedPreviousResult, isNull);
      },
    );

    test('custom prompt builder receives the original task', () async {
      String? capturedTask;

      final producer = _FakeAgent.single(name: 'producer');
      final reviewer = _FakeAgent.single(name: 'reviewer');

      final loop = AgentLoop(
        context: ctx,
        producer: producer,
        reviewer: reviewer,
        isAccepted: (result, iteration) => true,
        buildProducerPrompt: (task, ctx, iteration, prev) async {
          capturedTask = task;
          return 'custom prompt';
        },
      );

      await loop.run('My original task');

      expect(capturedTask, 'My original task');
    });

    test('custom prompt builder receives the FileContext', () async {
      FileContext? capturedCtx;

      final producer = _FakeAgent.single(name: 'producer');
      final reviewer = _FakeAgent.single(name: 'reviewer');

      final loop = AgentLoop(
        context: ctx,
        producer: producer,
        reviewer: reviewer,
        isAccepted: (result, iteration) => true,
        buildProducerPrompt: (task, context, iteration, prev) async {
          capturedCtx = context;
          return 'custom prompt';
        },
      );

      await loop.run('task');

      expect(capturedCtx, same(ctx));
    });
  });

  // ── AgentLoop.run() — custom buildReviewerPrompt ────────────────────────

  group('AgentLoop.run() — custom buildReviewerPrompt', () {
    late Directory tempDir;
    late FileContext ctx;

    setUp(() {
      final result = _tempContext();
      tempDir = result.dir;
      ctx = result.ctx;
    });

    tearDown(() => tempDir.deleteSync(recursive: true));

    test('uses custom reviewer prompt builder', () async {
      final producer = _FakeAgent.single(
        name: 'producer',
        result: const AgentResult(output: 'my code'),
      );
      final reviewer = _FakeAgent.single(name: 'reviewer');

      final loop = AgentLoop(
        context: ctx,
        producer: producer,
        reviewer: reviewer,
        isAccepted: (result, iteration) => true,
        buildReviewerPrompt: (task, ctx, iteration, producerResult) async {
          return 'CUSTOM REVIEW: ${producerResult.output} for "$task" (iter $iteration)';
        },
      );

      await loop.run('Build feature');

      expect(
        reviewer.capturedTasks.first,
        'CUSTOM REVIEW: my code for "Build feature" (iter 0)',
      );
    });

    test(
      'custom reviewer prompt receives the current producer result',
      () async {
        AgentResult? capturedProducerResult;

        final producer = _FakeAgent.single(
          name: 'producer',
          result: const AgentResult(output: 'produced output', tokensUsed: 42),
        );
        final reviewer = _FakeAgent.single(name: 'reviewer');

        final loop = AgentLoop(
          context: ctx,
          producer: producer,
          reviewer: reviewer,
          isAccepted: (result, iteration) => true,
          buildReviewerPrompt: (task, ctx, iteration, producerResult) async {
            capturedProducerResult = producerResult;
            return 'review prompt';
          },
        );

        await loop.run('task');

        expect(capturedProducerResult, isNotNull);
        expect(capturedProducerResult!.output, 'produced output');
        expect(capturedProducerResult!.tokensUsed, 42);
      },
    );

    test('custom reviewer prompt receives correct iteration index', () async {
      final capturedIterations = <int>[];

      final producer = _FakeAgent(
        name: 'producer',
        results: [
          const AgentResult(output: 'v1'),
          const AgentResult(output: 'v2'),
        ],
      );
      final reviewer = _FakeAgent(
        name: 'reviewer',
        results: [
          const AgentResult(output: 'no'),
          const AgentResult(output: 'yes'),
        ],
      );

      final loop = AgentLoop(
        context: ctx,
        producer: producer,
        reviewer: reviewer,
        isAccepted: (result, iteration) => iteration == 1,
        buildReviewerPrompt: (task, ctx, iteration, producerResult) async {
          capturedIterations.add(iteration);
          return 'review iter $iteration';
        },
      );

      await loop.run('task');

      expect(capturedIterations, [0, 1]);
    });

    test('custom reviewer prompt receives the FileContext', () async {
      FileContext? capturedCtx;

      final producer = _FakeAgent.single(name: 'producer');
      final reviewer = _FakeAgent.single(name: 'reviewer');

      final loop = AgentLoop(
        context: ctx,
        producer: producer,
        reviewer: reviewer,
        isAccepted: (result, iteration) => true,
        buildReviewerPrompt: (task, context, iteration, producerResult) async {
          capturedCtx = context;
          return 'review prompt';
        },
      );

      await loop.run('task');

      expect(capturedCtx, same(ctx));
    });
  });

  // ── AgentLoop.run() — error handling ────────────────────────────────────

  group('AgentLoop.run() — error handling', () {
    late Directory tempDir;
    late FileContext ctx;

    setUp(() {
      final result = _tempContext();
      tempDir = result.dir;
      ctx = result.ctx;
    });

    tearDown(() => tempDir.deleteSync(recursive: true));

    test('producer exception propagates immediately', () async {
      final error = Exception('producer crash');
      final producer = _FakeAgent.throwing(name: 'producer', error: error);
      final reviewer = _FakeAgent.single(name: 'reviewer');

      final loop = AgentLoop(
        context: ctx,
        producer: producer,
        reviewer: reviewer,
        isAccepted: (result, iteration) => true,
      );

      await expectLater(loop.run('task'), throwsA(same(error)));
      // Reviewer should never have been called
      expect(reviewer.callCount, 0);
    });

    test('reviewer exception propagates immediately', () async {
      final error = Exception('reviewer crash');
      final producer = _FakeAgent.single(name: 'producer');
      final reviewer = _FakeAgent.throwing(name: 'reviewer', error: error);

      final loop = AgentLoop(
        context: ctx,
        producer: producer,
        reviewer: reviewer,
        isAccepted: (result, iteration) => true,
      );

      await expectLater(loop.run('task'), throwsA(same(error)));
      // Producer ran once but no second iteration
      expect(producer.callCount, 1);
    });

    test(
      'producer error on iteration 1 propagates after iteration 0 completes',
      () async {
        final error = StateError('producer error on second iteration');
        var producerCallCount = 0;
        final customProducer = _CustomAgent(
          name: 'producer',
          handler: (task, context) async {
            producerCallCount++;
            if (producerCallCount == 2) throw error;
            return const AgentResult(output: 'v1');
          },
        );

        final reviewer = _FakeAgent.single(
          name: 'reviewer',
          result: const AgentResult(output: 'needs work'),
        );

        final loop = AgentLoop(
          context: ctx,
          producer: customProducer,
          reviewer: reviewer,
          isAccepted: (result, iteration) => false,
          maxIterations: 5,
        );

        await expectLater(loop.run('task'), throwsA(same(error)));
        // First iteration completed (producer + reviewer), second iteration producer threw
        expect(producerCallCount, 2);
        expect(reviewer.callCount, 1);
      },
    );
  });

  // ── AgentLoop.run() — duration tracking ─────────────────────────────────

  group('AgentLoop.run() — duration', () {
    late Directory tempDir;
    late FileContext ctx;

    setUp(() {
      final result = _tempContext();
      tempDir = result.dir;
      ctx = result.ctx;
    });

    tearDown(() => tempDir.deleteSync(recursive: true));

    test('duration is non-negative', () async {
      final producer = _FakeAgent.single(name: 'producer');
      final reviewer = _FakeAgent.single(name: 'reviewer');

      final loop = AgentLoop(
        context: ctx,
        producer: producer,
        reviewer: reviewer,
        isAccepted: (result, iteration) => true,
      );

      final result = await loop.run('task');

      expect(result.duration.inMicroseconds, greaterThanOrEqualTo(0));
    });

    test('duration does not exceed wall-clock time', () async {
      final producer = _FakeAgent.single(name: 'producer');
      final reviewer = _FakeAgent.single(name: 'reviewer');

      final loop = AgentLoop(
        context: ctx,
        producer: producer,
        reviewer: reviewer,
        isAccepted: (result, iteration) => true,
      );

      final before = DateTime.now();
      final result = await loop.run('task');
      final after = DateTime.now();

      final wallTime = after.difference(before);
      expect(
        result.duration.inMicroseconds,
        lessThanOrEqualTo(wallTime.inMicroseconds + 100000),
      );
    });
  });

  // ── AgentLoop.run() — default prompt formats ───────────────────────────

  group('AgentLoop.run() — default prompt formats', () {
    late Directory tempDir;
    late FileContext ctx;

    setUp(() {
      final result = _tempContext();
      tempDir = result.dir;
      ctx = result.ctx;
    });

    tearDown(() => tempDir.deleteSync(recursive: true));

    test(
      'default producer prompt on iteration 0 is the original task',
      () async {
        final producer = _FakeAgent.single(name: 'producer');
        final reviewer = _FakeAgent.single(name: 'reviewer');

        final loop = AgentLoop(
          context: ctx,
          producer: producer,
          reviewer: reviewer,
          isAccepted: (result, iteration) => true,
        );

        await loop.run('Original task description');

        expect(producer.capturedTasks[0], 'Original task description');
      },
    );

    test(
      'default producer prompt on iteration 1+ appends feedback section',
      () async {
        final producer = _FakeAgent(
          name: 'producer',
          results: [
            const AgentResult(output: 'v1'),
            const AgentResult(output: 'v2'),
          ],
        );
        final reviewer = _FakeAgent(
          name: 'reviewer',
          results: [
            const AgentResult(output: 'Fix bug in line 42'),
            const AgentResult(output: 'approved'),
          ],
        );

        final loop = AgentLoop(
          context: ctx,
          producer: producer,
          reviewer: reviewer,
          isAccepted: (result, iteration) => iteration == 1,
        );

        await loop.run('Implement sorting');

        // Second producer call should contain:
        // original task + separator + previous feedback + instruction
        final prompt = producer.capturedTasks[1];
        expect(prompt, startsWith('Implement sorting'));
        expect(prompt, contains('\n\n---\n'));
        expect(prompt, contains('Previous review feedback:'));
        expect(prompt, contains('Fix bug in line 42'));
        expect(
          prompt,
          contains('Please address the feedback above and try again.'),
        );
      },
    );

    test('default reviewer prompt format contains required elements', () async {
      final producer = _FakeAgent.single(
        name: 'producer',
        result: const AgentResult(output: 'producer output here'),
      );
      final reviewer = _FakeAgent.single(name: 'reviewer');

      final loop = AgentLoop(
        context: ctx,
        producer: producer,
        reviewer: reviewer,
        isAccepted: (result, iteration) => true,
      );

      await loop.run('Create a REST API');

      final reviewPrompt = reviewer.capturedTasks[0];
      expect(reviewPrompt, contains('Review the following output'));
      expect(reviewPrompt, contains('meets the requirements'));
      expect(reviewPrompt, contains('Original task:'));
      expect(reviewPrompt, contains('Create a REST API'));
      expect(reviewPrompt, contains('Producer output:'));
      expect(reviewPrompt, contains('producer output here'));
    });
  });

  // ── AgentLoop.run() — both custom prompts together ─────────────────────

  group('AgentLoop.run() — both custom prompt builders', () {
    late Directory tempDir;
    late FileContext ctx;

    setUp(() {
      final result = _tempContext();
      tempDir = result.dir;
      ctx = result.ctx;
    });

    tearDown(() => tempDir.deleteSync(recursive: true));

    test('custom producer and reviewer prompts are both used', () async {
      final producer = _FakeAgent.single(name: 'producer');
      final reviewer = _FakeAgent.single(name: 'reviewer');

      final loop = AgentLoop(
        context: ctx,
        producer: producer,
        reviewer: reviewer,
        isAccepted: (result, iteration) => true,
        buildProducerPrompt: (task, ctx, iter, prev) async => 'PROD: $task',
        buildReviewerPrompt: (task, ctx, iter, pr) async => 'REV: ${pr.output}',
      );

      await loop.run('task');

      expect(producer.capturedTasks.first, 'PROD: task');
      expect(reviewer.capturedTasks.first, 'REV: fake output');
    });
  });

  // ── AgentLoop.run() — edge cases ───────────────────────────────────────

  group('AgentLoop.run() — edge cases', () {
    late Directory tempDir;
    late FileContext ctx;

    setUp(() {
      final result = _tempContext();
      tempDir = result.dir;
      ctx = result.ctx;
    });

    tearDown(() => tempDir.deleteSync(recursive: true));

    test('empty task string is passed through to producer', () async {
      final producer = _FakeAgent.single(name: 'producer');
      final reviewer = _FakeAgent.single(name: 'reviewer');

      final loop = AgentLoop(
        context: ctx,
        producer: producer,
        reviewer: reviewer,
        isAccepted: (result, iteration) => true,
      );

      await loop.run('');

      expect(producer.capturedTasks.first, '');
    });

    test('large maxIterations only runs as many as needed', () async {
      final producer = _FakeAgent.single(name: 'producer');
      final reviewer = _FakeAgent.single(name: 'reviewer');

      final loop = AgentLoop(
        context: ctx,
        producer: producer,
        reviewer: reviewer,
        isAccepted: (result, iteration) => iteration == 0,
        maxIterations: 100,
      );

      final result = await loop.run('task');

      expect(result.accepted, isTrue);
      expect(result.iterationCount, 1);
      expect(producer.callCount, 1);
      expect(reviewer.callCount, 1);
    });

    test('producer and reviewer can be the same agent instance', () async {
      final agent = _FakeAgent.single(
        name: 'dual',
        result: const AgentResult(output: 'output', tokensUsed: 10),
      );

      final loop = AgentLoop(
        context: ctx,
        producer: agent,
        reviewer: agent,
        isAccepted: (result, iteration) => true,
      );

      final result = await loop.run('task');

      expect(agent.callCount, 2); // once as producer, once as reviewer
      expect(result.totalTokensUsed, 20);
    });

    test(
      'iteration with zero tokensUsed agents results in totalTokensUsed = 0',
      () async {
        final producer = _FakeAgent.single(
          name: 'producer',
          result: const AgentResult(output: 'out', tokensUsed: 0),
        );
        final reviewer = _FakeAgent.single(
          name: 'reviewer',
          result: const AgentResult(output: 'review', tokensUsed: 0),
        );

        final loop = AgentLoop(
          context: ctx,
          producer: producer,
          reviewer: reviewer,
          isAccepted: (result, iteration) => true,
        );

        final result = await loop.run('task');

        expect(result.totalTokensUsed, 0);
      },
    );

    test(
      'isAccepted receives correct reviewer result for each iteration',
      () async {
        // Verify the correlation between the reviewer result and isAccepted
        final reviewerOutputs = <String>[];

        final producer = _FakeAgent(
          name: 'producer',
          results: [
            const AgentResult(output: 'p0'),
            const AgentResult(output: 'p1'),
            const AgentResult(output: 'p2'),
          ],
        );
        final reviewer = _FakeAgent(
          name: 'reviewer',
          results: [
            const AgentResult(output: 'review-0'),
            const AgentResult(output: 'review-1'),
            const AgentResult(output: 'review-2'),
          ],
        );

        final loop = AgentLoop(
          context: ctx,
          producer: producer,
          reviewer: reviewer,
          isAccepted: (result, iteration) {
            reviewerOutputs.add(result.output);
            return iteration == 2;
          },
          maxIterations: 5,
        );

        await loop.run('task');

        expect(reviewerOutputs, ['review-0', 'review-1', 'review-2']);
      },
    );
  });

  // ── AgentLoop.run() — execution order ──────────────────────────────────

  group('AgentLoop.run() — execution order', () {
    late Directory tempDir;
    late FileContext ctx;

    setUp(() {
      final result = _tempContext();
      tempDir = result.dir;
      ctx = result.ctx;
    });

    tearDown(() => tempDir.deleteSync(recursive: true));

    test('producer runs before reviewer in each iteration', () async {
      final executionLog = <String>[];

      final producer = _CustomAgent(
        name: 'producer',
        handler: (task, context) async {
          executionLog.add('producer');
          return const AgentResult(output: 'produced');
        },
      );
      final reviewer = _CustomAgent(
        name: 'reviewer',
        handler: (task, context) async {
          executionLog.add('reviewer');
          return const AgentResult(output: 'reviewed');
        },
      );

      final loop = AgentLoop(
        context: ctx,
        producer: producer,
        reviewer: reviewer,
        isAccepted: (result, iteration) => true,
      );

      await loop.run('task');

      expect(executionLog, ['producer', 'reviewer']);
    });

    test('iterations execute in sequence: p0, r0, p1, r1, ...', () async {
      final executionLog = <String>[];

      final producer = _CustomAgent(
        name: 'producer',
        handler: (task, context) async {
          final iteration = executionLog.where((e) => e.startsWith('p')).length;
          executionLog.add('p$iteration');
          return AgentResult(output: 'p$iteration');
        },
      );
      final reviewer = _CustomAgent(
        name: 'reviewer',
        handler: (task, context) async {
          final iteration = executionLog.where((e) => e.startsWith('r')).length;
          executionLog.add('r$iteration');
          return AgentResult(output: 'r$iteration');
        },
      );

      final loop = AgentLoop(
        context: ctx,
        producer: producer,
        reviewer: reviewer,
        isAccepted: (result, iteration) => iteration == 2,
        maxIterations: 5,
      );

      await loop.run('task');

      expect(executionLog, ['p0', 'r0', 'p1', 'r1', 'p2', 'r2']);
    });
  });
}

// ---------------------------------------------------------------------------
// Custom agent helper for fine-grained control over behavior
// ---------------------------------------------------------------------------

/// A custom [Agent] that delegates [run] to a callback.
class _CustomAgent extends Agent {
  _CustomAgent({
    required super.name,
    required Future<AgentResult> Function(String, FileContext?) handler,
  }) : _handler = handler,
       super(
         client: LmStudioClient(AgentsCoreConfig(logger: const SilentLogger())),
         config: AgentsCoreConfig(logger: const SilentLogger()),
       );

  final Future<AgentResult> Function(String, FileContext?) _handler;
  int callCount = 0;

  @override
  Future<AgentResult> run(String task, {FileContext? context}) async {
    callCount++;
    return _handler(task, context);
  }
}
