import '../context/file_context.dart';
import '../models/chat_completion_request.dart';
import '../models/chat_message.dart';
import 'agent.dart';
import 'agent_result.dart';

/// A single-round agent that sends one chat completion request and returns
/// the result.
///
/// [SimpleAgent] is the most basic concrete [Agent] implementation. It
/// builds a message list from its [systemPrompt] and the provided task,
/// sends a single (non-streaming) chat completion via [client], and wraps
/// the response in an [AgentResult].
///
/// No tool-calling loop is performed — if the model returns tool calls
/// they are recorded in [AgentResult.toolCallsMade] but not executed.
/// For agents that need to execute tools iteratively, use a higher-level
/// agent subclass.
///
/// ```dart
/// final agent = SimpleAgent(
///   name: 'summariser',
///   client: LmStudioClient(config),
///   config: config,
///   model: 'llama-3-8b',
///   systemPrompt: 'You are a concise summariser.',
/// );
///
/// final result = await agent.run('Summarise this document.');
/// print(result.output);
/// agent.client.dispose();
/// ```
class SimpleAgent extends Agent {
  /// Creates a [SimpleAgent].
  ///
  /// All parameters are forwarded to the [Agent] base class. See [Agent]
  /// for detailed documentation on each parameter.
  SimpleAgent({
    required super.name,
    required super.client,
    required super.config,
    super.systemPrompt,
    super.tools,
    super.model,
  });

  /// The default model identifier used when [model] is `null`.
  static const defaultModel = 'lmstudio-community/default';

  /// Executes a single chat completion round and returns the result.
  ///
  /// Builds a [ChatCompletionRequest] with:
  /// - [systemPrompt] as the system message (if non-null)
  /// - [task] as the user message
  /// - [tools] as available tool definitions (if non-empty)
  /// - [model] (or [defaultModel] when null)
  ///
  /// The [context] parameter is accepted for interface compliance but is
  /// not used in this simple implementation — no file operations are
  /// performed.
  ///
  /// Returns an [AgentResult] populated from the first choice of the
  /// chat completion response.
  ///
  /// Throws [LmStudioConnectionException] if the server cannot be reached.
  /// Throws [LmStudioHttpException] if the response status is not 2xx.
  @override
  Future<AgentResult> run(String task, {FileContext? context}) async {
    config.logger.info(
      '[$name] Running task: '
      '${task.length > 60 ? '${task.substring(0, 60)}...' : task}',
    );

    final messages = _buildMessages(task);

    final request = ChatCompletionRequest(
      model: model ?? defaultModel,
      messages: messages,
      tools: tools.isNotEmpty ? tools : null,
    );

    config.logger.debug(
      '[$name] Sending chat completion: '
      'model=${request.model}, '
      'messages=${messages.length}, '
      'tools=${tools.length}',
    );

    final response = await client.chatCompletion(request);
    final choice = response.choices.first;
    final message = choice.message;

    config.logger.debug(
      '[$name] Received response: '
      'tokens=${response.usage.totalTokens}, '
      'finishReason=${choice.finishReason}',
    );

    return AgentResult(
      output: message.content ?? '',
      toolCallsMade: message.toolCalls ?? const [],
      tokensUsed: response.usage.totalTokens,
      // SimpleAgent does not track stop reason; ReActAgent handles that.
      // choice.finishReason is a raw OpenAI String — not assignable to AgentStopReason.
      stoppedReason: null,
    );
  }

  /// Builds the message list from [systemPrompt] and [task].
  List<ChatMessage> _buildMessages(String task) {
    return [
      if (systemPrompt != null)
        ChatMessage(role: ChatMessageRole.system, content: systemPrompt),
      ChatMessage(role: ChatMessageRole.user, content: task),
    ];
  }
}
