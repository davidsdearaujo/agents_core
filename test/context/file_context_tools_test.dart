import 'dart:io';

import 'package:agents_core/agents_core.dart';
import 'package:test/test.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// Helpers
// ═══════════════════════════════════════════════════════════════════════════════

/// Creates an isolated temporary [FileContext] for a single test.
///
/// Returns both the [FileContext] and the underlying [Directory] so the
/// caller can perform raw filesystem assertions and clean up via [Directory.deleteSync].
({FileContext ctx, Directory dir}) _tempContext() {
  final dir = Directory.systemTemp.createTempSync('agents_core_tools_test_');
  final ctx = FileContext(workspacePath: dir.path);
  return (ctx: ctx, dir: dir);
}

// ═══════════════════════════════════════════════════════════════════════════════
// Tests
// ═══════════════════════════════════════════════════════════════════════════════

void main() {
  // ─────────────────────────────────────────────────────────────────────────────
  // 1. Tool definition objects — identity and structure
  // ─────────────────────────────────────────────────────────────────────────────
  group('readFileTool', () {
    group('type', () {
      test('is a ToolDefinition', () {
        expect(readFileTool, isA<ToolDefinition>());
      });
    });

    group('name', () {
      test('name is "read_file"', () {
        expect(readFileTool.name, equals('read_file'));
      });
    });

    group('description', () {
      test('description is non-empty', () {
        expect(readFileTool.description, isNotEmpty);
      });
    });

    group('parameters', () {
      test('parameters has type "object"', () {
        expect(readFileTool.parameters['type'], equals('object'));
      });

      test('parameters has a "properties" map', () {
        expect(readFileTool.parameters['properties'], isA<Map>());
      });

      test('"fileName" is a property', () {
        final props =
            readFileTool.parameters['properties'] as Map<String, dynamic>;
        expect(props, contains('fileName'));
      });

      test('"fileName" property has type "string"', () {
        final props =
            readFileTool.parameters['properties'] as Map<String, dynamic>;
        final fileNameProp = props['fileName'] as Map<String, dynamic>;
        expect(fileNameProp['type'], equals('string'));
      });

      test('"fileName" is listed in required', () {
        final required = readFileTool.parameters['required'] as List<dynamic>;
        expect(required, contains('fileName'));
      });
    });

    group('toJson()', () {
      test('round-trips through toJson() / fromJson()', () {
        final json = readFileTool.toJson();
        final restored = ToolDefinition.fromJson(json);
        expect(restored.name, equals(readFileTool.name));
        expect(restored.description, equals(readFileTool.description));
      });

      test('toJson() has type "function"', () {
        expect(readFileTool.toJson()['type'], equals('function'));
      });
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('writeFileTool', () {
    group('type', () {
      test('is a ToolDefinition', () {
        expect(writeFileTool, isA<ToolDefinition>());
      });
    });

    group('name', () {
      test('name is "write_file"', () {
        expect(writeFileTool.name, equals('write_file'));
      });
    });

    group('description', () {
      test('description is non-empty', () {
        expect(writeFileTool.description, isNotEmpty);
      });
    });

    group('parameters', () {
      test('parameters has type "object"', () {
        expect(writeFileTool.parameters['type'], equals('object'));
      });

      test('"fileName" is a property', () {
        final props =
            writeFileTool.parameters['properties'] as Map<String, dynamic>;
        expect(props, contains('fileName'));
      });

      test('"content" is a property', () {
        final props =
            writeFileTool.parameters['properties'] as Map<String, dynamic>;
        expect(props, contains('content'));
      });

      test('"fileName" property has type "string"', () {
        final props =
            writeFileTool.parameters['properties'] as Map<String, dynamic>;
        final prop = props['fileName'] as Map<String, dynamic>;
        expect(prop['type'], equals('string'));
      });

      test('"content" property has type "string"', () {
        final props =
            writeFileTool.parameters['properties'] as Map<String, dynamic>;
        final prop = props['content'] as Map<String, dynamic>;
        expect(prop['type'], equals('string'));
      });

      test('"fileName" is listed in required', () {
        final required = writeFileTool.parameters['required'] as List<dynamic>;
        expect(required, contains('fileName'));
      });

      test('"content" is listed in required', () {
        final required = writeFileTool.parameters['required'] as List<dynamic>;
        expect(required, contains('content'));
      });
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('listFilesTool', () {
    group('type', () {
      test('is a ToolDefinition', () {
        expect(listFilesTool, isA<ToolDefinition>());
      });
    });

    group('name', () {
      test('name is "list_files"', () {
        expect(listFilesTool.name, equals('list_files'));
      });
    });

    group('description', () {
      test('description is non-empty', () {
        expect(listFilesTool.description, isNotEmpty);
      });
    });

    group('parameters', () {
      test('parameters has type "object"', () {
        expect(listFilesTool.parameters['type'], equals('object'));
      });

      test('"glob" is an optional property', () {
        final props =
            listFilesTool.parameters['properties'] as Map<String, dynamic>;
        expect(props, contains('glob'));
      });

      test('"glob" property has type "string"', () {
        final props =
            listFilesTool.parameters['properties'] as Map<String, dynamic>;
        final prop = props['glob'] as Map<String, dynamic>;
        expect(prop['type'], equals('string'));
      });

      test('"glob" is NOT in required (it is optional)', () {
        final required = listFilesTool.parameters['required'] as List<dynamic>;
        expect(required, isNot(contains('glob')));
      });
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('appendFileTool', () {
    group('type', () {
      test('is a ToolDefinition', () {
        expect(appendFileTool, isA<ToolDefinition>());
      });
    });

    group('name', () {
      test('name is "append_file"', () {
        expect(appendFileTool.name, equals('append_file'));
      });
    });

    group('description', () {
      test('description is non-empty', () {
        expect(appendFileTool.description, isNotEmpty);
      });
    });

    group('parameters', () {
      test('parameters has type "object"', () {
        expect(appendFileTool.parameters['type'], equals('object'));
      });

      test('"fileName" is a property', () {
        final props =
            appendFileTool.parameters['properties'] as Map<String, dynamic>;
        expect(props, contains('fileName'));
      });

      test('"content" is a property', () {
        final props =
            appendFileTool.parameters['properties'] as Map<String, dynamic>;
        expect(props, contains('content'));
      });

      test('"fileName" is listed in required', () {
        final required = appendFileTool.parameters['required'] as List<dynamic>;
        expect(required, contains('fileName'));
      });

      test('"content" is listed in required', () {
        final required = appendFileTool.parameters['required'] as List<dynamic>;
        expect(required, contains('content'));
      });
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // 2. createHandlers — structure
  // ─────────────────────────────────────────────────────────────────────────────
  group('createHandlers', () {
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

    test('returns a Map', () {
      final handlers = createHandlers(ctx);
      expect(handlers, isA<Map<String, dynamic>>());
    });

    test('returns a Map with 4 entries', () {
      final handlers = createHandlers(ctx);
      expect(handlers, hasLength(4));
    });

    test('contains handler for "read_file"', () {
      final handlers = createHandlers(ctx);
      expect(handlers, contains('read_file'));
    });

    test('contains handler for "write_file"', () {
      final handlers = createHandlers(ctx);
      expect(handlers, contains('write_file'));
    });

    test('contains handler for "list_files"', () {
      final handlers = createHandlers(ctx);
      expect(handlers, contains('list_files'));
    });

    test('contains handler for "append_file"', () {
      final handlers = createHandlers(ctx);
      expect(handlers, contains('append_file'));
    });

    test('each value is a function', () {
      final handlers = createHandlers(ctx);
      for (final entry in handlers.entries) {
        expect(entry.value, isA<Function>(),
            reason: 'handler "${entry.key}" should be a Function');
      }
    });

    test('calling any handler returns a Future<String>', () async {
      final handlers = createHandlers(ctx);
      ctx.write('probe.txt', 'x');
      final result = await handlers['read_file']!({'fileName': 'probe.txt'});
      expect(result, isA<String>());
    });

    test('handlers from two createHandlers calls are independent', () async {
      final tmp2 = _tempContext();
      final ctx2 = tmp2.ctx;
      final dir2 = tmp2.dir;

      final h1 = createHandlers(ctx);
      final h2 = createHandlers(ctx2);

      // Write to ctx1 only.
      await h1['write_file']!(
          {'fileName': 'only_in_ctx1.txt', 'content': 'x'});

      // ctx2 should not have the file.
      final result = await h2['read_file']!({'fileName': 'only_in_ctx1.txt'});
      // Expect an error string, not the content.
      expect(result.toLowerCase(), contains('error'));

      dir2.deleteSync(recursive: true);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // 3. write_file handler
  // ─────────────────────────────────────────────────────────────────────────────
  group('write_file handler', () {
    late FileContext ctx;
    late Directory dir;
    late Map<String, Future<String> Function(Map<String, dynamic>)> handlers;

    setUp(() {
      final tmp = _tempContext();
      ctx = tmp.ctx;
      dir = tmp.dir;
      handlers = createHandlers(ctx);
    });

    tearDown(() {
      dir.deleteSync(recursive: true);
    });

    test('returns a non-empty string on success', () async {
      final result = await handlers['write_file']!(
          {'fileName': 'hello.txt', 'content': 'Hello, world!'});
      expect(result, isNotEmpty);
    });

    test('success message mentions the file name', () async {
      final result = await handlers['write_file']!(
          {'fileName': 'notes.md', 'content': 'Some notes here.'});
      expect(result, contains('notes.md'));
    });

    test('success message mentions the byte count', () async {
      const content = 'Hello world';
      final result = await handlers['write_file']!(
          {'fileName': 'size.txt', 'content': content});
      expect(result, contains('${content.length}'));
    });

    test('file is actually created in the workspace', () async {
      await handlers['write_file']!(
          {'fileName': 'created.txt', 'content': 'content here'});
      expect(ctx.exists('created.txt'), isTrue);
    });

    test('file content matches what was written', () async {
      const content = 'exact content to verify';
      await handlers['write_file']!(
          {'fileName': 'verify.txt', 'content': content});
      expect(ctx.read('verify.txt'), equals(content));
    });

    test('overwrites an existing file', () async {
      await handlers['write_file']!(
          {'fileName': 'overwrite.txt', 'content': 'original'});
      await handlers['write_file']!(
          {'fileName': 'overwrite.txt', 'content': 'updated'});
      expect(ctx.read('overwrite.txt'), equals('updated'));
    });

    test('can write empty content', () async {
      final result =
          await handlers['write_file']!({'fileName': 'empty.txt', 'content': ''});
      expect(result, isNotEmpty);
      expect(ctx.exists('empty.txt'), isTrue);
    });

    test('can write multi-line content', () async {
      const content = 'line1\nline2\nline3';
      await handlers['write_file']!(
          {'fileName': 'multi.txt', 'content': content});
      expect(ctx.read('multi.txt'), equals(content));
    });

    test('returns error string on path traversal attempt', () async {
      final result = await handlers['write_file']!(
          {'fileName': '../escaped.txt', 'content': 'bad'});
      expect(result.toLowerCase(), contains('error'));
    });

    test('path traversal does NOT write a file', () async {
      await handlers['write_file']!(
          {'fileName': '../escaped.txt', 'content': 'bad'});
      expect(File('${dir.parent.path}/escaped.txt').existsSync(), isFalse);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // 4. read_file handler
  // ─────────────────────────────────────────────────────────────────────────────
  group('read_file handler', () {
    late FileContext ctx;
    late Directory dir;
    late Map<String, Future<String> Function(Map<String, dynamic>)> handlers;

    setUp(() {
      final tmp = _tempContext();
      ctx = tmp.ctx;
      dir = tmp.dir;
      handlers = createHandlers(ctx);
    });

    tearDown(() {
      dir.deleteSync(recursive: true);
    });

    test('returns file contents when file exists', () async {
      ctx.write('greet.txt', 'Hello from file!');
      final result =
          await handlers['read_file']!({'fileName': 'greet.txt'});
      expect(result, contains('Hello from file!'));
    });

    test('returns the exact file content', () async {
      const content = 'exact content\nwith newlines\nand more';
      ctx.write('exact.txt', content);
      final result =
          await handlers['read_file']!({'fileName': 'exact.txt'});
      expect(result, equals(content));
    });

    test('returns error string when file does not exist', () async {
      final result =
          await handlers['read_file']!({'fileName': 'nonexistent.txt'});
      expect(result.toLowerCase(), contains('error'));
    });

    test('error string mentions the file name on not-found', () async {
      final result =
          await handlers['read_file']!({'fileName': 'missing_file.txt'});
      expect(result, contains('missing_file.txt'));
    });

    test('returns error string on path traversal attempt', () async {
      final result =
          await handlers['read_file']!({'fileName': '../secret.txt'});
      expect(result.toLowerCase(), contains('error'));
    });

    test('can read a file previously written via write_file handler', () async {
      const content = 'written by handler';
      await handlers['write_file']!(
          {'fileName': 'roundtrip.txt', 'content': content});
      final result =
          await handlers['read_file']!({'fileName': 'roundtrip.txt'});
      expect(result, equals(content));
    });

    test('can read empty file', () async {
      ctx.write('empty.txt', '');
      final result =
          await handlers['read_file']!({'fileName': 'empty.txt'});
      expect(result, equals(''));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // 5. list_files handler
  // ─────────────────────────────────────────────────────────────────────────────
  group('list_files handler', () {
    late FileContext ctx;
    late Directory dir;
    late Map<String, Future<String> Function(Map<String, dynamic>)> handlers;

    setUp(() {
      final tmp = _tempContext();
      ctx = tmp.ctx;
      dir = tmp.dir;
      handlers = createHandlers(ctx);
    });

    tearDown(() {
      dir.deleteSync(recursive: true);
    });

    test('returns a string result', () async {
      final result = await handlers['list_files']!({});
      expect(result, isA<String>());
    });

    test('empty workspace returns a string (no crash)', () async {
      final result = await handlers['list_files']!({});
      expect(result, isNotEmpty);
    });

    test('lists files that exist in the workspace', () async {
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
      // Both should include the file.
      expect(resultNoGlob, contains('file.txt'));
      expect(resultNullGlob, contains('file.txt'));
    });

    test('glob with no matches returns string (no crash)', () async {
      ctx.write('readme.md', 'md');
      final result = await handlers['list_files']!({'glob': '*.dart'});
      // Should return something (e.g., "No files found" or empty listing).
      expect(result, isA<String>());
    });

    test('nested files are included in listing', () async {
      ctx.write('subdir/nested.txt', 'nested content');
      final result = await handlers['list_files']!({});
      expect(result, contains('nested.txt'));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // 6. append_file handler
  // ─────────────────────────────────────────────────────────────────────────────
  group('append_file handler', () {
    late FileContext ctx;
    late Directory dir;
    late Map<String, Future<String> Function(Map<String, dynamic>)> handlers;

    setUp(() {
      final tmp = _tempContext();
      ctx = tmp.ctx;
      dir = tmp.dir;
      handlers = createHandlers(ctx);
    });

    tearDown(() {
      dir.deleteSync(recursive: true);
    });

    test('returns a non-empty string on success', () async {
      ctx.write('log.txt', 'initial');
      final result = await handlers['append_file']!(
          {'fileName': 'log.txt', 'content': ' appended'});
      expect(result, isNotEmpty);
    });

    test('success message mentions the file name', () async {
      ctx.write('log.txt', 'initial');
      final result = await handlers['append_file']!(
          {'fileName': 'log.txt', 'content': ' more'});
      expect(result, contains('log.txt'));
    });

    test('content is appended after existing content', () async {
      ctx.write('log.txt', 'line1');
      await handlers['append_file']!(
          {'fileName': 'log.txt', 'content': '\nline2'});
      expect(ctx.read('log.txt'), equals('line1\nline2'));
    });

    test('creates file if it does not exist', () async {
      await handlers['append_file']!(
          {'fileName': 'new.txt', 'content': 'first write'});
      expect(ctx.exists('new.txt'), isTrue);
      expect(ctx.read('new.txt'), equals('first write'));
    });

    test('multiple appends accumulate in order', () async {
      await handlers['append_file']!(
          {'fileName': 'accum.txt', 'content': 'A'});
      await handlers['append_file']!(
          {'fileName': 'accum.txt', 'content': 'B'});
      await handlers['append_file']!(
          {'fileName': 'accum.txt', 'content': 'C'});
      expect(ctx.read('accum.txt'), equals('ABC'));
    });

    test('success message mentions byte count', () async {
      const appended = 'exactly 12 chars';
      ctx.write('bytes.txt', '');
      final result = await handlers['append_file']!(
          {'fileName': 'bytes.txt', 'content': appended});
      expect(result, contains('${appended.length}'));
    });

    test('returns error string on path traversal attempt', () async {
      final result = await handlers['append_file']!(
          {'fileName': '../bad.txt', 'content': 'x'});
      expect(result.toLowerCase(), contains('error'));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // 7. Handler key names match tool definition names
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

    test('handler key matches readFileTool.name', () {
      final handlers = createHandlers(ctx);
      expect(handlers, contains(readFileTool.name));
    });

    test('handler key matches writeFileTool.name', () {
      final handlers = createHandlers(ctx);
      expect(handlers, contains(writeFileTool.name));
    });

    test('handler key matches listFilesTool.name', () {
      final handlers = createHandlers(ctx);
      expect(handlers, contains(listFilesTool.name));
    });

    test('handler key matches appendFileTool.name', () {
      final handlers = createHandlers(ctx);
      expect(handlers, contains(appendFileTool.name));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // 8. Tool definitions are exported from the barrel
  // ─────────────────────────────────────────────────────────────────────────────
  group('barrel export verification', () {
    test('readFileTool is accessible from package:agents_core/agents_core.dart',
        () {
      // Just accessing the identifier via the import above proves it.
      expect(readFileTool.name, equals('read_file'));
    });

    test('writeFileTool is accessible from barrel', () {
      expect(writeFileTool.name, equals('write_file'));
    });

    test('listFilesTool is accessible from barrel', () {
      expect(listFilesTool.name, equals('list_files'));
    });

    test('appendFileTool is accessible from barrel', () {
      expect(appendFileTool.name, equals('append_file'));
    });

    test('createHandlers is accessible from barrel', () {
      expect(createHandlers, isA<Function>());
    });
  });
}
