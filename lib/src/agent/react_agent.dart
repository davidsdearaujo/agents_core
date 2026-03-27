import 'dart:convert';

import '../context/file_context.dart';
import '../loop_detection/loop_detection_config.dart';
import '../loop_detection/loop_detector.dart';
import '../models/chat_completion_request.dart';
import '../models/chat_message.dart';
import '../models/tool_call.dart';
import 'agent.dart';
import 'agent_result.dart';

/// A tool-handler function that receives parsed JSON arguments and returns
/// a string result to feed back to the model.
///
/// Handlers are registered by tool name in [ReActAgent.toolHandlers].
///
/// ```dart
/// Future<String> getWeather(Map<String, dynamic> args) async {
///   final city = args['city'] as String;
///   return 'Sunny, 22°C in $city';
/// }
/// ```
typedef ToolHandler = Future<String> Function(Map<String, dynamic> arguments);

/// An agent that implements the Reason + Act (ReAct) loop with tool calling.
///
/// [ReActAgent] extends [Agent] to execute a multi-turn conversation loop:
///
/// 1. Send the message history to the LLM.
/// 2. If the response contains tool calls, execute each tool via the
///    registered [toolHandlers] and append the results as `role:tool`
///    messages.
/// 3. Repeat from step 1.
///
/// The loop terminates when:
/// - The model produces a response with **no tool calls** (natural
///   completion, `stoppedReason: "completed"`).
/// - [maxIterations] is reached (`stoppedReason: "max_iterations"`).
/// - Cumulative token usage exceeds [maxTotalTokens]
///   (`stoppedReason: "max_total_tokens"`).
/// - A repetitive loop is detected via [loopDetectionConfig]
///   (`stoppedReason: "loop_detected"`).
///
/// Unregistered tools do **not** throw — instead an error string is returned
/// to the LLM so it can self-correct.
///
/// ```dart
/// final agent = ReActAgent(
///   name: 'researcher',
///   client: client,
///   config: config,
///   model: 'llama-3-8b',
///   systemPrompt: 'You are a research assistant.',
///   tools: [weatherTool],
///   toolHandlers: {
///     'get_weather': (args) async => 'Sunny, 22°C',
///   },
/// );
///
/// final result = await agent.run('What is the weather in NYC?');
/// print(result.output);
/// print(result.stoppedReason); // "completed"
/// ```
class ReActAgent extends Agent {
  /// Creates a [ReActAgent].
  ///
  /// [toolHandlers] maps tool names to their handler functions. Every
  /// [ToolDefinition] in [tools] should have a corresponding entry;
  /// unregistered tools produce an error message fed back to the model.
  ///
  /// [maxIterations] caps the number of LLM round-trips. Defaults to 10.
  ///
  /// [maxTotalTokens] caps cumulative token usage across all iterations.
  /// When `null`, no token budget is enforced.
  ///
  /// [loopDetectionConfig] enables automatic detection of repetitive
  /// tool-call and output patterns. When `null` (the default), no loop
  /// detection is performed.
  ReActAgent({
    required super.name,
    required super.client,
    required super.config,
    required this.toolHandlers,
    super.systemPrompt,
    super.tools,
    super.model,
    this.maxIterations = 10,
    this.maxTotalTokens,
    this.loopDetectionConfig,
  });

  /// Maps tool names to their handler functions.
  ///
  /// When the model requests a tool call, the agent looks up the function
  /// name here and invokes the corresponding handler. If no handler is
  /// found, an error message is returned to the LLM.
  final Map<String, ToolHandler> toolHandlers;

  /// Maximum number of LLM round-trips before the loop is stopped.
  ///
  /// Defaults to 10. Each iteration consists of one chat completion request
  /// followed by tool execution (if tool calls are present).
  final int maxIterations;

  /// Maximum cumulative token usage before the loop is stopped.
  ///
  /// When `null`, no token budget is enforced. When set, the agent checks
  /// the running total after each iteration and stops if the budget is
  /// exceeded.
  final int? maxTotalTokens;

  /// Optional configuration for automatic loop detection.
  ///
  /// When non-null, a [LoopDetector] is created at the start of each
  /// [run] invocation and checks for repetitive tool-call sequences or
  /// near-identical outputs after each iteration. If a loop is detected,
  /// the agent stops with `stoppedReason: "loop_detected"`.
  ///
  /// When `null` (the default), no loop detection is performed.
  final LoopDetectionConfig? loopDetectionConfig;

  /// The default model identifier used when [model] is `null`.
  static const defaultModel = 'lmstudio-community/default';

