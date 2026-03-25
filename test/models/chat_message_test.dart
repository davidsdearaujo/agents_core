import 'package:agents_core/agents_core.dart';
import 'package:test/test.dart';

void main() {
  group('ChatMessageRole', () {
    test('has system value', () {
      expect(ChatMessageRole.system, isA<ChatMessageRole>());
    });

    test('has user value', () {
      expect(ChatMessageRole.user, isA<ChatMessageRole>());
    });

    test('has assistant value', () {
      expect(ChatMessageRole.assistant, isA<ChatMessageRole>());
    });

    test('has tool value', () {
      expect(ChatMessageRole.tool, isA<ChatMessageRole>());
    });

    test('serializes system to "system"', () {
      expect(ChatMessageRole.system.value, equals('system'));
    });

    test('serializes user to "user"', () {
      expect(ChatMessageRole.user.value, equals('user'));
    });

    test('serializes assistant to "assistant"', () {
      expect(ChatMessageRole.assistant.value, equals('assistant'));
    });

    test('serializes tool to "tool"', () {
      expect(ChatMessageRole.tool.value, equals('tool'));
    });

    test('fromString parses system', () {
      expect(ChatMessageRole.fromString('system'), equals(ChatMessageRole.system));
    });

    test('fromString parses user', () {
      expect(ChatMessageRole.fromString('user'), equals(ChatMessageRole.user));
    });

    test('fromString parses assistant', () {
      expect(ChatMessageRole.fromString('assistant'), equals(ChatMessageRole.assistant));
    });

    test('fromString parses tool', () {
      expect(ChatMessageRole.fromString('tool'), equals(ChatMessageRole.tool));
    });

    test('fromString throws on unknown role', () {
      expect(() => ChatMessageRole.fromString('unknown'), throwsArgumentError);
    });
  });

  group('ChatMessage — construction', () {
    test('creates user message', () {
      final msg = ChatMessage(role: ChatMessageRole.user, content: 'Hello');
      expect(msg.role, equals(ChatMessageRole.user));
      expect(msg.content, equals('Hello'));
      expect(msg.toolCallId, isNull);
    });

    test('creates system message', () {
      final msg = ChatMessage(role: ChatMessageRole.system, content: 'You are helpful.');
      expect(msg.role, equals(ChatMessageRole.system));
      expect(msg.content, equals('You are helpful.'));
    });

    test('creates assistant message', () {
      final msg = ChatMessage(role: ChatMessageRole.assistant, content: 'I can help.');
      expect(msg.role, equals(ChatMessageRole.assistant));
      expect(msg.content, equals('I can help.'));
    });

    test('creates tool message with toolCallId', () {
      final msg = ChatMessage(
        role: ChatMessageRole.tool,
        content: '{"temperature": 72}',
        toolCallId: 'call_abc123',
      );
      expect(msg.role, equals(ChatMessageRole.tool));
      expect(msg.content, equals('{"temperature": 72}'));
      expect(msg.toolCallId, equals('call_abc123'));
    });

    test('toolCallId defaults to null', () {
      final msg = ChatMessage(role: ChatMessageRole.user, content: 'test');
      expect(msg.toolCallId, isNull);
    });

    test('supports empty content', () {
      final msg = ChatMessage(role: ChatMessageRole.user, content: '');
      expect(msg.content, equals(''));
    });
  });

  group('ChatMessage — toJson()', () {
    test('user message serializes correctly', () {
      final msg = ChatMessage(role: ChatMessageRole.user, content: 'Hello');
      final json = msg.toJson();
      expect(json['role'], equals('user'));
      expect(json['content'], equals('Hello'));
    });

    test('system message serializes correctly', () {
      final msg = ChatMessage(role: ChatMessageRole.system, content: 'Be helpful');
      final json = msg.toJson();
      expect(json['role'], equals('system'));
      expect(json['content'], equals('Be helpful'));
    });

    test('assistant message serializes correctly', () {
      final msg = ChatMessage(role: ChatMessageRole.assistant, content: 'Sure!');
      final json = msg.toJson();
      expect(json['role'], equals('assistant'));
      expect(json['content'], equals('Sure!'));
    });

    test('tool message serializes role and toolCallId', () {
      final msg = ChatMessage(
        role: ChatMessageRole.tool,
        content: 'result',
        toolCallId: 'call_xyz',
      );
      final json = msg.toJson();
      expect(json['role'], equals('tool'));
      expect(json['content'], equals('result'));
      expect(json['tool_call_id'], equals('call_xyz'));
    });

    test('toolCallId is omitted from JSON when null', () {
      final msg = ChatMessage(role: ChatMessageRole.user, content: 'Hi');
      final json = msg.toJson();
      expect(json.containsKey('tool_call_id'), isFalse);
    });

    test('toJson returns Map<String, dynamic>', () {
      final msg = ChatMessage(role: ChatMessageRole.user, content: 'test');
      expect(msg.toJson(), isA<Map<String, dynamic>>());
    });
  });

  group('ChatMessage — fromJson()', () {
    test('parses user message', () {
      final json = {'role': 'user', 'content': 'Hello'};
      final msg = ChatMessage.fromJson(json);
      expect(msg.role, equals(ChatMessageRole.user));
      expect(msg.content, equals('Hello'));
      expect(msg.toolCallId, isNull);
    });

    test('parses system message', () {
      final json = {'role': 'system', 'content': 'You are an assistant.'};
      final msg = ChatMessage.fromJson(json);
      expect(msg.role, equals(ChatMessageRole.system));
      expect(msg.content, equals('You are an assistant.'));
    });

    test('parses assistant message', () {
      final json = {'role': 'assistant', 'content': 'How can I help?'};
      final msg = ChatMessage.fromJson(json);
      expect(msg.role, equals(ChatMessageRole.assistant));
      expect(msg.content, equals('How can I help?'));
    });

    test('parses tool message with tool_call_id', () {
      final json = {
        'role': 'tool',
        'content': '{"result": "ok"}',
        'tool_call_id': 'call_abc',
      };
      final msg = ChatMessage.fromJson(json);
      expect(msg.role, equals(ChatMessageRole.tool));
      expect(msg.content, equals('{"result": "ok"}'));
      expect(msg.toolCallId, equals('call_abc'));
    });

    test('toolCallId is null when not in JSON', () {
      final json = {'role': 'user', 'content': 'Hi'};
      final msg = ChatMessage.fromJson(json);
      expect(msg.toolCallId, isNull);
    });

    test('throws on unknown role', () {
      final json = {'role': 'unknown_role', 'content': 'Hello'};
      expect(() => ChatMessage.fromJson(json), throwsA(anything));
    });
  });

  group('ChatMessage — round-trip', () {
    test('user message round-trips through toJson/fromJson', () {
      final original = ChatMessage(role: ChatMessageRole.user, content: 'Hello!');
      final restored = ChatMessage.fromJson(original.toJson());
      expect(restored.role, equals(original.role));
      expect(restored.content, equals(original.content));
      expect(restored.toolCallId, equals(original.toolCallId));
    });

    test('tool message round-trips with toolCallId', () {
      final original = ChatMessage(
        role: ChatMessageRole.tool,
        content: '{"data": 42}',
        toolCallId: 'call_round_trip',
      );
      final restored = ChatMessage.fromJson(original.toJson());
      expect(restored.role, equals(original.role));
      expect(restored.content, equals(original.content));
      expect(restored.toolCallId, equals(original.toolCallId));
    });

    test('all roles round-trip correctly', () {
      for (final role in [
        ChatMessageRole.system,
        ChatMessageRole.user,
        ChatMessageRole.assistant,
        ChatMessageRole.tool,
      ]) {
        final msg = ChatMessage(
          role: role,
          content: 'content for $role',
          toolCallId: role == ChatMessageRole.tool ? 'call_id' : null,
        );
        final restored = ChatMessage.fromJson(msg.toJson());
        expect(restored.role, equals(role));
      }
    });
  });
}
