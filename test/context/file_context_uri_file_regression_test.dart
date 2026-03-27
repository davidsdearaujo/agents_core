import 'dart:io';

import 'package:agents_core/agents_core.dart';
import 'package:test/test.dart';

// =============================================================================
// FileContext — Uri.file regression tests
//
// Regression tests for the bug fixed in v0.2.0 where `FileContext._resolve`
// used `Uri.parse()` to normalize file paths. `Uri.parse()` percent-encodes
// spaces and special characters (e.g. "my notes.txt" → "my%20notes.txt"),
// causing `File` to create files with literal `%20` in the name instead of
// actual spaces.
//
// The fix changed `_resolve` to use `Uri.file()`, which correctly round-trips
// file-system paths including spaces and other characters without introducing
// percent-encoding artifacts.
//
// These tests ensure:
// 1. Filenames with spaces work correctly at all nesting levels
// 2. Directory paths with spaces work correctly
// 3. Special characters that Uri.parse would mangle are handled properly
// 4. Files with spaces are found by listFiles and glob
// 5. No percent-encoded artifacts appear in the file system
// =============================================================================

// -----------------------------------------------------------------------------
// Helpers
// -----------------------------------------------------------------------------

/// Creates an isolated temporary [FileContext] for a single test.
({FileContext ctx, Directory dir}) _tempContext() {
  final dir = Directory.systemTemp.createTempSync('agents_core_uri_reg_');
  final ctx = FileContext(workspacePath: dir.path);
  return (ctx: ctx, dir: dir);
}

// =============================================================================
// Tests
// =============================================================================

