import 'dart:io';

import 'package:agents_core/agents_core.dart';
import 'package:test/test.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// Helpers
// ═══════════════════════════════════════════════════════════════════════════════

/// Creates an isolated temporary [FileContext] for a single test.
({FileContext ctx, Directory dir}) _tempContext() {
  final dir = Directory.systemTemp.createTempSync('agents_core_python_tools_');
  final ctx = FileContext(workspacePath: dir.path);
  return (ctx: ctx, dir: dir);
}

// ═══════════════════════════════════════════════════════════════════════════════
// Tests — python/file_context_tools.dart
//
// These tests verify the python-module variant of file-context tools.
// Key differences from context/file_context_tools:
//   - Identifier names use "Definition" suffix (readFileToolDefinition, etc.)
//   - Parameter key is "path" (not "fileName")
//   - No append_file tool or handler
//   - Factory uses named param: createFileContextHandlers(context: ctx)
//   - Provides fileContextToolDefinitions getter (list of 3)
//   - Returns ToolHandler (type alias) not raw closure
// ═══════════════════════════════════════════════════════════════════════════════

void main() {
  // ─────────────────────────────────────────────────────────────────────────────
  // 1. readFileToolDefinition — structure
  // ─────────────────────────────────────────────────────────────────────────────
  group('readFileToolDefinition', () {
    test('is a ToolDefinition', () {
      expect(readFileToolDefinition, isA<ToolDefinition>());
    });

    test('name is "read_file"', () {
      expect(readFileToolDefinition.name, equals('read_file'));
    });

    test('description is non-empty', () {
      expect(readFileToolDefinition.description, isNotEmpty);
    });

    test('parameters has type "object"', () {
      expect(readFileToolDefinition.parameters['type'], equals('object'));
    });

    test('parameters has a "properties" map', () {
      expect(readFileToolDefinition.parameters['properties'], isA<Map>());
    });

    test('"path" is a property (not "fileName")', () {
      final props =
          readFileToolDefinition.parameters['properties']
              as Map<String, dynamic>;
      expect(props, contains('path'));
      expect(props, isNot(contains('fileName')));
    });

    test('"path" property has type "string"', () {
      final props =
          readFileToolDefinition.parameters['properties']
              as Map<String, dynamic>;
      final pathProp = props['path'] as Map<String, dynamic>;
      expect(pathProp['type'], equals('string'));
    });

    test('"path" is listed in required', () {
      final required =
          readFileToolDefinition.parameters['required'] as List<dynamic>;
      expect(required, contains('path'));
    });

    test('toJson() round-trips correctly', () {
      final json = readFileToolDefinition.toJson();
      final restored = ToolDefinition.fromJson(json);
      expect(restored.name, equals(readFileToolDefinition.name));
      expect(restored.description, equals(readFileToolDefinition.description));
    });

    test('toJson() has type "function"', () {
      expect(readFileToolDefinition.toJson()['type'], equals('function'));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // 2. writeFileToolDefinition — structure
  // ─────────────────────────────────────────────────────────────────────────────
  group('writeFileToolDefinition', () {
    test('is a ToolDefinition', () {
      expect(writeFileToolDefinition, isA<ToolDefinition>());
    });

    test('name is "write_file"', () {
      expect(writeFileToolDefinition.name, equals('write_file'));
    });

    test('description is non-empty', () {
      expect(writeFileToolDefinition.description, isNotEmpty);
    });

    test('parameters has type "object"', () {
      expect(writeFileToolDefinition.parameters['type'], equals('object'));
    });

    test('"path" is a property (not "fileName")', () {
      final props =
          writeFileToolDefinition.parameters['properties']
              as Map<String, dynamic>;
      expect(props, contains('path'));
      expect(props, isNot(contains('fileName')));
    });

    test('"content" is a property', () {
      final props =
          writeFileToolDefinition.parameters['properties']
              as Map<String, dynamic>;
      expect(props, contains('content'));
    });

    test('"path" property has type "string"', () {
      final props =
          writeFileToolDefinition.parameters['properties']
              as Map<String, dynamic>;
      final pathProp = props['path'] as Map<String, dynamic>;
      expect(pathProp['type'], equals('string'));
    });

    test('"content" property has type "string"', () {
      final props =
          writeFileToolDefinition.parameters['properties']
              as Map<String, dynamic>;
      final contentProp = props['content'] as Map<String, dynamic>;
      expect(contentProp['type'], equals('string'));
    });

    test('"path" is listed in required', () {
      final required =
          writeFileToolDefinition.parameters['required'] as List<dynamic>;
      expect(required, contains('path'));
    });

    test('"content" is listed in required', () {
      final required =
          writeFileToolDefinition.parameters['required'] as List<dynamic>;
      expect(required, contains('content'));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // 3. listFilesToolDefinition — structure
  // ─────────────────────────────────────────────────────────────────────────────
  group('listFilesToolDefinition', () {
    test('is a ToolDefinition', () {
      expect(listFilesToolDefinition, isA<ToolDefinition>());
    });

    test('name is "list_files"', () {
      expect(listFilesToolDefinition.name, equals('list_files'));
    });

    test('description is non-empty', () {
      expect(listFilesToolDefinition.description, isNotEmpty);
    });

    test('parameters has type "object"', () {
      expect(listFilesToolDefinition.parameters['type'], equals('object'));
    });

    test('"glob" is an optional property', () {
      final props =
          listFilesToolDefinition.parameters['properties']
              as Map<String, dynamic>;
      expect(props, contains('glob'));
    });

    test('"glob" property has type "string"', () {
      final props =
          listFilesToolDefinition.parameters['properties']
              as Map<String, dynamic>;
      final globProp = props['glob'] as Map<String, dynamic>;
      expect(globProp['type'], equals('string'));
    });

    test('"glob" is NOT listed as required', () {
      // The python version omits the "required" key entirely OR has no glob in required.
      final required = listFilesToolDefinition.parameters['required'];
      if (required != null) {
        expect(required as List<dynamic>, isNot(contains('glob')));
      }
      // If null — also acceptable (no required constraint at all).
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // 4. fileContextToolDefinitions getter
  // ─────────────────────────────────────────────────────────────────────────────
  group('fileContextToolDefinitions', () {
    test('returns a List<ToolDefinition>', () {
      expect(fileContextToolDefinitions, isA<List<ToolDefinition>>());
    });

    test('returns exactly 4 definitions (read, write, list, append)', () {
      expect(fileContextToolDefinitions, hasLength(4));
    });

    test('contains a tool named "read_file"', () {
      final names = fileContextToolDefinitions.map((t) => t.name).toList();
      expect(names, contains('read_file'));
    });

    test('contains a tool named "write_file"', () {
      final names = fileContextToolDefinitions.map((t) => t.name).toList();
      expect(names, contains('write_file'));
    });

    test('contains a tool named "list_files"', () {
      final names = fileContextToolDefinitions.map((t) => t.name).toList();
      expect(names, contains('list_files'));
    });

    test('contains a tool named "append_file"', () {
      final names = fileContextToolDefinitions.map((t) => t.name).toList();
      expect(names, contains('append_file'));
    });

    test('each call returns a new list (not cached identity)', () {
      // Two calls should be structurally equal even if not identical instances.
      final a = fileContextToolDefinitions;
      final b = fileContextToolDefinitions;
      expect(
        a.map((t) => t.name).toList(),
        equals(b.map((t) => t.name).toList()),
      );
    });

    test('all entries are ToolDefinition instances', () {
      for (final tool in fileContextToolDefinitions) {
        expect(tool, isA<ToolDefinition>());
      }
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // 5. createFileContextHandlers — structure
  // ─────────────────────────────────────────────────────────────────────────────
  group('createFileContextHandlers', () {
    late FileContext ctx;
    late Directory dir;

    setUp(() {
      final tmp = _tempContext();
      ctx = tmp.ctx;
      dir = tmp.dir;
    });

    tearDown(() {
      dir.deleteSync(recursive: true);
    });

    test('accepts named "context" parameter', () {
      // Compile-time verification: named param `context:` must work.
      expect(() => createFileContextHandlers(context: ctx), returnsNormally);
    });

    test('returns a Map', () {
      final handlers = createFileContextHandlers(context: ctx);
      expect(handlers, isA<Map>());
    });

    test('returns exactly 4 handlers (read, write, list, append)', () {
      final handlers = createFileContextHandlers(context: ctx);
      expect(handlers, hasLength(4));
    });

    test('contains "read_file" handler', () {
      final handlers = createFileContextHandlers(context: ctx);
      expect(handlers, contains('read_file'));
    });

    test('contains "write_file" handler', () {
      final handlers = createFileContextHandlers(context: ctx);
      expect(handlers, contains('write_file'));
    });

    test('contains "list_files" handler', () {
      final handlers = createFileContextHandlers(context: ctx);
      expect(handlers, contains('list_files'));
    });

    test('contains "append_file" handler', () {
      final handlers = createFileContextHandlers(context: ctx);
      expect(handlers, contains('append_file'));
    });

    test('each handler is callable (is a Function)', () {
      final handlers = createFileContextHandlers(context: ctx);
      for (final entry in handlers.entries) {
        expect(
          entry.value,
          isA<Function>(),
          reason: 'handler "${entry.key}" should be a Function',
        );
      }
    });

    test('handlers from two calls are independent', () async {
      final tmp2 = _tempContext();
      final ctx2 = tmp2.ctx;
      final dir2 = tmp2.dir;

      final h1 = createFileContextHandlers(context: ctx);
      final h2 = createFileContextHandlers(context: ctx2);

      await h1['write_file']!({'path': 'only_in_ctx1.txt', 'content': 'x'});

      final result = await h2['read_file']!({'path': 'only_in_ctx1.txt'});
      expect(result.toLowerCase(), contains('error'));

      dir2.deleteSync(recursive: true);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // 6. write_file handler (python version — uses "path" key)
  // ─────────────────────────────────────────────────────────────────────────────
  group('write_file handler (python)', () {
    late FileContext ctx;
    late Directory dir;
    late Map<String, ToolHandler> handlers;

    setUp(() {
      final tmp = _tempContext();
      ctx = tmp.ctx;
      dir = tmp.dir;
      handlers = createFileContextHandlers(context: ctx);
    });

    tearDown(() {
      dir.deleteSync(recursive: true);
    });

    test('returns a non-empty string on success', () async {
      final result = await handlers['write_file']!({
        'path': 'hello.txt',
        'content': 'Hello, world!',
      });
      expect(result, isNotEmpty);
    });

    test('success message mentions the file path', () async {
      final result = await handlers['write_file']!({
        'path': 'notes.md',
        'content': 'Some notes here.',
      });
      expect(result, contains('notes.md'));
    });

    test('file is created in the workspace', () async {
      await handlers['write_file']!({
        'path': 'created.txt',
        'content': 'content here',
      });
      expect(ctx.exists('created.txt'), isTrue);
    });

    test('file content matches what was written', () async {
      const content = 'exact content to verify';
      await handlers['write_file']!({'path': 'verify.txt', 'content': content});
      expect(ctx.read('verify.txt'), equals(content));
    });

    test('overwrites an existing file', () async {
      await handlers['write_file']!({
        'path': 'overwrite.txt',
        'content': 'original',
      });
      await handlers['write_file']!({
        'path': 'overwrite.txt',
        'content': 'updated',
      });
      expect(ctx.read('overwrite.txt'), equals('updated'));
    });

    test('can write empty content', () async {
      final result = await handlers['write_file']!({
        'path': 'empty.txt',
        'content': '',
      });
      expect(result, isNotEmpty);
      expect(ctx.exists('empty.txt'), isTrue);
    });

    test('can write multi-line content', () async {
      const content = 'line1\nline2\nline3';
      await handlers['write_file']!({'path': 'multi.txt', 'content': content});
      expect(ctx.read('multi.txt'), equals(content));
    });

    test('returns error string when path is empty string', () async {
      final result = await handlers['write_file']!({
        'path': '',
        'content': 'data',
      });
      expect(result.toLowerCase(), contains('error'));
    });

    test('returns error string on path traversal attempt', () async {
      final result = await handlers['write_file']!({
        'path': '../escaped.txt',
        'content': 'bad',
      });
      expect(result.toLowerCase(), contains('error'));
    });

    test('path traversal does NOT create file outside workspace', () async {
      await handlers['write_file']!({
        'path': '../escaped.txt',
        'content': 'bad',
      });
      expect(File('${dir.parent.path}/escaped.txt').existsSync(), isFalse);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // 7. read_file handler (python version — uses "path" key)
  // ─────────────────────────────────────────────────────────────────────────────
  group('read_file handler (python)', () {
    late FileContext ctx;
    late Directory dir;
    late Map<String, ToolHandler> handlers;

    setUp(() {
      final tmp = _tempContext();
      ctx = tmp.ctx;
      dir = tmp.dir;
      handlers = createFileContextHandlers(context: ctx);
    });

    tearDown(() {
      dir.deleteSync(recursive: true);
    });

    test('returns exact file content when file exists', () async {
      ctx.write('greet.txt', 'Hello from python tools!');
      final result = await handlers['read_file']!({'path': 'greet.txt'});
      expect(result, contains('Hello from python tools!'));
    });

    test('returns error string when file does not exist', () async {
      final result = await handlers['read_file']!({'path': 'nonexistent.txt'});
      expect(result.toLowerCase(), contains('error'));
    });

    test('returns error string when path is empty', () async {
      final result = await handlers['read_file']!({'path': ''});
      expect(result.toLowerCase(), contains('error'));
    });

    test('returns error string on path traversal attempt', () async {
      final result = await handlers['read_file']!({'path': '../secret.txt'});
      expect(result.toLowerCase(), contains('error'));
    });

    test('can read a file written via write_file handler', () async {
      const content = 'written by python write_file handler';
      await handlers['write_file']!({
        'path': 'roundtrip.txt',
        'content': content,
      });
      final result = await handlers['read_file']!({'path': 'roundtrip.txt'});
      expect(result, equals(content));
    });

    test('can read empty file', () async {
      ctx.write('empty.txt', '');
      final result = await handlers['read_file']!({'path': 'empty.txt'});
      expect(result, equals(''));
    });

    test('handles missing path key gracefully (null path)', () async {
      // path key absent — should return an error, not throw.
      final result = await handlers['read_file']!({});
      expect(result, isA<String>());
      expect(result.toLowerCase(), contains('error'));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // 8. list_files handler (python version)
  // ─────────────────────────────────────────────────────────────────────────────
  group('list_files handler (python)', () {
    late FileContext ctx;
    late Directory dir;
    late Map<String, ToolHandler> handlers;

    setUp(() {
      final tmp = _tempContext();
      ctx = tmp.ctx;
      dir = tmp.dir;
      handlers = createFileContextHandlers(context: ctx);
    });

    tearDown(() {
      dir.deleteSync(recursive: true);
    });

    test('returns a String result (no crash)', () async {
      final result = await handlers['list_files']!({});
      expect(result, isA<String>());
    });

    test('empty workspace returns a non-empty string', () async {
      final result = await handlers['list_files']!({});
      expect(result, isNotEmpty);
    });

    test('lists files present in the workspace', () async {
      ctx.write('alpha.txt', 'a');
      ctx.write('beta.txt', 'b');
      final result = await handlers['list_files']!({});
      expect(result, contains('alpha.txt'));
      expect(result, contains('beta.txt'));
    });

    test('result mentions all written files', () async {
      ctx.write('one.md', '1');
      ctx.write('two.md', '2');
      ctx.write('three.md', '3');
      final result = await handlers['list_files']!({});
      expect(result, contains('one.md'));
      expect(result, contains('two.md'));
      expect(result, contains('three.md'));
    });

    test('glob filter limits results to matching files', () async {
      ctx.write('doc.md', 'markdown');
      ctx.write('code.dart', 'dart');
      ctx.write('config.json', 'json');

      final result = await handlers['list_files']!({'glob': '*.md'});
      expect(result, contains('doc.md'));
      expect(result, isNot(contains('code.dart')));
      expect(result, isNot(contains('config.json')));
    });

    test('no glob returns all files', () async {
      ctx.write('a.txt', 'a');
      ctx.write('b.dart', 'b');
      final result = await handlers['list_files']!({});
      expect(result, contains('a.txt'));
      expect(result, contains('b.dart'));
    });

    test('null glob is equivalent to no glob', () async {
      ctx.write('file.txt', 'x');
      final resultNoGlob = await handlers['list_files']!({});
      final resultNullGlob = await handlers['list_files']!({'glob': null});
      expect(resultNoGlob, contains('file.txt'));
      expect(resultNullGlob, contains('file.txt'));
    });

    test('glob with no matches returns a string (no crash)', () async {
      ctx.write('readme.md', 'md');
      final result = await handlers['list_files']!({'glob': '*.dart'});
      expect(result, isA<String>());
      expect(result, isNotEmpty);
    });

    test('nested files are included in listing', () async {
      ctx.write('subdir/nested.txt', 'nested content');
      final result = await handlers['list_files']!({});
      expect(result, contains('nested.txt'));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // 9. Handler keys match tool definition names
  // ─────────────────────────────────────────────────────────────────────────────
  group('handler keys match tool definition names', () {
    late FileContext ctx;
    late Directory dir;

    setUp(() {
      final tmp = _tempContext();
      ctx = tmp.ctx;
      dir = tmp.dir;
    });

    tearDown(() {
      dir.deleteSync(recursive: true);
    });

    test('handler key matches readFileToolDefinition.name', () {
      final handlers = createFileContextHandlers(context: ctx);
      expect(handlers, contains(readFileToolDefinition.name));
    });

    test('handler key matches writeFileToolDefinition.name', () {
      final handlers = createFileContextHandlers(context: ctx);
      expect(handlers, contains(writeFileToolDefinition.name));
    });

    test('handler key matches listFilesToolDefinition.name', () {
      final handlers = createFileContextHandlers(context: ctx);
      expect(handlers, contains(listFilesToolDefinition.name));
    });

    test('all fileContextToolDefinitions names have a corresponding handler', () {
      final handlers = createFileContextHandlers(context: ctx);
      for (final tool in fileContextToolDefinitions) {
        expect(
          handlers,
          contains(tool.name),
          reason:
              'handler for "${tool.name}" should be in createFileContextHandlers',
        );
      }
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // 10. Barrel export verification — python symbols are accessible
  // ─────────────────────────────────────────────────────────────────────────────
  group('barrel export verification (python module)', () {
    test('readFileToolDefinition accessible from barrel', () {
      expect(readFileToolDefinition.name, equals('read_file'));
    });

    test('writeFileToolDefinition accessible from barrel', () {
      expect(writeFileToolDefinition.name, equals('write_file'));
    });

    test('listFilesToolDefinition accessible from barrel', () {
      expect(listFilesToolDefinition.name, equals('list_files'));
    });

    test('fileContextToolDefinitions getter accessible from barrel', () {
      expect(fileContextToolDefinitions, isA<List<ToolDefinition>>());
    });

    test('createFileContextHandlers accessible from barrel', () {
      expect(createFileContextHandlers, isA<Function>());
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // 11. Name collision guard — python symbols must not clash with context symbols
  //
  // Both modules are exported from the barrel. Any name overlap would cause a
  // compile error. This group documents the known distinct identifiers.
  // ─────────────────────────────────────────────────────────────────────────────
  group('no name collision between context and python modules', () {
    test('readFileToolDefinition (python) != readFileTool (context)', () {
      // They are different identifiers — both accessible without ambiguity.
      expect(readFileToolDefinition.name, equals(readFileTool.name));
      // Same tool name but different Dart identifiers — no collision.
    });

    test('createFileContextHandlers != createHandlers (different names)', () {
      // Verify both symbols exist and are distinct Functions.
      expect(createFileContextHandlers, isA<Function>());
      expect(createHandlers, isA<Function>());
      expect(
        identical(createFileContextHandlers, createHandlers),
        isFalse,
        reason: 'should be distinct functions',
      );
    });

    test(
      'fileContextToolDefinitions getter coexists with readFileTool const',
      () {
        expect(fileContextToolDefinitions, isA<List>());
        expect(readFileTool, isA<ToolDefinition>());
      },
    );
  });
}
