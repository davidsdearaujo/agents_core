import '../agent/agent.dart';
import '../agent/agent_result.dart';
import '../context/file_context.dart';

/// A single iteration record in an [AgentLoop] run.
///
/// Each iteration captures the zero-based [index], the [producerResult] from
/// the producing agent, and the [reviewerResult] from the reviewing agent.
///
/// ```dart
/// for (final iteration in loopResult.iterations) {
///   print('Iteration ${iteration.index}: '
///       'producer tokens=${iteration.producerResult.tokensUsed}, '
///       'reviewer tokens=${iteration.reviewerResult.tokensUsed}');
/// }
/// ```
class AgentLoopIteration {
  /// Creates an [AgentLoopIteration].
  ///
  /// [index] is the zero-based iteration number.
  /// [producerResult] is the result from the producer agent for this iteration.
  /// [reviewerResult] is the result from the reviewer agent for this iteration.
  const AgentLoopIteration({
    required this.index,
    required this.producerResult,
    required this.reviewerResult,
  });

  /// The zero-based iteration index.
  final int index;

  /// The result produced by the producer agent in this iteration.
  final AgentResult producerResult;

  /// The result produced by the reviewer agent in this iteration.
  final AgentResult reviewerResult;
}

/// The overall result of an [AgentLoop.run] invocation.
///
/// Contains all [iterations], whether the reviewer [accepted] the output,
/// the wall-clock [duration], and the [totalTokensUsed] across every agent
/// run.
///
/// ```dart
/// final result = await loop.run('Implement feature X');
/// print('Accepted: ${result.accepted}');
/// print('Iterations: ${result.iterationCount}');
/// print('Total tokens: ${result.totalTokensUsed}');
/// ```
class AgentLoopResult {
  /// Creates an [AgentLoopResult].
  ///
  /// [iterations] contains all iteration records in execution order.
  /// [accepted] is `true` when the reviewer accepted the producer's output.
  /// [duration] is the wall-clock time of the entire loop.
  /// [totalTokensUsed] is the sum of all agent runs' `tokensUsed`.
  const AgentLoopResult({
    required this.iterations,
    required this.accepted,
    required this.duration,
    required this.totalTokensUsed,
  });

  /// All iteration records in execution order.
  final List<AgentLoopIteration> iterations;

  /// Whether the reviewer accepted the producer's output.
  ///
  /// `true` when [isAccepted] returned `true` for the reviewer result.
  /// `false` when [AgentLoop.maxIterations] was reached without acceptance.
  final bool accepted;

  /// The wall-clock duration of the entire [AgentLoop.run] call.
  final Duration duration;

  /// The sum of all `tokensUsed` across every producer and reviewer run.
  final int totalTokensUsed;

  /// The number of iterations executed.
  int get iterationCount => iterations.length;

  /// The [AgentResult] from the last producer run.
  ///
  /// Throws [StateError] if [iterations] is empty.
  AgentResult get lastProducerResult => iterations.last.producerResult;

  /// The [AgentResult] from the last reviewer run.
  ///
  /// Throws [StateError] if [iterations] is empty.
  AgentResult get lastReviewerResult => iterations.last.reviewerResult;

  /// Whether the loop ended because [AgentLoop.maxIterations] was reached
  /// without the reviewer accepting.
  bool get reachedMaxIterations => !accepted;
}

/// Orchestrates a produce-review loop between two agents.
///
/// The [AgentLoop] runs a [producer] agent and a [reviewer] agent in a tight
/// loop. Each iteration, the producer generates output and the reviewer
/// evaluates it. The loop continues until the reviewer accepts the output
/// (as determined by [isAccepted]) or [maxIterations] is reached.
///
/// This is useful for iterative refinement workflows — e.g. a developer
/// agent writes code and a QA agent reviews it, with feedback looping back
/// until quality criteria are met.
///
/// ```dart
/// final loop = AgentLoop(
///   context: fileContext,
///   producer: devAgent,
///   reviewer: qaAgent,
///   isAccepted: (result, iteration) =>
///       result.output.contains('APPROVED'),
/// );
/// final result = await loop.run('Implement the login feature');
/// if (result.accepted) {
///   print('Accepted after ${result.iterationCount} iterations');
/// }
/// ```
class AgentLoop {
  /// Creates an [AgentLoop].
  ///
  /// [context] is the shared [FileContext] passed to both agents.
  ///
  /// [producer] is the agent that generates work each iteration.
  ///
  /// [reviewer] is the agent that evaluates the producer's output.
  ///
  /// [isAccepted] determines whether the reviewer's result constitutes
  /// acceptance. Receives the reviewer's [AgentResult] and the zero-based
  /// iteration index.
  ///
  /// [maxIterations] is the safety limit to prevent infinite loops.
  /// Defaults to `5`.
  ///
  /// [buildProducerPrompt] optionally customises the prompt sent to the
  /// producer. When `null`, a default prompt is used that includes the
  /// original task and (from iteration 1+) the reviewer's feedback.
  ///
  /// [buildReviewerPrompt] optionally customises the prompt sent to the
  /// reviewer. When `null`, a default prompt is used that includes the
  /// original task and the producer's output.
  const AgentLoop({
    required this.context,
    required this.producer,
    required this.reviewer,
    required this.isAccepted,
    this.maxIterations = 5,
    this.buildProducerPrompt,
    this.buildReviewerPrompt,
  });

