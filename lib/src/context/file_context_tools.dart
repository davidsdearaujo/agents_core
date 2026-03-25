import '../exceptions/file_context_exceptions.dart';
import '../models/tool_definition.dart';
import 'file_context.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Tool definitions
// ─────────────────────────────────────────────────────────────────────────────

/// Tool definition for reading a file from the workspace.
///
/// Requires a `fileName` argument specifying the relative path within the
/// workspace.
const ToolDefinition readFileTool = ToolDefinition(
  name: 'read_file',
  description: 'Reads the contents of a file from the workspace directory. '
      'Returns the file content as a string.',
  parameters: <String, dynamic>{
    'type': 'object',
    'properties': <String, dynamic>{
      'fileName': <String, dynamic>{
        'type': 'string',
        'description': 'The relative path to the file within the workspace '
            '(e.g. "data.csv", "output/results.json").',
      },
    },
    'required': <dynamic>['fileName'],
  },
);

/// Tool definition for writing content to a file in the workspace.
///
/// Requires `fileName` and `content` arguments. Creates the file if it does
/// not exist; overwrites if it does. Parent directories are created
/// automatically.
const ToolDefinition writeFileTool = ToolDefinition(
  name: 'write_file',
  description: 'Writes content to a file in the workspace directory. '
      'Creates the file if it does not exist; overwrites if it does. '
      'Parent directories are created automatically.',
  parameters: <String, dynamic>{
    'type': 'object',
    'properties': <String, dynamic>{
      'fileName': <String, dynamic>{
        'type': 'string',
        'description': 'The relative path to the file within the workspace '
            '(e.g. "data.csv", "output/results.json").',
      },
      'content': <String, dynamic>{
        'type': 'string',
        'description': 'The content to write to the file.',
      },
    },
    'required': <dynamic>['fileName', 'content'],
  },
);

/// Tool definition for listing files in the workspace.
///
/// Accepts an optional `glob` parameter to filter results. When omitted,
/// all files are returned.
const ToolDefinition listFilesTool = ToolDefinition(
  name: 'list_files',
  description: 'Lists files in the workspace directory. '
      'Returns a newline-separated list of relative file paths. '
      'Optionally filters by a glob pattern.',
  parameters: <String, dynamic>{
    'type': 'object',
    'properties': <String, dynamic>{
      'glob': <String, dynamic>{
        'type': 'string',
        'description': 'Optional glob pattern to filter files '
            '(e.g. "*.csv", "**/*.json"). Omit to list all files.',
      },
    },
    'required': <dynamic>[],
  },
);

/// Tool definition for appending content to a file in the workspace.
///
/// Requires `fileName` and `content` arguments. Creates the file if it does
/// not exist; appends to the end if it does.
const ToolDefinition appendFileTool = ToolDefinition(
  name: 'append_file',
  description: 'Appends content to a file in the workspace directory. '
      'Creates the file if it does not exist.',
  parameters: <String, dynamic>{
    'type': 'object',
    'properties': <String, dynamic>{
      'fileName': <String, dynamic>{
        'type': 'string',
        'description': 'The relative path to the file within the workspace '
            '(e.g. "log.txt", "output/results.csv").',
      },
      'content': <String, dynamic>{
        'type': 'string',
        'description': 'The content to append to the file.',
      },
    },
    'required': <dynamic>['fileName', 'content'],
  },
);

// ─────────────────────────────────────────────────────────────────────────────
// Handler factory
// ─────────────────────────────────────────────────────────────────────────────

/// Creates a map of file-context tool handlers backed by [ctx].
///
/// Returns handlers for `read_file`, `write_file`, `list_files`, and
/// `append_file`. Each handler parses its JSON arguments, delegates to the
/// corresponding [FileContext] method, and returns a human-readable result
/// string. Errors are caught and returned as error strings so the LLM can
/// self-correct.
///
/// ```dart
/// final handlers = createHandlers(ctx);
/// final result = await handlers['read_file']!({'fileName': 'notes.txt'});
/// ```
Map<String, Future<String> Function(Map<String, dynamic>)> createHandlers(
  FileContext ctx,
) {
  return {
    'read_file': (Map<String, dynamic> args) async {
      final fileName = args['fileName'] as String;
      if (_containsTraversal(fileName)) {
        return 'Error: '
            '${PathTraversalException(path: fileName)}';
      }
      try {
        return ctx.read(fileName);
      } on FileNotFoundException catch (e) {
        return 'Error: file not found — $e';
      } on PathTraversalException catch (e) {
        return 'Error: $e';
      }
    },
    'write_file': (Map<String, dynamic> args) async {
      final fileName = args['fileName'] as String;
      final content = args['content'] as String;
      if (_containsTraversal(fileName)) {
        return 'Error: '
            '${PathTraversalException(path: fileName)}';
      }
      try {
        ctx.write(fileName, content);
        return "File '$fileName' written successfully "
            '(${content.length} bytes).';
      } on PathTraversalException catch (e) {
        return 'Error: $e';
      }
    },
    'list_files': (Map<String, dynamic> args) async {
      final glob = args['glob'] as String?;
      final files = ctx.listFiles(glob: glob);
      if (files.isEmpty) {
        return 'No files found.';
      }
      return '${files.length} files:\n${files.map((f) => '- $f').join('\n')}';
    },
    'append_file': (Map<String, dynamic> args) async {
      final fileName = args['fileName'] as String;
      final content = args['content'] as String;
      if (_containsTraversal(fileName)) {
        return 'Error: '
            '${PathTraversalException(path: fileName)}';
      }
      try {
        ctx.append(fileName, content);
        return "Appended ${content.length} bytes to '$fileName' successfully.";
      } on PathTraversalException catch (e) {
        return 'Error: $e';
      }
    },
  };
}

/// Returns `true` if [fileName] contains `..` path segments that could
/// escape the workspace root.
///
/// This is a defense-in-depth check that runs before delegating to
/// [FileContext], which performs its own (canonical-path-based) validation.
bool _containsTraversal(String fileName) {
  // Split on both Unix and Windows separators.
  return fileName.split(RegExp(r'[/\\]')).contains('..');
}
