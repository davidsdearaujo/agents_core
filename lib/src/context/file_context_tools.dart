import '../agent/react_agent.dart';
import '../exceptions/file_context_exceptions.dart';
import '../models/tool_definition.dart';
import 'file_context.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Tool definitions
// ─────────────────────────────────────────────────────────────────────────────

/// Tool definition for reading a file from the workspace.
///
/// Requires a `path` argument specifying the relative path within the
/// workspace.
const ToolDefinition readFileTool = ToolDefinition(
  name: 'read_file',
  description:
      'Reads the contents of a file from the workspace directory. '
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
    'required': <dynamic>['path'],
  },
);

/// Tool definition for writing content to a file in the workspace.
///
/// Requires `path` and `content` arguments. Creates the file if it does
/// not exist; overwrites if it does. Parent directories are created
/// automatically.
const ToolDefinition writeFileTool = ToolDefinition(
  name: 'write_file',
  description:
      'Writes content to a file in the workspace directory. '
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
    'required': <dynamic>['path', 'content'],
  },
);

/// Tool definition for listing files in the workspace.
///
/// Accepts an optional `glob` parameter to filter results. When omitted,
/// all files are returned.
const ToolDefinition listFilesTool = ToolDefinition(
  name: 'list_files',
  description:
      'Lists files in the workspace directory. '
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
    'required': <dynamic>[],
  },
);

/// Tool definition for appending content to a file in the workspace.
///
/// Requires `path` and `content` arguments. Creates the file if it does
/// not exist; appends to the end if it does.
const ToolDefinition appendFileTool = ToolDefinition(
  name: 'append_file',
  description:
      'Appends content to a file in the workspace directory. '
      'Creates the file if it does not exist.',
  parameters: <String, dynamic>{
    'type': 'object',
    'properties': <String, dynamic>{
      'path': <String, dynamic>{
        'type': 'string',
        'description':
            'The relative path to the file within the workspace '
            '(e.g. "log.txt", "output/results.csv").',
      },
      'content': <String, dynamic>{
        'type': 'string',
        'description': 'The content to append to the file.',
      },
    },
    'required': <dynamic>['path', 'content'],
  },
);

// ─────────────────────────────────────────────────────────────────────────────
// Backward-compatibility aliases (migrated from python/file_context_tools.dart)
// ─────────────────────────────────────────────────────────────────────────────

/// Backward-compatible alias for [readFileTool].
///
/// Retained for consumers that previously imported from
/// `python/file_context_tools.dart`. Prefer [readFileTool] for new code.
final ToolDefinition readFileToolDefinition = readFileTool;

/// Backward-compatible alias for [writeFileTool].
///
/// Retained for consumers that previously imported from
/// `python/file_context_tools.dart`. Prefer [writeFileTool] for new code.
final ToolDefinition writeFileToolDefinition = writeFileTool;

/// Backward-compatible alias for [listFilesTool].
///
/// Retained for consumers that previously imported from
/// `python/file_context_tools.dart`. Prefer [listFilesTool] for new code.
final ToolDefinition listFilesToolDefinition = listFilesTool;

// ─────────────────────────────────────────────────────────────────────────────
// Tool list
// ─────────────────────────────────────────────────────────────────────────────

/// Returns all file-context [ToolDefinition]s: [readFileTool], [writeFileTool],
/// [listFilesTool], and [appendFileTool].
///
/// Use this getter when registering tools with an agent:
///
/// ```dart
/// final agent = ReActAgent(
///   tools: [...fileContextToolDefinitions, ...myOtherTools],
///   toolHandlers: createHandlers(context),
/// );
/// ```
List<ToolDefinition> get fileContextToolDefinitions => [
  readFileTool,
  writeFileTool,
  listFilesTool,
  appendFileTool,
];

// ─────────────────────────────────────────────────────────────────────────────
// Handler factories
// ─────────────────────────────────────────────────────────────────────────────

/// Creates a map of file-context tool handlers backed by [context].
///
/// Returns handlers for `read_file`, `write_file`, `list_files`, and
/// `append_file`. Each handler parses its JSON arguments, delegates to the
/// corresponding [FileContext] method, and returns a human-readable result
/// string.
///
/// Errors (empty path, path traversal, file not found) are caught and
/// returned as error strings so the LLM can self-correct rather than
/// crashing the agent loop.
///
/// All handlers read the file path from the `"path"` argument key.
///
/// ```dart
/// final handlers = createHandlers(context);
/// final result = await handlers['read_file']!({'path': 'notes.txt'});
/// ```
///
/// See also: [createFileContextHandlers] — an alias with a named `context:`
/// parameter that may be more ergonomic at call sites.
Map<String, ToolHandler> createHandlers(FileContext context) {
  return {
    'read_file': (Map<String, dynamic> args) async {
      final path = args['path'] as String? ?? '';
      if (path.isEmpty) {
        return 'Error: "path" parameter is required and must not be empty.';
      }
      if (_containsTraversal(path)) {
        return 'Error: ${PathTraversalException(path: path)}';
      }
      try {
        return context.read(path);
      } on FileNotFoundException catch (e) {
        return 'Error: file not found — $e';
      } on PathTraversalException catch (e) {
        return 'Error: $e';
      }
    },
    'write_file': (Map<String, dynamic> args) async {
      final path = args['path'] as String? ?? '';
      final content = args['content'] as String? ?? '';
      if (path.isEmpty) {
        return 'Error: "path" parameter is required and must not be empty.';
      }
      if (_containsTraversal(path)) {
        return 'Error: ${PathTraversalException(path: path)}';
      }
      try {
        context.write(path, content);
        return "File '$path' written successfully (${content.length} characters).";
      } on PathTraversalException catch (e) {
        return 'Error: $e';
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
    'append_file': (Map<String, dynamic> args) async {
      final path = args['path'] as String? ?? '';
      final content = args['content'] as String? ?? '';
      if (path.isEmpty) {
        return 'Error: "path" parameter is required and must not be empty.';
      }
      if (_containsTraversal(path)) {
        return 'Error: ${PathTraversalException(path: path)}';
      }
      try {
        context.append(path, content);
        return "Appended ${content.length} characters to '$path' successfully.";
      } on PathTraversalException catch (e) {
        return 'Error: $e';
      }
    },
  };
}

/// Alias for [createHandlers] that accepts a named `context:` parameter.
///
/// Prefer this form when building handler maps at call sites where named
/// parameters improve readability:
///
/// ```dart
/// final handlers = createFileContextHandlers(context: fileContext);
/// ```
///
/// See also: [createHandlers] — the positional form.
Map<String, ToolHandler> createFileContextHandlers({
  required FileContext context,
}) => createHandlers(context);

// ─────────────────────────────────────────────────────────────────────────────
// Private helpers
// ─────────────────────────────────────────────────────────────────────────────

/// Returns `true` if [path] contains `..` segments that could escape the
/// workspace root.
///
/// This is a defense-in-depth check that runs before delegating to
/// [FileContext], which performs its own canonical-path-based validation.
/// Splits on both Unix (`/`) and Windows (`\`) separators.
bool _containsTraversal(String path) {
  return path.split(RegExp(r'[/\\]')).contains('..');
}
