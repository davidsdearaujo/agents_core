import 'dart:io';

import '../exceptions/file_context_exceptions.dart';

/// A sandboxed file-system abstraction rooted at a workspace directory.
///
/// [FileContext] provides read, write, append, delete, and listing operations
/// scoped to a single [workspacePath]. Every path argument is validated against
/// directory-traversal attacks (`../`) before any I/O is performed.
///
/// ```dart
/// final ctx = FileContext(workspacePath: '/tmp/workspace');
/// ctx.write('notes.txt', 'hello');
/// print(ctx.read('notes.txt')); // hello
/// ```
class FileContext {
  /// Creates a [FileContext] rooted at [workspacePath].
  ///
  /// The directory is created (recursively) if it does not already exist.
  ///
  /// Throws [ArgumentError] if [workspacePath] is empty.
  FileContext({required String workspacePath})
      : _root = Directory(workspacePath) {
    if (workspacePath.isEmpty) {
      throw ArgumentError.value(
        workspacePath,
        'workspacePath',
        'must not be empty',
      );
    }
    _root.createSync(recursive: true);
  }

  final Directory _root;

  /// The absolute path to the workspace root directory.
  String get workspacePath => _root.path;

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Writes [content] to [fileName], creating the file if it does not exist
  /// and overwriting it if it does.
  ///
  /// Parent directories are created automatically.
  ///
  /// Throws [PathTraversalException] if [fileName] escapes the workspace.
  void write(String fileName, String content) {
    final file = _resolve(fileName);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
  }

  /// Reads the entire contents of [fileName] as a string.
  ///
  /// Throws [FileNotFoundException] if the file does not exist.
  /// Throws [PathTraversalException] if [fileName] escapes the workspace.
  String read(String fileName) {
    final file = _resolve(fileName);
    if (!file.existsSync()) {
      throw FileNotFoundException(path: file.path);
    }
    return file.readAsStringSync();
  }

  /// Returns `true` if [fileName] exists in the workspace.
  ///
  /// Throws [PathTraversalException] if [fileName] escapes the workspace.
  bool exists(String fileName) {
    final file = _resolve(fileName);
    return file.existsSync();
  }

  /// Lists file paths in the workspace, optionally filtered by a [glob]
  /// pattern.
  ///
  /// Returned paths are relative to the workspace root. Only regular files
  /// are included (directories are excluded).
  ///
  /// The [glob] parameter supports simple patterns:
  /// - `*` matches any sequence of characters except `/`
  /// - `**` matches any sequence of characters including `/`
  /// - `?` matches a single character except `/`
  ///
  /// ```dart
  /// final dartFiles = ctx.listFiles(glob: '*.dart');
  /// final allNested = ctx.listFiles(glob: '**/*.json');
  /// ```
  List<String> listFiles({String? glob}) {
    final entities = _root.listSync(recursive: true);
    final relativePaths = <String>[];

    final rootPrefix = _normalizedRootPrefix;

    for (final entity in entities) {
      if (entity is! File) continue;
      final relative = entity.path.substring(rootPrefix.length);
      if (glob != null && !_matchGlob(glob, relative)) continue;
      relativePaths.add(relative);
    }

    relativePaths.sort();
    return relativePaths;
  }

  /// Appends [content] to [fileName], creating the file if it does not exist.
  ///
  /// Throws [PathTraversalException] if [fileName] escapes the workspace.
  void append(String fileName, String content) {
    final file = _resolve(fileName);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content, mode: FileMode.append);
  }

  /// Deletes [fileName] from the workspace.
  ///
  /// Throws [FileNotFoundException] if the file does not exist.
  /// Throws [PathTraversalException] if [fileName] escapes the workspace.
  void delete(String fileName) {
    final file = _resolve(fileName);
    if (!file.existsSync()) {
      throw FileNotFoundException(path: file.path);
    }
    file.deleteSync();
  }

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  /// The root path with a trailing separator, used for stripping prefixes.
  String get _normalizedRootPrefix {
    final rootPath = _root.absolute.path;
    return rootPath.endsWith(Platform.pathSeparator)
        ? rootPath
        : '$rootPath${Platform.pathSeparator}';
  }

  /// Resolves [fileName] to an absolute [File] within the workspace.
  ///
  /// The path is normalized via [Uri.file] + [Uri.normalizePath] to collapse
  /// `.` and `..` segments **before** the prefix check, preventing traversal
  /// attacks that embed `..` after a valid directory name
  /// (e.g. `a/../../etc/passwd`).
  ///
  /// [Uri.file] is used instead of [Uri.parse] to correctly handle file-system
  /// paths that contain spaces or other characters that [Uri.parse] would
  /// percent-encode.
  ///
  /// Throws [PathTraversalException] if the resolved path escapes the root.
  File _resolve(String fileName) {
    final rootAbsolute = _root.absolute.path;

    // Build the joined path and normalize it to resolve . and .. segments.
    // Uri.file correctly round-trips file-system paths (including spaces)
    // without introducing percent-encoding artifacts.
    final joined = '$rootAbsolute${Platform.pathSeparator}$fileName';
    final normalized = Uri.file(joined).normalizePath().toFilePath();

    // Build the canonical root prefix (with trailing separator).
    final rootPrefix = rootAbsolute.endsWith(Platform.pathSeparator)
        ? rootAbsolute
        : '$rootAbsolute${Platform.pathSeparator}';

    // Reject if the normalized path escapes the workspace root.
    if (!normalized.startsWith(rootPrefix) && normalized != rootAbsolute) {
      throw PathTraversalException(path: fileName);
    }

    return File(normalized);
  }

  /// Matches a relative [path] against a simple [glob] pattern.
  ///
  /// Supports `*` (any non-separator chars), `**` (any chars including
  /// separator), and `?` (single non-separator char).
  static bool _matchGlob(String glob, String path) {
    final buffer = StringBuffer('^');

    for (var i = 0; i < glob.length; i++) {
      final char = glob[i];

      if (char == '*') {
        // Check for **
        if (i + 1 < glob.length && glob[i + 1] == '*') {
          buffer.write('.*');
          i++; // skip the second *
          // Skip a following / after ** (e.g. **/ matches nested dirs)
          if (i + 1 < glob.length && glob[i + 1] == '/') {
            i++;
            buffer.write('(?:/)?');
          }
        } else {
          // Single * — match anything except path separator
          buffer.write('[^/]*');
        }
      } else if (char == '?') {
        buffer.write('[^/]');
      } else if (_regexMetaChars.contains(char)) {
        buffer.write('\\$char');
      } else {
        buffer.write(char);
      }
    }

    buffer.write(r'$');
    return RegExp(buffer.toString()).hasMatch(path);
  }

  /// Characters that must be escaped when building a regex from a glob.
  static const _regexMetaChars = r'\.+^${}()|[]';
}
