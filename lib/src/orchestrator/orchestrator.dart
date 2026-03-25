// ignore_for_file: prefer_initializing_formals

import '../agent/agent.dart';
import '../agent/agent_result.dart';
import '../context/file_context.dart';

/// Policy that controls how the [Orchestrator] handles step failures.
///
/// - [stop] — propagate the exception immediately and halt execution.
/// - [continueOnError] — catch the exception, record it in
///   [OrchestratorResult.errors], and continue with the next step.
enum OrchestratorErrorPolicy {
  /// Stop execution immediately and rethrow the exception.
  stop,

  /// Catch the exception, add it to the errors list, and continue.
  continueOnError,
}

/// A single step in an [Orchestrator] pipeline.
///
/// Each step pairs an [agent] with a [taskPrompt] that can be either a
/// static [String] or a dynamic function that resolves at runtime using
/// the orchestrator's [FileContext].
///
/// An optional [condition] callback decides whether the step should run.
/// When the condition returns `false`, the step is skipped entirely (its
/// agent is not invoked and no result is recorded).
///
/// ```dart
/// // Static prompt
/// AgentStep(agent: myAgent, taskPrompt: 'Summarise the report');
///
/// // Dynamic prompt
/// AgentStep.dynamic(
///   agent: myAgent,
///   taskPrompt: (ctx) async => 'Process: ${ctx.read("input.txt")}',
/// );
/// ```
class AgentStep {
  /// Creates an [AgentStep] with a static [String] task prompt.
  ///
  /// [agent] is the agent that will execute this step.
  /// [taskPrompt] is the literal prompt string passed to [Agent.run].
  /// [condition] is an optional guard; when it returns `false` the step
  /// is skipped.
  const AgentStep({
    required this.agent,
    required String taskPrompt,
    this.condition,
  }) : taskPrompt = taskPrompt;

  /// Creates an [AgentStep] with a dynamic task prompt that is resolved
  /// at runtime.
  ///
  /// [taskPrompt] receives the orchestrator's [FileContext] and returns
  /// the prompt string. This allows building prompts from workspace state
  /// (e.g. reading files produced by earlier steps).
  ///
  /// [condition] is an optional guard; when it returns `false` the step
  /// is skipped.
  const AgentStep.dynamic({
    required this.agent,
    required Future<String> Function(FileContext) taskPrompt,
    this.condition,
  }) : taskPrompt = taskPrompt;

  /// The agent that executes this step.
  final Agent agent;

  /// The task prompt — either a [String] or a
  /// `Future<String> Function(FileContext)` that is awaited at runtime.
  final Object taskPrompt;

  /// An optional guard condition evaluated before the step runs.
  ///
  /// When `null`, the step always executes. When provided, the step is
  /// skipped if the function returns `false`.
  final Future<bool> Function(FileContext)? condition;
}

/// The result of an [Orchestrator.run] invocation.
///
/// Contains the [AgentResult] from each successfully executed step, the
/// total [duration] of the run, and any [errors] captured when using
/// [OrchestratorErrorPolicy.continueOnError].
///
/// ```dart
/// final result = await orchestrator.run();
/// print('Steps: ${result.stepResults.length}');
/// print('Duration: ${result.duration}');
/// if (result.hasErrors) print('Errors: ${result.errors}');
/// ```
class OrchestratorResult {
  /// Creates an [OrchestratorResult].
  const OrchestratorResult({
    required this.stepResults,
    required this.duration,
    this.errors = const [],
  });

  /// The [AgentResult] from each successfully executed step, in execution
  /// order.
  ///
  /// Skipped steps (condition returned `false`) and failed steps (when using
  /// [OrchestratorErrorPolicy.continueOnError]) are **not** included.
  final List<AgentResult> stepResults;

  /// The wall-clock duration of the entire [Orchestrator.run] call.
  final Duration duration;

  /// Exceptions caught during the run when using
  /// [OrchestratorErrorPolicy.continueOnError].
  ///
  /// Empty when all steps succeed or when [OrchestratorErrorPolicy.stop]
  /// is in effect (because the first error is rethrown).
  final List<Object> errors;

  /// Whether any errors were captured during the run.
  bool get hasErrors => errors.isNotEmpty;
}

/// Sequences agent execution through a pipeline of [AgentStep]s.
///
/// The [Orchestrator] iterates through [steps] in order, evaluating each
/// step's optional [AgentStep.condition], resolving dynamic prompts, and
/// collecting results.
///
/// Error handling is controlled by [onError]:
/// - [OrchestratorErrorPolicy.stop] (default) — rethrow on first failure.
/// - [OrchestratorErrorPolicy.continueOnError] — catch, record, continue.
///
/// ```dart
/// final orch = Orchestrator(
///   context: fileContext,
///   steps: [
///     AgentStep(agent: researcher, taskPrompt: 'Research topic X'),
///     AgentStep(agent: writer, taskPrompt: 'Write summary'),
///   ],
/// );
/// final result = await orch.run();
/// ```
class Orchestrator {
  /// Creates an [Orchestrator].
  ///
  /// [context] is the shared [FileContext] passed to every step's agent
  /// and available to conditions and dynamic prompts.
  ///
  /// [steps] defines the pipeline of agent invocations to execute.
  ///
  /// [onError] controls failure behaviour. Defaults to
  /// [OrchestratorErrorPolicy.stop].
  const Orchestrator({
    required this.context,
    required this.steps,
    this.onError = OrchestratorErrorPolicy.stop,
  });

  /// The shared workspace context for all steps.
  final FileContext context;

  /// The ordered list of steps to execute.
  final List<AgentStep> steps;

  /// The error-handling policy for step failures.
  final OrchestratorErrorPolicy onError;

  /// Executes all [steps] sequentially and returns an [OrchestratorResult].
  ///
  /// For each step:
  /// 1. If [AgentStep.condition] is non-null, await it; skip the step when
  ///    it returns `false`.
  /// 2. Resolve the task prompt — use as-is for [String], or await the
  ///    function for dynamic prompts.
  /// 3. Call [Agent.run] with the resolved prompt and [context].
  /// 4. On success, add the [AgentResult] to `stepResults`.
  /// 5. On failure, either rethrow ([OrchestratorErrorPolicy.stop]) or
  ///    capture the error and continue
  ///    ([OrchestratorErrorPolicy.continueOnError]).
  ///
  /// The returned [OrchestratorResult.duration] reflects the wall-clock
  /// time of the entire run.
  Future<OrchestratorResult> run() async {
    final stopwatch = Stopwatch()..start();
    final stepResults = <AgentResult>[];
    final errors = <Object>[];

    for (final step in steps) {
      // 1. Evaluate condition — skip step if false.
      if (step.condition != null) {
        final shouldRun = await step.condition!(context);
        if (!shouldRun) continue;
      }

      // 2. Resolve the task prompt.
      final String resolvedPrompt;
      final prompt = step.taskPrompt;
      if (prompt is String) {
        resolvedPrompt = prompt;
      } else {
        resolvedPrompt =
            await (prompt as Future<String> Function(FileContext))(context);
      }

      // 3. Execute the agent.
      try {
        final result = await step.agent.run(resolvedPrompt, context: context);
        stepResults.add(result);
      } catch (e) {
        if (onError == OrchestratorErrorPolicy.stop) rethrow;
        errors.add(e);
      }
    }

    stopwatch.stop();

    return OrchestratorResult(
      stepResults: stepResults,
      duration: stopwatch.elapsed,
      errors: errors,
    );
  }
}
