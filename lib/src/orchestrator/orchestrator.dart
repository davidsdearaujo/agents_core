// ignore_for_file: prefer_initializing_formals

import '../agent/agent.dart';
import '../context/file_context.dart';
import 'orchestrator_step.dart';
import 'step_result.dart';
import 'task_prompt.dart';

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
class AgentStep extends OrchestratorStep {
  /// Creates an [AgentStep] with a static [String] task prompt.
  ///
  /// [agent] is the agent that will execute this step.
  /// [taskPrompt] is the literal prompt string passed to [Agent.run].
  /// [condition] is an optional guard; when it returns `false` the step
  /// is skipped.
  AgentStep({required this.agent, required String taskPrompt, this.condition})
    : taskPrompt = StaticPrompt(taskPrompt);

  /// Creates an [AgentStep] with a dynamic task prompt that is resolved
  /// at runtime.
  ///
  /// [taskPrompt] receives the orchestrator's [FileContext] and returns
  /// the prompt string. This allows building prompts from workspace state
  /// (e.g. reading files produced by earlier steps).
  ///
  /// [condition] is an optional guard; when it returns `false` the step
  /// is skipped.
  AgentStep.dynamic({
    required this.agent,
    required Future<String> Function(FileContext) taskPrompt,
    this.condition,
  }) : taskPrompt = DynamicPrompt(taskPrompt);

  /// The agent that executes this step.
  final Agent agent;

  /// The task prompt — either a [StaticPrompt] (compile-time string) or a
  /// [DynamicPrompt] (resolved at runtime from the [FileContext]).
  @override
  final TaskPrompt taskPrompt;

  /// An optional guard condition evaluated before the step runs.
  ///
  /// When `null`, the step always executes. When provided, the step is
  /// skipped if the function returns `false`.
  @override
  final Future<bool> Function(FileContext)? condition;

  /// Runs [agent] with [resolvedPrompt] and wraps the result in an
  /// [AgentStepResult].
  @override
  Future<StepResult> execute(FileContext context, String resolvedPrompt) async {
    final result = await agent.run(resolvedPrompt, context: context);
    return AgentStepResult(agentResult: result);
  }
}

/// The result of an [Orchestrator.run] invocation.
///
/// Contains the [StepResult] from each successfully executed step, the
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

  /// The [StepResult] from each successfully executed step, in execution
  /// order.
  ///
  /// Each entry is either an [AgentStepResult] (from an [AgentStep]) or an
  /// [AgentLoopStepResult] (from an [AgentLoopStep]). Skipped steps
  /// (condition returned `false`) and failed steps (when using
  /// [OrchestratorErrorPolicy.continueOnError]) are **not** included.
  final List<StepResult> stepResults;

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

/// Sequences execution through a pipeline of [OrchestratorStep]s.
///
/// The [Orchestrator] iterates through [steps] in order, evaluating each
/// step's optional [OrchestratorStep.condition], resolving dynamic prompts
/// via an exhaustive switch on [TaskPrompt], then dispatching to each step's
/// [OrchestratorStep.execute] method polymorphically.
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
///     AgentLoopStep(
///       producer: devAgent,
///       reviewer: qaAgent,
///       isAccepted: (r, i) => r.output.contains('APPROVED'),
///       taskPrompt: 'Implement feature Y',
///     ),
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
  /// [steps] defines the pipeline of [OrchestratorStep]s to execute.
  /// Each step can be an [AgentStep] or an [AgentLoopStep].
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
  final List<OrchestratorStep> steps;

  /// The error-handling policy for step failures.
  final OrchestratorErrorPolicy onError;

  /// Executes all [steps] sequentially and returns an [OrchestratorResult].
  ///
  /// For each step:
  /// 1. If [OrchestratorStep.condition] is non-null, await it; skip the step
  ///    when it returns `false`.
  /// 2. Resolve the task prompt via an exhaustive switch on [TaskPrompt] —
  ///    [StaticPrompt] is used directly; [DynamicPrompt] is awaited with the
  ///    shared [context].
  /// 3. Dispatch to [OrchestratorStep.execute] polymorphically — no
  ///    type-switches. Custom step types work without modifying this class.
  /// 4. On success, add the [StepResult] to `stepResults`.
  /// 5. On failure, either rethrow ([OrchestratorErrorPolicy.stop]) or
  ///    capture the error and continue
  ///    ([OrchestratorErrorPolicy.continueOnError]).
  ///
  /// The returned [OrchestratorResult.duration] reflects the wall-clock
  /// time of the entire run.
  Future<OrchestratorResult> run() async {
    final stopwatch = Stopwatch()..start();
    final stepResults = <StepResult>[];
    final errors = <Object>[];

    for (final step in steps) {
      // 1. Evaluate condition — skip step if false.
      if (step.condition != null) {
        final shouldRun = await step.condition!(context);
        if (!shouldRun) continue;
      }

      // 2. Resolve the task prompt via exhaustive switch — no runtime casts.
      final resolvedPrompt = switch (step.taskPrompt) {
        StaticPrompt(:final value) => value,
        DynamicPrompt(:final resolver) => await resolver(context),
      };

      // 3. Execute the step polymorphically — open to extension without
      //    modification (Open/Closed Principle).
      try {
        final result = await step.execute(context, resolvedPrompt);
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
