import '../client/llm_client.dart';
import '../config/agents_core_config.dart';
import '../context/file_context.dart';
import '../models/tool_definition.dart';
import 'agent_result.dart';

/// Abstract base class for all agents in the orchestration framework.
///
/// An [Agent] encapsulates a persona (via [name] and [systemPrompt]), a set
/// of [tools] it may invoke, and a connection to an LM Studio backend via
/// [client]. Subclasses implement the [run] method to define how the agent
/// processes a task — from a single chat-completion round ([SimpleAgent]) to
/// multi-turn tool-calling loops.
///
/// ```dart
/// class MyAgent extends Agent {
///   MyAgent({required super.name, required super.client, required super.config});
///
///   @override
///   Future<AgentResult> run(String task, {FileContext? context}) async {
///     // custom execution logic
///   }
/// }
/// ```
abstract class Agent {
  /// Creates an [Agent].
  ///
  /// [name] identifies the agent in logs and orchestration metadata.
  ///
  /// [client] is the LM Studio client used for chat completions. The caller
  /// is responsible for disposing the client after the agent is no longer
  /// needed.
  ///
  /// [config] provides cross-cutting settings (logger, timeout, etc.).
  ///
  /// [systemPrompt] sets the system-level instruction prepended to every
  /// request. When `null`, no system message is included.
  ///
  /// [tools] defines the functions the model is allowed to invoke. Defaults
  /// to an empty list (no tool use).
  ///
  /// [model] overrides the model identifier sent in requests. When `null`,
  /// the subclass decides which model to use (or falls back to a default).
  Agent({
    required this.name,
    required this.client,
    required this.config,
    this.systemPrompt,
    this.tools = const [],
    this.model,
  });

  /// A human-readable name identifying this agent.
  ///
  /// Used in log messages and orchestration metadata (e.g. task assignments).
  final String name;

  /// The LLM client used for chat completion requests.
  ///
  /// The agent does **not** own this client — the caller is responsible for
  /// calling [LlmClient.dispose] when done.
  final LlmClient client;

  /// Cross-cutting configuration (logger, timeouts, base URL).
  final AgentsCoreConfig config;

  /// The system prompt prepended to every chat completion request.
  ///
  /// Defines the agent's persona, constraints, and behavioural guidelines.
  /// When `null`, no system message is included in the request.
  final String? systemPrompt;

  /// Tool definitions the model may invoke during execution.
  ///
  /// Empty by default. Subclasses that support tool calling should populate
  /// this with the relevant [ToolDefinition] objects.
  final List<ToolDefinition> tools;

  /// The model identifier sent in chat completion requests.
  ///
  /// When `null`, the subclass is free to choose a default or derive the
  /// model from configuration.
  final String? model;

  /// Executes the agent's task and returns an [AgentResult].
  ///
  /// [task] is the user-facing prompt or instruction the agent should
  /// process.
  ///
  /// [context] provides an optional sandboxed file-system workspace. When
  /// supplied, the agent may read and write files within the workspace.
  /// The [AgentResult.filesModified] field should reflect any mutations.
  ///
  /// Throws [LmStudioConnectionException] if the server cannot be reached.
  /// Throws [LmStudioHttpException] if the response status is not 2xx.
  Future<AgentResult> run(String task, {FileContext? context});
}
