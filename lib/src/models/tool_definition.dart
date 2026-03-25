/// Defines a tool (function) that the model can invoke.
///
/// Follows the OpenAI function-calling format where each tool is wrapped
/// in a `{"type": "function", "function": {...}}` envelope.
///
/// ```dart
/// final tool = ToolDefinition(
///   name: 'get_weather',
///   description: 'Get the current weather for a city',
///   parameters: {
///     'type': 'object',
///     'properties': {
///       'city': {'type': 'string'},
///     },
///     'required': ['city'],
///   },
/// );
/// ```
class ToolDefinition {
  /// Creates a [ToolDefinition].
  ///
  /// [name] is the function name the model will reference.
  /// [description] tells the model what the tool does.
  /// [parameters] is a JSON Schema object describing the expected arguments.
  const ToolDefinition({
    required this.name,
    required this.description,
    required this.parameters,
  });

  /// Deserializes a [ToolDefinition] from the OpenAI function tool format.
  ///
  /// Expects the envelope shape:
  /// ```json
  /// {"type": "function", "function": {"name": "...", "description": "...", "parameters": {...}}}
  /// ```
  factory ToolDefinition.fromJson(Map<String, dynamic> json) {
    final fn = json['function'] as Map<String, dynamic>;
    return ToolDefinition(
      name: fn['name'] as String,
      description: fn['description'] as String,
      parameters: fn['parameters'] as Map<String, dynamic>,
    );
  }

  /// The function name.
  final String name;

  /// A human-readable description of what the tool does.
  final String description;

  /// A JSON Schema object describing the function parameters.
  final Map<String, dynamic> parameters;

  /// Serializes this tool to the OpenAI function tool format.
  ///
  /// Returns a map with `type` set to `"function"` and a nested `function`
  /// object containing `name`, `description`, and `parameters`.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'type': 'function',
        'function': <String, dynamic>{
          'name': name,
          'description': description,
          'parameters': parameters,
        },
      };
}
