import '../agent/agent_result.dart';
import 'agent_loop.dart';

/// Abstract base class for step results in an [Orchestrator] pipeline.
///
/// Each concrete subclass wraps the result of a specific step type:
///
/// - [AgentStepResult] — wraps the [AgentResult] from a single-agent step.
/// - [AgentLoopStepResult] — wraps the [AgentLoopResult] from a produce-review
///   loop step.
///
/// Common accessors [output] and [tokensUsed] are available on all subtypes,
/// enabling uniform processing without type checks. Use pattern matching or
/// type checks to access step-specific details:
///
/// ```dart
/// for (final result in orchestratorResult.stepResults) {
///   print('Output: ${result.output}');
///   print('Tokens: ${result.tokensUsed}');
///
///   if (result is AgentStepResult) {
///     print('Agent output: ${result.agentResult.output}');
///   } else if (result is AgentLoopStepResult) {
///     print('Loop accepted: ${result.accepted}');
///     print('Iterations: ${result.iterationCount}');
///   }
/// }
/// ```
abstract class StepResult {
  /// Const constructor for subclasses.
  const StepResult();

  /// The primary text output of this step.
  String get output;

  /// Total tokens consumed by this step.
  int get tokensUsed;
}

/// The result of an [AgentStep] execution.
///
/// Wraps the [AgentResult] returned by the single agent run.
///
/// ```dart
/// final stepResult = AgentStepResult(agentResult: result);
/// print(stepResult.output);     // The agent's text response
/// print(stepResult.tokensUsed); // Token count from the run
/// ```
class AgentStepResult extends StepResult {
  /// Creates an [AgentStepResult].
  ///
  /// [agentResult] is the result from the agent's [Agent.run] invocation.
  const AgentStepResult({required this.agentResult});

  /// The result from the agent that executed this step.
  final AgentResult agentResult;

  @override
  String get output => agentResult.output;

  @override
  int get tokensUsed => agentResult.tokensUsed;

  @override
  String toString() => 'AgentStepResult($agentResult)';
}

/// The result of an [AgentLoopStep] execution.
///
/// Wraps the [AgentLoopResult] returned by the produce-review loop and
/// provides convenient accessors for loop-specific details.
///
/// ```dart
/// final stepResult = AgentLoopStepResult(agentLoopResult: loopResult);
/// print(stepResult.output);         // Last producer's text output
/// print(stepResult.accepted);       // Whether the reviewer accepted
/// print(stepResult.iterationCount); // Number of iterations executed
/// ```
class AgentLoopStepResult extends StepResult {
  /// Creates an [AgentLoopStepResult].
  ///
  /// [agentLoopResult] is the result from the [AgentLoop.run] invocation.
  const AgentLoopStepResult({required this.agentLoopResult});

  /// The result from the produce-review loop that executed this step.
  final AgentLoopResult agentLoopResult;

  @override
  String get output => agentLoopResult.lastProducerResult.output;

  @override
  int get tokensUsed => agentLoopResult.totalTokensUsed;

  /// Whether the reviewer accepted the producer's output.
  bool get accepted => agentLoopResult.accepted;

  /// The number of produce-review iterations executed.
  int get iterationCount => agentLoopResult.iterationCount;

  @override
  String toString() => 'AgentLoopStepResult($agentLoopResult)';
}
