// ignore_for_file: prefer_initializing_formals

import '../agent/agent.dart';
import '../agent/agent_result.dart';
import '../context/file_context.dart';

/// Abstract base class for all steps in an [Orchestrator] pipeline.
///
/// Each step carries a [taskPrompt] and an optional [condition] guard.
/// Concrete subclasses define how the step is executed:
///
/// - [AgentStep] — runs a single agent once.
/// - [AgentLoopStep] — runs a produce-review loop between two agents.
///
/// The [taskPrompt] is typed as [Object] to allow both:
/// - A static [String] prompt, and
/// - A `Future<String> Function(FileContext)` that resolves at runtime.
///
/// ```dart
/// // Concrete subclasses satisfy the abstract getters:
/// final step = AgentStep(agent: myAgent, taskPrompt: 'Summarise the report');
/// print(step.taskPrompt); // 'Summarise the report'
/// print(step.condition);  // null — step always runs
/// ```
abstract class OrchestratorStep {
  /// Const constructor for subclasses.
  const OrchestratorStep();

  /// The task prompt — either a [String] or a
  /// `Future<String> Function(FileContext)` that is awaited at runtime.
  Object get taskPrompt;

  /// An optional guard condition evaluated before the step runs.
  ///
  /// When `null`, the step always executes. When provided, the step is
  /// skipped if the function returns `false`.
  Future<bool> Function(FileContext)? get condition;
}

/// An [OrchestratorStep] that runs a produce-review [AgentLoop].
///
/// Holds all [AgentLoop] configuration **except** the shared [FileContext],
/// which the [Orchestrator] provides at runtime. This allows the same step
/// definition to be reused across different orchestrator contexts.
///
/// The [taskPrompt] can be a static [String] or a dynamic function that
/// resolves at runtime using the orchestrator's [FileContext]:
///
/// ```dart
/// // Static prompt
/// AgentLoopStep(
///   producer: devAgent,
///   reviewer: qaAgent,
///   isAccepted: (result, i) => result.output.contains('APPROVED'),
///   taskPrompt: 'Implement the login feature',
/// );
///
/// // Dynamic prompt
/// AgentLoopStep.dynamic(
///   producer: devAgent,
///   reviewer: qaAgent,
///   isAccepted: (result, i) => result.output.contains('APPROVED'),
///   taskPrompt: (ctx) async => 'Fix: ${await ctx.read("errors.log")}',
/// );
/// ```
class AgentLoopStep extends OrchestratorStep {
  /// Creates an [AgentLoopStep] with a static [String] task prompt.
  ///
  /// [producer] is the agent that generates work each iteration.
  ///
  /// [reviewer] is the agent that evaluates the producer's output.
  ///
  /// [isAccepted] determines whether the reviewer's result constitutes
  /// acceptance. Receives the reviewer's [AgentResult] and the zero-based
  /// iteration index.
  ///
  /// [taskPrompt] is the literal prompt string passed to [AgentLoop.run].
  ///
  /// [maxIterations] is the safety limit to prevent infinite loops.
  /// Defaults to `5`.
  ///
  /// [buildProducerPrompt] optionally customises the prompt sent to the
  /// producer. When `null`, [AgentLoop] uses its default prompt.
  ///
  /// [buildReviewerPrompt] optionally customises the prompt sent to the
  /// reviewer. When `null`, [AgentLoop] uses its default prompt.
  ///
  /// [condition] is an optional guard; when it returns `false` the step
  /// is skipped.
  AgentLoopStep({
    required this.producer,
    required this.reviewer,
    required this.isAccepted,
    required String taskPrompt,
    this.maxIterations = 5,
    this.buildProducerPrompt,
    this.buildReviewerPrompt,
    this.condition,
  }) : taskPrompt = taskPrompt;

  /// Creates an [AgentLoopStep] with a dynamic task prompt that is resolved
  /// at runtime.
  ///
  /// [taskPrompt] receives the orchestrator's [FileContext] and returns
  /// the prompt string. This allows building prompts from workspace state
  /// (e.g. reading files produced by earlier steps).
  ///
  /// [condition] is an optional guard; when it returns `false` the step
  /// is skipped.
  AgentLoopStep.dynamic({
    required this.producer,
    required this.reviewer,
    required this.isAccepted,
    required Future<String> Function(FileContext) taskPrompt,
    this.maxIterations = 5,
    this.buildProducerPrompt,
    this.buildReviewerPrompt,
    this.condition,
  }) : taskPrompt = taskPrompt;

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
  /// [AgentLoopResult.accepted] set to `false`. Defaults to `5`.
  final int maxIterations;

  /// Optional custom prompt builder for the producer agent.
  ///
  /// Receives the original task, the shared [FileContext], the current
  /// iteration index, and the previous reviewer result (`null` on first
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

  @override
  final Object taskPrompt;

  @override
  final Future<bool> Function(FileContext)? condition;
}
