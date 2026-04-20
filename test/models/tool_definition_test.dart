import 'package:agents_core/agents_core.dart';
import 'package:test/test.dart';

void main() {
  // Minimal JSON Schema for test parameters
  const simpleParams = <String, dynamic>{
    'type': 'object',
    'properties': {
      'location': {'type': 'string', 'description': 'The city and state'},
    },
    'required': ['location'],
  };

  group('ToolDefinition — construction', () {
    test('creates with name, description, and parameters', () {
      final tool = ToolDefinition(
        name: 'get_weather',
        description: 'Get the current weather',
        parameters: simpleParams,
      );
      expect(tool.name, equals('get_weather'));
      expect(tool.description, equals('Get the current weather'));
      expect(tool.parameters, equals(simpleParams));
    });

    test('accepts empty description', () {
      final tool = ToolDefinition(
        name: 'no_op',
        description: '',
        parameters: <String, dynamic>{
          'type': 'object',
          'properties': <String, dynamic>{},
        },
      );
      expect(tool.description, equals(''));
    });

    test('accepts empty parameters schema', () {
      final tool = ToolDefinition(
        name: 'no_params',
        description: 'A tool with no parameters',
        parameters: <String, dynamic>{
          'type': 'object',
          'properties': <String, dynamic>{},
        },
      );
      expect(tool.parameters, isA<Map<String, dynamic>>());
    });
  });

  group('ToolDefinition — toJson()', () {
    test('serializes as OpenAI function tool format', () {
      final tool = ToolDefinition(
        name: 'get_weather',
        description: 'Get the current weather',
        parameters: simpleParams,
      );
      final json = tool.toJson();
      // OpenAI format: {"type": "function", "function": {"name": ..., "description": ..., "parameters": ...}}
      expect(json['type'], equals('function'));
      expect(json['function'], isA<Map<String, dynamic>>());
      final fn = json['function'] as Map<String, dynamic>;
      expect(fn['name'], equals('get_weather'));
      expect(fn['description'], equals('Get the current weather'));
      expect(fn['parameters'], equals(simpleParams));
    });

    test('toJson returns Map<String, dynamic>', () {
      final tool = ToolDefinition(
        name: 'test',
        description: 'A test tool',
        parameters: <String, dynamic>{},
      );
      expect(tool.toJson(), isA<Map<String, dynamic>>());
    });

    test('nested parameters are preserved in JSON', () {
      final complexParams = <String, dynamic>{
        'type': 'object',
        'properties': {
          'a': {'type': 'string'},
          'b': {'type': 'integer'},
          'c': {
            'type': 'object',
            'properties': {
              'nested': {'type': 'boolean'},
            },
          },
        },
        'required': ['a'],
      };
      final tool = ToolDefinition(
        name: 'complex',
        description: 'Complex tool',
        parameters: complexParams,
      );
      final json = tool.toJson();
      final fn = json['function'] as Map<String, dynamic>;
      expect(fn['parameters'], equals(complexParams));
    });
  });

  group('ToolDefinition — fromJson()', () {
    test('parses from OpenAI function tool format', () {
      final json = <String, dynamic>{
        'type': 'function',
        'function': {
          'name': 'get_weather',
          'description': 'Get the current weather',
          'parameters': simpleParams,
        },
      };
      final tool = ToolDefinition.fromJson(json);
      expect(tool.name, equals('get_weather'));
      expect(tool.description, equals('Get the current weather'));
      expect(tool.parameters, equals(simpleParams));
    });

    test('parses tool with empty parameters', () {
      final json = <String, dynamic>{
        'type': 'function',
        'function': {
          'name': 'empty_tool',
          'description': 'No params',
          'parameters': <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{},
          },
        },
      };
      final tool = ToolDefinition.fromJson(json);
      expect(tool.name, equals('empty_tool'));
    });
  });

  group('ToolDefinition — round-trip', () {
    test('round-trips through toJson/fromJson', () {
      final original = ToolDefinition(
        name: 'search',
        description: 'Search the web',
        parameters: simpleParams,
      );
      final restored = ToolDefinition.fromJson(original.toJson());
      expect(restored.name, equals(original.name));
      expect(restored.description, equals(original.description));
      expect(restored.parameters, equals(original.parameters));
    });
  });
}