  /// The shared workspace context for both agents.
  final FileContext context;

  /// The agent that produces work each iteration.
  final Agent producer;

  /// The agent that reviews the producer's output each iteration.
  final Agent reviewer;

  /// Determines whether the reviewer accepted the producer's output.
  ///
  /// Receives the reviewer's [AgentResult] and the zero-based iteration
  /// index. Return `true` to stop the loop and mark the result as accepted.
  final bool Function(AgentResult reviewerResult, int iteration) isAccepted;

  /// The maximum number of produce-review iterations.
  ///
  /// When reached without acceptance, the loop returns with
  /// [AgentLoopResult.accepted] set to `false`.
  final int maxIterations;

  /// Optional custom prompt builder for the producer agent.
  ///
  /// Receives the original task, the shared [FileContext], the current
  /// iteration index, and the previous reviewer result (null on first
  /// iteration).
  final Future<String> Function(
    String originalTask,
    FileContext context,
    int iteration,
    AgentResult? previousReviewerResult,
  )? buildProducerPrompt;

  /// Optional custom prompt builder for the reviewer agent.
  ///
  /// Receives the original task, the shared [FileContext], the current
  /// iteration index, and the producer's result for this iteration.
  final Future<String> Function(
    String originalTask,
    FileContext context,
    int iteration,
    AgentResult producerResult,
  )? buildReviewerPrompt;

  /// Executes the produce-review loop and returns an [AgentLoopResult].
  ///
  /// For each iteration:
  /// 1. Build the producer prompt (default or custom via [buildProducerPrompt]).
  /// 2. Run [producer] with the resolved prompt and [context].
  /// 3. Build the reviewer prompt (default or custom via [buildReviewerPrompt]).
  /// 4. Run [reviewer] with the resolved prompt and [context].
  /// 5. Record the [AgentLoopIteration].
  /// 6. If [isAccepted] returns `true`, set `accepted = true` and break.
  ///
  /// Exceptions from either agent propagate immediately — there is no
  /// error-policy mechanism because partial loop results are not useful.
  ///
  /// The returned [AgentLoopResult.duration] reflects the wall-clock time
  /// of the entire run.
  Future<AgentLoopResult> run(String task) async {
    final stopwatch = Stopwatch()..start();
    final iterations = <AgentLoopIteration>[];
    var accepted = false;
    var totalTokens = 0;
    AgentResult? previousReviewerResult;

    for (var i = 0; i < maxIterations; i++) {
      // 1. Build producer prompt.
      final String producerPrompt;
      if (buildProducerPrompt != null) {
        producerPrompt = await buildProducerPrompt!(
          task,
          context,
          i,
          previousReviewerResult,
        );
      } else {
        producerPrompt = _defaultProducerPrompt(task, i, previousReviewerResult);
      }

      // 2. Run producer.
      final producerResult = await producer.run(
        producerPrompt,
        context: context,
      );
      totalTokens += producerResult.tokensUsed;

      // 3. Build reviewer prompt.
      final String reviewerPrompt;
      if (buildReviewerPrompt != null) {
        reviewerPrompt = await buildReviewerPrompt!(
          task,
          context,
          i,
          producerResult,
        );
      } else {
        reviewerPrompt = _defaultReviewerPrompt(task, producerResult);
      }

      // 4. Run reviewer.
      final reviewerResult = await reviewer.run(
        reviewerPrompt,
        context: context,
      );
      totalTokens += reviewerResult.tokensUsed;

      // 5. Record iteration.
      iterations.add(AgentLoopIteration(
        index: i,
        producerResult: producerResult,
        reviewerResult: reviewerResult,
      ));

      // 6. Check acceptance.
      if (isAccepted(reviewerResult, i)) {
        accepted = true;
        break;
      }

      previousReviewerResult = reviewerResult;
    }

    stopwatch.stop();

    return AgentLoopResult(
      iterations: iterations,
      accepted: accepted,
      duration: stopwatch.elapsed,
      totalTokensUsed: totalTokens,
    );
  }

  /// Default producer prompt for iteration 0: the original task as-is.
  /// For iteration 1+: the original task plus the reviewer's feedback.
  String _defaultProducerPrompt(
    String task,
    int iteration,
    AgentResult? previousReviewerResult,
  ) {
    if (iteration == 0 || previousReviewerResult == null) {
      return task;
    }
    return '$task\n\n---\n'
        'Previous review feedback:\n'
        '${previousReviewerResult.output}\n\n'
        'Please address the feedback above and try again.';
  }

  /// Default reviewer prompt: asks the reviewer to evaluate the producer's
  /// output against the original task.
  String _defaultReviewerPrompt(String task, AgentResult producerResult) {
    return 'Review the following output and determine if it meets the '
        'requirements.\n\n'
        'Original task: $task\n\n'
        'Producer output:\n'
        '${producerResult.output}';
  }
}
