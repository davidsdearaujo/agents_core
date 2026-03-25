// Multi-turn conversation example.
//
// Demonstrates how to maintain a conversation history across multiple
// exchanges with the LLM using LmStudioClient and ChatMessage.
// Each request sends the full message history so the model can reference
// prior turns.
//
// ## Prerequisites
//
// - LM Studio running on localhost:1234 (the default)
// - A model loaded in LM Studio (e.g. llama-3-8b)
//
// ## Run
//
//   dart run example/conversation.dart
import 'dart:io';

import 'package:agents_core/agents_core.dart';

Future<void> main() async {
  final config = AgentsCoreConfig(
    logger: const SilentLogger(),
  );

  final client = LmStudioClient(config);
  const model = 'llama-3-8b';

  // Maintain conversation history as a growable list.
  final history = <ChatMessage>[
    ChatMessage(
      role: ChatMessageRole.system,
      content: 'You are a helpful history tutor. '
          'Keep answers concise (1-2 sentences). '
          'Reference prior questions when relevant.',
    ),
  ];

  try {
    // ── Turn 1 ─────────────────────────────────────────────────────────
    print('--- Turn 1 ---');
    final reply1 = await _sendMessage(
      client: client,
      model: model,
      history: history,
      userMessage: 'Who built the Great Wall of China?',
    );
    print('User:  Who built the Great Wall of China?');
    print('AI:    $reply1\n');

    // ── Turn 2 (references prior context) ──────────────────────────────
    print('--- Turn 2 ---');
    final reply2 = await _sendMessage(
      client: client,
      model: model,
      history: history,
      userMessage: 'How long is it?',
    );
    print('User:  How long is it?');
    print('AI:    $reply2\n');

    // ── Turn 3 ─────────────────────────────────────────────────────────
    print('--- Turn 3 ---');
    final reply3 = await _sendMessage(
      client: client,
      model: model,
      history: history,
      userMessage: 'Can you see it from space?',
    );
    print('User:  Can you see it from space?');
    print('AI:    $reply3\n');

    // ── Show full history ──────────────────────────────────────────────
    print('=== Conversation history (${history.length} messages) ===');
    for (final msg in history) {
      final role = msg.role.value.toUpperCase().padRight(10);
      final content = msg.content ?? '(no content)';
      final preview =
          content.length > 70 ? '${content.substring(0, 70)}...' : content;
      print('  $role $preview');
    }
  } on LmStudioConnectionException catch (e) {
    stderr.writeln('Connection error: ${e.message}');
    stderr.writeln('Make sure LM Studio is running on localhost:1234.');
    exit(1);
  } finally {
    client.dispose();
  }
}

/// Sends a user message, appends both user and assistant messages to
/// [history], and returns the assistant's reply text.
Future<String> _sendMessage({
  required LmStudioClient client,
  required String model,
  required List<ChatMessage> history,
  required String userMessage,
}) async {
  // Append the user message to the conversation history.
  history.add(ChatMessage(role: ChatMessageRole.user, content: userMessage));

  // Send the full history to the model.
  final request = ChatCompletionRequest(
    model: model,
    messages: history,
  );

  final response = await client.chatCompletion(request);
  final assistantMessage = response.choices.first.message;

  // Append the assistant's reply to the conversation history.
  history.add(assistantMessage);

  return assistantMessage.content ?? '';
}