void main() {
  // ---------------------------------------------------------------------------
  // Group 1: Filenames with spaces — the core regression scenario
  // ---------------------------------------------------------------------------
  group('FileContext Uri.file regression — filenames with spaces', () {
    late FileContext ctx;
    late Directory dir;

    setUp(() {
      final tmp = _tempContext();
      ctx = tmp.ctx;
      dir = tmp.dir;
    });

    tearDown(() => dir.deleteSync(recursive: true));

    test('write and read file with single space in name', () {
      ctx.write('my notes.txt', 'hello');
      expect(ctx.read('my notes.txt'), equals('hello'));
    });

    test('write and read file with multiple spaces in name', () {
      ctx.write('my  long  name.txt', 'content');
      expect(ctx.read('my  long  name.txt'), equals('content'));
    });

    test('file with spaces physically exists at correct path (no %20)', () {
      ctx.write('research outline.md', '# Research');
      final file = File('${dir.path}/research outline.md');
      expect(file.existsSync(), isTrue,
          reason: 'File should exist with real spaces, not percent-encoded');
    });

    test('no percent-encoded file is created for spaced filename', () {
      ctx.write('my notes.txt', 'data');
      final percentFile = File('${dir.path}/my%20notes.txt');
      expect(percentFile.existsSync(), isFalse,
          reason: 'No file with %20 should be created — this was the bug');
    });

    test('exists() returns true for file with spaces', () {
      ctx.write('project plan.txt', 'plan');
      expect(ctx.exists('project plan.txt'), isTrue);
    });

    test('delete() removes file with spaces', () {
      ctx.write('temp file.txt', 'temp');
      ctx.delete('temp file.txt');
      expect(ctx.exists('temp file.txt'), isFalse);
    });

    test('append() works on file with spaces', () {
      ctx.write('log file.txt', 'line1');
      ctx.append('log file.txt', '\nline2');
      expect(ctx.read('log file.txt'), equals('line1\nline2'));
    });

    test('listFiles() returns file with spaces in name', () {
      ctx.write('spaced file.txt', 'data');
      final files = ctx.listFiles();
      expect(files, contains('spaced file.txt'));
    });

    test('listFiles() does NOT return percent-encoded filename', () {
      ctx.write('my notes.txt', 'data');
      final files = ctx.listFiles();
      expect(files, isNot(contains('my%20notes.txt')),
          reason: 'Listed filename should have real spaces, not %20');
      expect(files, contains('my notes.txt'));
    });

    test('glob matches file with spaces', () {
      ctx.write('report summary.txt', 'data');
      ctx.write('code.dart', 'void main() {}');
      final txtFiles = ctx.listFiles(glob: '*.txt');
      expect(txtFiles, contains('report summary.txt'));
      expect(txtFiles, isNot(contains('code.dart')));
    });
  });

  // ---------------------------------------------------------------------------
  // Group 2: Directory paths with spaces
  // ---------------------------------------------------------------------------
  group('FileContext Uri.file regression — directory paths with spaces', () {
    late FileContext ctx;
    late Directory dir;

    setUp(() {
      final tmp = _tempContext();
      ctx = tmp.ctx;
      dir = tmp.dir;
    });

    tearDown(() => dir.deleteSync(recursive: true));

    test('write file in directory with spaces', () {
      ctx.write('my docs/readme.txt', 'hello');
      expect(ctx.read('my docs/readme.txt'), equals('hello'));
    });

    test('directory with spaces physically exists (no %20)', () {
      ctx.write('project notes/file.txt', 'data');
      final directory = Directory('${dir.path}/project notes');
      expect(directory.existsSync(), isTrue,
          reason: 'Directory should have real spaces');
    });

    test('no percent-encoded directory is created', () {
      ctx.write('my folder/file.txt', 'data');
      final percentDir = Directory('${dir.path}/my%20folder');
      expect(percentDir.existsSync(), isFalse,
          reason: 'No directory with %20 should be created');
    });

    test('deeply nested directories with spaces at all levels', () {
      ctx.write('level one/level two/level three/deep file.txt', 'deep');
      expect(
        ctx.read('level one/level two/level three/deep file.txt'),
        equals('deep'),
      );
    });

    test('deeply nested directory path physically exists (no %20 anywhere)',
        () {
      ctx.write('parent dir/child dir/file.txt', 'data');
      final parentDir = Directory('${dir.path}/parent dir');
      final childDir = Directory('${dir.path}/parent dir/child dir');
      expect(parentDir.existsSync(), isTrue);
      expect(childDir.existsSync(), isTrue);

      // Verify no percent-encoded versions exist
      expect(Directory('${dir.path}/parent%20dir').existsSync(), isFalse);
    });

    test('mixed: spaces in both directory and filename', () {
      ctx.write('my project/research notes.md', '# Notes');
      expect(ctx.read('my project/research notes.md'), equals('# Notes'));
      final file = File('${dir.path}/my project/research notes.md');
      expect(file.existsSync(), isTrue);
    });

    test('listFiles includes files from directories with spaces', () {
      ctx.write('spaced dir/file.txt', 'data');
      final files = ctx.listFiles();
      expect(files.any((f) => f.contains('spaced dir')), isTrue);
      expect(files.any((f) => f.contains('spaced%20dir')), isFalse);
    });

    test('glob ** matches files in directories with spaces', () {
      ctx.write('my docs/code.dart', 'void main() {}');
      ctx.write('my docs/notes.txt', 'notes');
      ctx.write('flat.dart', 'x');
      final dartFiles = ctx.listFiles(glob: '**/*.dart');
      expect(dartFiles.any((f) => f.contains('my docs')), isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // Group 3: Special characters that Uri.parse would percent-encode
  // ---------------------------------------------------------------------------
  group(
      'FileContext Uri.file regression — special characters '
      '(hash, plus, percent)', () {
    late FileContext ctx;
    late Directory dir;

    setUp(() {
      final tmp = _tempContext();
      ctx = tmp.ctx;
      dir = tmp.dir;
    });

    tearDown(() => dir.deleteSync(recursive: true));

    test('filename with parentheses', () {
      ctx.write('file (1).txt', 'copy');
      expect(ctx.read('file (1).txt'), equals('copy'));
      expect(ctx.exists('file (1).txt'), isTrue);
    });

    test('filename with square brackets', () {
      ctx.write('data[0].json', '{"key":"value"}');
      expect(ctx.read('data[0].json'), equals('{"key":"value"}'));
    });

    test('filename with equals sign', () {
      ctx.write('key=value.conf', 'config');
      expect(ctx.read('key=value.conf'), equals('config'));
    });

    test('filename with ampersand', () {
      ctx.write('a&b.txt', 'ampersand');
      expect(ctx.read('a&b.txt'), equals('ampersand'));
    });

    test('filename with at sign', () {
      ctx.write('user@domain.txt', 'email');
      expect(ctx.read('user@domain.txt'), equals('email'));
    });

    test('filename with exclamation mark', () {
      ctx.write('important!.txt', 'urgent');
      expect(ctx.read('important!.txt'), equals('urgent'));
    });

    test('filename with comma', () {
      ctx.write('a,b,c.csv', '1,2,3');
      expect(ctx.read('a,b,c.csv'), equals('1,2,3'));
    });

    test('filename with semicolons', () {
      ctx.write('key;value.txt', 'data');
      expect(ctx.read('key;value.txt'), equals('data'));
    });

    test('filename with single quotes', () {
      ctx.write("it's.txt", 'possessive');
      expect(ctx.read("it's.txt"), equals('possessive'));
    });

    test('filename combining spaces and special characters', () {
      ctx.write('my file (copy 1).txt', 'combined');
      expect(ctx.read('my file (copy 1).txt'), equals('combined'));
      final file = File('${dir.path}/my file (copy 1).txt');
      expect(file.existsSync(), isTrue);
    });

    test('directory with parentheses and spaces', () {
      ctx.write('docs (v2)/notes.txt', 'v2 notes');
      expect(ctx.read('docs (v2)/notes.txt'), equals('v2 notes'));
    });
  });

  // ---------------------------------------------------------------------------
  // Group 4: Path traversal security still works with spaces
  // ---------------------------------------------------------------------------
  group('FileContext Uri.file regression — security with spaces', () {
    late FileContext ctx;
    late Directory dir;

    setUp(() {
      final tmp = _tempContext();
      ctx = tmp.ctx;
      dir = tmp.dir;
    });

    tearDown(() => dir.deleteSync(recursive: true));

    test('traversal with spaces in path component is still rejected', () {
      expect(
        () => ctx.write('my docs/../../escape.txt', 'bad'),
        throwsA(isA<PathTraversalException>()),
      );
    });

    test('traversal with spaces in filename component is still rejected', () {
      expect(
        () => ctx.read('../secret file.txt'),
        throwsA(isA<PathTraversalException>()),
      );
    });

    test('legitimate path with spaces + ".." that stays in workspace is OK',
        () {
      // 'a b/../c d.txt' resolves to 'c d.txt' inside workspace — allowed
      expect(() => ctx.write('a b/../c d.txt', 'ok'), returnsNormally);
      expect(ctx.exists('c d.txt'), isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // Group 5: Workspace path itself containing spaces
  // ---------------------------------------------------------------------------
  group('FileContext Uri.file regression — workspace path with spaces', () {
    test('workspace path with spaces works for all operations', () {
      final spacedDir = Directory.systemTemp
          .createTempSync('agents core workspace ');
      addTearDown(() => spacedDir.deleteSync(recursive: true));

      final ctx = FileContext(workspacePath: spacedDir.path);

      // write
      ctx.write('notes.txt', 'hello from spaced workspace');
      expect(ctx.read('notes.txt'), equals('hello from spaced workspace'));
      expect(ctx.exists('notes.txt'), isTrue);

      // append
      ctx.append('notes.txt', '\nmore');
      expect(ctx.read('notes.txt'), equals('hello from spaced workspace\nmore'));

      // listFiles
      expect(ctx.listFiles(), contains('notes.txt'));

      // delete
      ctx.delete('notes.txt');
      expect(ctx.exists('notes.txt'), isFalse);
    });

    test('workspace path with spaces + file with spaces', () {
      final spacedDir = Directory.systemTemp
          .createTempSync('agents spaced workspace ');
      addTearDown(() => spacedDir.deleteSync(recursive: true));

      final ctx = FileContext(workspacePath: spacedDir.path);

      ctx.write('my notes.txt', 'double spaces');
      expect(ctx.read('my notes.txt'), equals('double spaces'));

      // Verify physical file has real spaces
      final file = File('${spacedDir.path}/my notes.txt');
      expect(file.existsSync(), isTrue);
    });

    test('workspace path with spaces still blocks traversal', () {
      final spacedDir = Directory.systemTemp
          .createTempSync('agents secure workspace ');
      addTearDown(() => spacedDir.deleteSync(recursive: true));

      final ctx = FileContext(workspacePath: spacedDir.path);

      expect(
        () => ctx.write('../escape.txt', 'bad'),
        throwsA(isA<PathTraversalException>()),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Group 6: Round-trip integrity (write + read + listFiles consistency)
  // ---------------------------------------------------------------------------
  group('FileContext Uri.file regression — round-trip integrity', () {
    late FileContext ctx;
    late Directory dir;

    setUp(() {
      final tmp = _tempContext();
      ctx = tmp.ctx;
      dir = tmp.dir;
    });

    tearDown(() => dir.deleteSync(recursive: true));

    test('multiple files with spaces round-trip correctly', () {
      final files = {
        'meeting notes.txt': 'Meeting notes content',
        'project plan.md': '# Project Plan',
        'data analysis.csv': 'col1,col2,col3',
        'user guide (v2).pdf': 'pdf content',
        'config settings.yaml': 'key: value',
      };

      for (final entry in files.entries) {
        ctx.write(entry.key, entry.value);
      }

      for (final entry in files.entries) {
        expect(ctx.read(entry.key), equals(entry.value),
            reason: '"${entry.key}" should round-trip correctly');
        expect(ctx.exists(entry.key), isTrue,
            reason: '"${entry.key}" should exist');
      }

      final listed = ctx.listFiles();
      for (final name in files.keys) {
        expect(listed, contains(name),
            reason: '"$name" should appear in listFiles()');
      }
    });

    test('overwrite file with spaces preserves the correct name', () {
      ctx.write('document draft.txt', 'version 1');
      ctx.write('document draft.txt', 'version 2');
      expect(ctx.read('document draft.txt'), equals('version 2'));

      // Only one file should exist
      final listed = ctx.listFiles();
      final matches =
          listed.where((f) => f.contains('document')).toList();
      expect(matches, hasLength(1));
      expect(matches.first, equals('document draft.txt'));
    });

    test('unicode filename with spaces works correctly', () {
      ctx.write('relatório final.txt', 'Portuguese report');
      expect(ctx.read('relatório final.txt'), equals('Portuguese report'));
      expect(ctx.exists('relatório final.txt'), isTrue);
    });
  });
}
