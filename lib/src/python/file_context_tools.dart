import '../agent/react_agent.dart';
import '../context/file_context.dart';
import '../models/tool_definition.dart';

/// Tool definition for reading a file from the workspace.
final ToolDefinition readFileToolDefinition = ToolDefinition(
  name: 'read_file',
  description: 'Reads the contents of a file from the /workspace directory. '
      'Returns the file content as a string.',
  parameters: <String, dynamic>{
    'type': 'object',
    'properties': <String, dynamic>{
      'path': <String, dynamic>{
        'type': 'string',
        'description':
            'The relative path to the file within the workspace '
                '(e.g. "data.csv", "output/results.json").',
      },
    },
    'required': <String>['path'],
  },
);

/// Tool definition for writing a file to the workspace.
final ToolDefinition writeFileToolDefinition = ToolDefinition(
  name: 'write_file',
  description: 'Writes content to a file in the /workspace directory. '
      'Creates the file if it does not exist; overwrites if it does. '
      'Parent directories are created automatically.',
  parameters: <String, dynamic>{
    'type': 'object',
    'properties': <String, dynamic>{
      'path': <String, dynamic>{
        'type': 'string',
        'description':
            'The relative path to the file within the workspace '
                '(e.g. "data.csv", "output/results.json").',
      },
      'content': <String, dynamic>{
        'type': 'string',
        'description': 'The content to write to the file.',
      },
    },
    'required': <String>['path', 'content'],
  },
);

/// Tool definition for listing files in the workspace.
final ToolDefinition listFilesToolDefinition = ToolDefinition(
  name: 'list_files',
  description: 'Lists files in the /workspace directory. '
      'Returns a newline-separated list of relative file paths. '
      'Optionally filters by a glob pattern.',
  parameters: <String, dynamic>{
    'type': 'object',
    'properties': <String, dynamic>{
      'glob': <String, dynamic>{
        'type': 'string',
        'description':
            'Optional glob pattern to filter files '
                '(e.g. "*.csv", "**/*.json"). Omit to list all files.',
      },
    },
  },
);

/// Returns all file-context [ToolDefinition]s.
List<ToolDefinition> get fileContextToolDefinitions => [
      readFileToolDefinition,
      writeFileToolDefinition,
      listFilesToolDefinition,
    ];

/// Creates a map of file-context [ToolHandler]s backed by [context].
///
/// Returns handlers for `read_file`, `write_file`, and `list_files`.
/// Errors (e.g. file not found, path traversal) are returned as error
/// strings so the LLM can self-correct.
Map<String, ToolHandler> createFileContextHandlers({
  required FileContext context,
}) {
  return {
    'read_file': (Map<String, dynamic> args) async {
      final path = args['path'] as String? ?? '';
      if (path.isEmpty) {
        return 'Error: "path" parameter is required and must not be empty.';
      }
      try {
        return context.read(path);
      } on Exception catch (e) {
        return 'Error reading file "$path": $e';
      }
    },
    'write_file': (Map<String, dynamic> args) async {
      final path = args['path'] as String? ?? '';
      final content = args['content'] as String? ?? '';
      if (path.isEmpty) {
        return 'Error: "path" parameter is required and must not be empty.';
      }
      try {
        context.write(path, content);
        return 'File "$path" written successfully '
            '(${content.length} characters).';
      } on Exception catch (e) {
        return 'Error writing file "$path": $e';
      }
    },
    'list_files': (Map<String, dynamic> args) async {
      final glob = args['glob'] as String?;
      try {
        final files = context.listFiles(glob: glob);
        if (files.isEmpty) {
          return glob != null
              ? 'No files matching "$glob" found in workspace.'
              : 'Workspace is empty.';
        }
        return files.join('\n');
      } on Exception catch (e) {
        return 'Error listing files: $e';
      }
    },
  };
}