  /// Executes the ReAct loop for the given [task].
  ///
  /// Builds an initial message list from [systemPrompt] and [task], then
  /// enters the reason-act loop. Each iteration sends the accumulated
  /// messages to the LLM, executes any requested tool calls, and appends
  /// the results.
  ///
  /// Returns an [AgentResult] with the final output, all tool calls made
  /// across iterations, cumulative token count, and the reason the loop
  /// ended.
  @override
  Future<AgentResult> run(String task, {FileContext? context}) async {
    config.logger.info('[$name] Starting ReAct loop: '
        '${task.length > 60 ? '${task.substring(0, 60)}...' : task}');

    final messages = <ChatMessage>[
      if (systemPrompt != null)
        ChatMessage(role: ChatMessageRole.system, content: systemPrompt),
      ChatMessage(role: ChatMessageRole.user, content: task),
    ];

    final allToolCalls = <ToolCall>[];
    var totalTokens = 0;
    var iterations = 0;
    ChatMessage? lastAssistantMessage;
    String? stoppedReason;

    final detector = loopDetectionConfig != null
        ? LoopDetector(config: loopDetectionConfig!)
        : null;

    while (iterations < maxIterations) {
      iterations++;
      config.logger.debug(
        '[$name] Iteration $iterations/$maxIterations '
        '(tokens: $totalTokens)',
      );

      // ── Step 1: Send messages to LLM ──────────────────────────────────
      final request = ChatCompletionRequest(
        model: model ?? defaultModel,
        messages: messages,
        tools: tools.isNotEmpty ? tools : null,
      );

      final response = await client.chatCompletion(request);
      final choice = response.choices.first;
      final assistantMessage = choice.message;

      totalTokens += response.usage.totalTokens;
      lastAssistantMessage = assistantMessage;

      // Append the assistant message to the conversation history.
      messages.add(assistantMessage);

      config.logger.debug(
        '[$name] Response: finishReason=${choice.finishReason}, '
        'toolCalls=${assistantMessage.toolCalls?.length ?? 0}, '
        'tokens=${response.usage.totalTokens}',
      );

      // ── Step 2: Check for natural completion ──────────────────────────
      final toolCalls = assistantMessage.toolCalls;
      if (toolCalls == null || toolCalls.isEmpty) {
        stoppedReason = 'completed';
        config.logger.info(
          '[$name] Completed after $iterations iteration(s) '
          '($totalTokens tokens)',
        );
        break;
      }

      // ── Step 3: Execute tool calls ────────────────────────────────────
      allToolCalls.addAll(toolCalls);

      for (final toolCall in toolCalls) {
        final functionName = toolCall.function?.name ?? '';
        final toolCallId = toolCall.id ?? '';
        final rawArguments = toolCall.function?.arguments ?? '{}';

        config.logger.debug(
          '[$name] Executing tool: $functionName '
          '(id=$toolCallId)',
        );

        final result = await _executeTool(functionName, rawArguments);

        // Append tool result as a role:tool message.
        messages.add(ChatMessage(
          role: ChatMessageRole.tool,
          content: result,
          toolCallId: toolCallId,
        ));
      }

      // ── Step 3.5: Check for repetitive loop ────────────────────────────
      if (detector != null) {
        detector.recordToolCalls(toolCalls);
        detector.recordOutput(assistantMessage.content);
        final loopCheck = detector.check();
        if (loopCheck.isLooping) {
          stoppedReason = 'loop_detected';
          config.logger.warn(
            '[$name] Loop detected: ${loopCheck.reason}',
          );
          break;
        }
      }

      // ── Step 4: Check token budget ────────────────────────────────────
      if (maxTotalTokens != null && totalTokens >= maxTotalTokens!) {
        stoppedReason = 'max_total_tokens';
        config.logger.warn(
          '[$name] Token budget exceeded: '
          '$totalTokens >= $maxTotalTokens',
        );
        break;
      }
    }

    // If we exited the while loop without breaking, maxIterations was hit.
    if (stoppedReason == null) {
      stoppedReason = 'max_iterations';
      config.logger.warn(
        '[$name] Max iterations reached: $maxIterations',
      );
    }

    return AgentResult(
      output: lastAssistantMessage?.content ?? '',
      toolCallsMade: allToolCalls,
      tokensUsed: totalTokens,
      stoppedReason: stoppedReason,
    );
  }

  /// Executes a single tool call by looking up the handler in
  /// [toolHandlers].
  ///
  /// Returns the handler's string result on success, or an error message
  /// if the tool is not registered or the arguments cannot be parsed.
  /// Exceptions from handlers are caught and returned as error strings
  /// so the LLM can self-correct.
  Future<String> _executeTool(String functionName, String rawArguments) async {
    final handler = toolHandlers[functionName];
    if (handler == null) {
      config.logger.warn(
        '[$name] Unregistered tool called: $functionName',
      );
      return 'Error: tool "$functionName" is not registered. '
          'Available tools: ${toolHandlers.keys.join(", ")}';
    }

    try {
      final arguments = rawArguments.isEmpty
          ? <String, dynamic>{}
          : json.decode(rawArguments) as Map<String, dynamic>;
      return await handler(arguments);
    } on FormatException catch (e) {
      config.logger.error(
        '[$name] Failed to parse arguments for $functionName: $e',
      );
      return 'Error: failed to parse arguments for "$functionName": $e';
    } on Exception catch (e) {
      config.logger.error(
        '[$name] Tool "$functionName" threw: $e',
      );
      return 'Error: tool "$functionName" failed: $e';
    }
  }
}
