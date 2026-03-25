import 'dart:io';

import 'package:agents_core/agents_core.dart';
import 'package:test/test.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// Helper
// ═══════════════════════════════════════════════════════════════════════════════

/// Creates an isolated temporary [FileContext] for a single test.
({FileContext ctx, Directory dir}) _tempContext() {
  final dir = Directory.systemTemp.createTempSync('agents_core_fc_test_');
  final ctx = FileContext(workspacePath: dir.path);
  return (ctx: ctx, dir: dir);
}

// ═══════════════════════════════════════════════════════════════════════════════
// Tests
// ═══════════════════════════════════════════════════════════════════════════════

void main() {
  group('FileContext', () {
    // ─────────────────────────────────────────────────────────────────────────
    // Constructor
    // ─────────────────────────────────────────────────────────────────────────
    group('constructor', () {
      test('creates workspace directory when it does not exist', () {
        final path =
            '${Directory.systemTemp.path}/fc_new_${DateTime.now().millisecondsSinceEpoch}';
        addTearDown(() {
          final d = Directory(path);
          if (d.existsSync()) d.deleteSync(recursive: true);
        });

        expect(Directory(path).existsSync(), isFalse,
            reason: 'pre-condition: directory should not exist');
        FileContext(workspacePath: path);
        expect(Directory(path).existsSync(), isTrue);
      });

      test('accepts an existing directory without error', () {
        final dir = Directory.systemTemp.createTempSync('fc_existing_');
        addTearDown(() => dir.deleteSync(recursive: true));
        expect(() => FileContext(workspacePath: dir.path), returnsNormally);
      });

      test('throws ArgumentError for empty workspacePath', () {
        expect(
          () => FileContext(workspacePath: ''),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('workspacePath getter returns the configured path', () {
        final dir = Directory.systemTemp.createTempSync('fc_path_');
        addTearDown(() => dir.deleteSync(recursive: true));
        final ctx = FileContext(workspacePath: dir.path);
        expect(ctx.workspacePath, equals(dir.path));
      });
    });

    // ─────────────────────────────────────────────────────────────────────────
    // write()
    // ─────────────────────────────────────────────────────────────────────────
    group('write()', () {
      late FileContext ctx;
      late Directory dir;

      setUp(() {
        final tmp = _tempContext();
        ctx = tmp.ctx;
        dir = tmp.dir;
      });

      tearDown(() => dir.deleteSync(recursive: true));

      test('creates a file with the given content', () {
        ctx.write('hello.txt', 'world');
        expect(File('${dir.path}/hello.txt').readAsStringSync(), equals('world'));
      });

      test('file exists after write', () {
        ctx.write('exists.txt', 'data');
        expect(ctx.exists('exists.txt'), isTrue);
      });

      test('overwrites existing file content', () {
        ctx.write('file.txt', 'original');
        ctx.write('file.txt', 'updated');
        expect(ctx.read('file.txt'), equals('updated'));
      });

      test('creates parent directories automatically', () {
        ctx.write('a/b/c/file.txt', 'nested');
        expect(ctx.exists('a/b/c/file.txt'), isTrue);
      });

      test('can write empty content', () {
        ctx.write('empty.txt', '');
        expect(ctx.read('empty.txt'), equals(''));
      });

      test('can write multi-line content', () {
        const content = 'line1\nline2\nline3';
        ctx.write('multi.txt', content);
        expect(ctx.read('multi.txt'), equals(content));
      });

      test('can write unicode content', () {
        const content = 'Hello 🌍 世界';
        ctx.write('unicode.txt', content);
        expect(ctx.read('unicode.txt'), equals(content));
      });

      test('throws PathTraversalException for "../" path', () {
        expect(
          () => ctx.write('../escape.txt', 'bad'),
          throwsA(isA<PathTraversalException>()),
        );
      });

      test('path traversal does NOT create file outside workspace', () {
        try {
          ctx.write('../escape.txt', 'bad');
        } catch (_) {}
        expect(File('${dir.parent.path}/escape.txt').existsSync(), isFalse);
      });

      test('throws PathTraversalException for nested traversal "a/../../"', () {
        expect(
          () => ctx.write('a/../../escape.txt', 'bad'),
          throwsA(isA<PathTraversalException>()),
        );
      });

      test(
          'nested traversal "a/../../escape.txt" does NOT create file outside workspace',
          () {
        try {
          ctx.write('a/../../escape.txt', 'bad');
        } catch (_) {}
        // The file should not exist one level above the workspace
        expect(File('${dir.parent.path}/escape.txt').existsSync(), isFalse);
      });

      test(
          'throws PathTraversalException for deeply nested traversal "a/b/../../../"',
          () {
        expect(
          () => ctx.write('a/b/../../../escape.txt', 'bad'),
          throwsA(isA<PathTraversalException>()),
        );
      });

      test(
          'throws PathTraversalException for dot-slash with traversal "./../../"',
          () {
        expect(
          () => ctx.write('./../../escape.txt', 'bad'),
          throwsA(isA<PathTraversalException>()),
        );
      });

      test(
          'throws PathTraversalException for consecutive double-dots "../../"',
          () {
        expect(
          () => ctx.write('../../escape.txt', 'bad'),
          throwsA(isA<PathTraversalException>()),
        );
      });

      test('allows legitimate subdirectory paths without traversal', () {
        // These should NOT throw — they stay inside the workspace
        expect(() => ctx.write('a/b/c.txt', 'ok'), returnsNormally);
        expect(() => ctx.write('deep/nested/dir/file.txt', 'ok'), returnsNormally);
      });
    });

    // ─────────────────────────────────────────────────────────────────────────
    // read()
    // ─────────────────────────────────────────────────────────────────────────
    group('read()', () {
      late FileContext ctx;
      late Directory dir;

      setUp(() {
        final tmp = _tempContext();
        ctx = tmp.ctx;
        dir = tmp.dir;
      });

      tearDown(() => dir.deleteSync(recursive: true));

      test('returns file content', () {
        ctx.write('greet.txt', 'Hello!');
        expect(ctx.read('greet.txt'), equals('Hello!'));
      });

      test('reads exact multi-line content', () {
        const content = 'line1\nline2\nline3';
        ctx.write('multi.txt', content);
        expect(ctx.read('multi.txt'), equals(content));
      });

      test('reads empty file as empty string', () {
        ctx.write('empty.txt', '');
        expect(ctx.read('empty.txt'), equals(''));
      });

      test('round-trips content written by write()', () {
        const content = 'round-trip content\nwith multiple lines';
        ctx.write('roundtrip.txt', content);
        expect(ctx.read('roundtrip.txt'), equals(content));
      });

      test('throws FileNotFoundException for missing file', () {
        expect(
          () => ctx.read('nonexistent.txt'),
          throwsA(isA<FileNotFoundException>()),
        );
      });

      test('FileNotFoundException carries the missing path', () {
        try {
          ctx.read('missing.txt');
        } on FileNotFoundException catch (e) {
          expect(e.path, contains('missing.txt'));
          return;
        }
        fail('Expected FileNotFoundException');
      });

      test('throws PathTraversalException for "../" path', () {
        expect(
          () => ctx.read('../secret.txt'),
          throwsA(isA<PathTraversalException>()),
        );
      });

      test(
          'throws PathTraversalException for nested traversal "a/../../secret.txt"',
          () {
        expect(
          () => ctx.read('a/../../secret.txt'),
          throwsA(isA<PathTraversalException>()),
        );
      });

      test('can read file in subdirectory', () {
        ctx.write('sub/deep.txt', 'nested');
        expect(ctx.read('sub/deep.txt'), equals('nested'));
      });
    });

    // ─────────────────────────────────────────────────────────────────────────
    // exists()
    // ─────────────────────────────────────────────────────────────────────────
    group('exists()', () {
      late FileContext ctx;
      late Directory dir;

      setUp(() {
        final tmp = _tempContext();
        ctx = tmp.ctx;
        dir = tmp.dir;
      });

      tearDown(() => dir.deleteSync(recursive: true));

      test('returns true for a file that exists', () {
        ctx.write('present.txt', 'yes');
        expect(ctx.exists('present.txt'), isTrue);
      });

      test('returns false for a file that does not exist', () {
        expect(ctx.exists('absent.txt'), isFalse);
      });

      test('returns false after the file is deleted', () {
        ctx.write('temp.txt', 'data');
        ctx.delete('temp.txt');
        expect(ctx.exists('temp.txt'), isFalse);
      });

      test('throws PathTraversalException for "../" path', () {
        expect(
          () => ctx.exists('../etc/passwd'),
          throwsA(isA<PathTraversalException>()),
        );
      });

      test(
          'throws PathTraversalException for nested traversal "a/../../etc/passwd"',
          () {
        expect(
          () => ctx.exists('a/../../etc/passwd'),
          throwsA(isA<PathTraversalException>()),
        );
      });

      test('returns true for file in subdirectory', () {
        ctx.write('sub/file.txt', 'x');
        expect(ctx.exists('sub/file.txt'), isTrue);
      });
    });

    // ─────────────────────────────────────────────────────────────────────────
    // listFiles()
    // ─────────────────────────────────────────────────────────────────────────
    group('listFiles()', () {
      late FileContext ctx;
      late Directory dir;

      setUp(() {
        final tmp = _tempContext();
        ctx = tmp.ctx;
        dir = tmp.dir;
      });

      tearDown(() => dir.deleteSync(recursive: true));

      test('returns empty list for an empty workspace', () {
        expect(ctx.listFiles(), isEmpty);
      });

      test('lists written files', () {
        ctx.write('a.txt', 'a');
        ctx.write('b.txt', 'b');
        expect(ctx.listFiles(), containsAll(['a.txt', 'b.txt']));
      });

      test('returned paths are relative to workspace root (no leading slash)',
          () {
        ctx.write('file.txt', 'x');
        final files = ctx.listFiles();
        expect(files, contains('file.txt'));
        expect(files.every((f) => !f.startsWith('/')), isTrue);
      });

      test('excludes directories from listing', () {
        ctx.write('subdir/file.txt', 'x');
        final files = ctx.listFiles();
        expect(files, isNot(contains('subdir')));
      });

      test('returned list is sorted lexicographically', () {
        ctx.write('c.txt', 'c');
        ctx.write('a.txt', 'a');
        ctx.write('b.txt', 'b');
        final files = ctx.listFiles();
        final sorted = List<String>.from(files)..sort();
        expect(files, equals(sorted));
      });

      test('includes files in subdirectories', () {
        ctx.write('sub/nested.txt', 'nested');
        final files = ctx.listFiles();
        expect(files.any((f) => f.contains('nested.txt')), isTrue);
      });

      group('glob filtering', () {
        test('glob *.txt matches only .txt files at root', () {
          ctx.write('doc.txt', '');
          ctx.write('code.dart', '');
          final files = ctx.listFiles(glob: '*.txt');
          expect(files, contains('doc.txt'));
          expect(files, isNot(contains('code.dart')));
        });

        test('glob *.txt does NOT match nested files', () {
          ctx.write('root.txt', '');
          ctx.write('sub/nested.txt', '');
          final files = ctx.listFiles(glob: '*.txt');
          expect(files, contains('root.txt'));
          expect(files, isNot(contains('sub/nested.txt')));
        });

        test('glob **/*.dart matches files in all subdirectories', () {
          ctx.write('a.dart', '');
          ctx.write('sub/b.dart', '');
          ctx.write('sub/deep/c.dart', '');
          final files = ctx.listFiles(glob: '**/*.dart');
          expect(files, hasLength(3));
        });

        test('glob ? matches single character', () {
          ctx.write('a1.txt', '');
          ctx.write('ab.txt', '');
          ctx.write('abc.txt', '');
          final files = ctx.listFiles(glob: 'a?.txt');
          expect(files, containsAll(['a1.txt', 'ab.txt']));
          expect(files, isNot(contains('abc.txt')));
        });

        test('glob with no matches returns empty list', () {
          ctx.write('file.txt', '');
          expect(ctx.listFiles(glob: '*.dart'), isEmpty);
        });

        test('null glob returns all files', () {
          ctx.write('a.txt', 'a');
          ctx.write('b.dart', 'b');
          expect(ctx.listFiles(glob: null), hasLength(2));
        });

        test('omitting glob returns all files', () {
          ctx.write('a.txt', 'a');
          ctx.write('b.dart', 'b');
          expect(ctx.listFiles(), hasLength(2));
        });
      });
    });

    // ─────────────────────────────────────────────────────────────────────────
    // append()
    // ─────────────────────────────────────────────────────────────────────────
    group('append()', () {
      late FileContext ctx;
      late Directory dir;

      setUp(() {
        final tmp = _tempContext();
        ctx = tmp.ctx;
        dir = tmp.dir;
      });

      tearDown(() => dir.deleteSync(recursive: true));

      test('appends content after existing content', () {
        ctx.write('log.txt', 'line1');
        ctx.append('log.txt', '\nline2');
        expect(ctx.read('log.txt'), equals('line1\nline2'));
      });

      test('creates file if it does not exist', () {
        ctx.append('new.txt', 'first');
        expect(ctx.exists('new.txt'), isTrue);
        expect(ctx.read('new.txt'), equals('first'));
      });

      test('multiple appends accumulate in order', () {
        ctx.append('accum.txt', 'A');
        ctx.append('accum.txt', 'B');
        ctx.append('accum.txt', 'C');
        expect(ctx.read('accum.txt'), equals('ABC'));
      });

      test('appending empty string does not change content', () {
        ctx.write('file.txt', 'content');
        ctx.append('file.txt', '');
        expect(ctx.read('file.txt'), equals('content'));
      });

      test('throws PathTraversalException for "../" path', () {
        expect(
          () => ctx.append('../bad.txt', 'x'),
          throwsA(isA<PathTraversalException>()),
        );
      });

      test(
          'throws PathTraversalException for nested traversal "a/../../bad.txt"',
          () {
        expect(
          () => ctx.append('a/../../bad.txt', 'x'),
          throwsA(isA<PathTraversalException>()),
        );
      });

      test('nested traversal does NOT create file outside workspace', () {
        try {
          ctx.append('a/../../bad.txt', 'x');
        } catch (_) {}
        expect(File('${dir.parent.path}/bad.txt').existsSync(), isFalse);
      });

      test('creates parent directories automatically', () {
        ctx.append('sub/log.txt', 'entry');
        expect(ctx.exists('sub/log.txt'), isTrue);
      });
    });

    // ─────────────────────────────────────────────────────────────────────────
    // delete()
    // ─────────────────────────────────────────────────────────────────────────
    group('delete()', () {
      late FileContext ctx;
      late Directory dir;

      setUp(() {
        final tmp = _tempContext();
        ctx = tmp.ctx;
        dir = tmp.dir;
      });

      tearDown(() => dir.deleteSync(recursive: true));

      test('removes an existing file', () {
        ctx.write('target.txt', 'delete me');
        ctx.delete('target.txt');
        expect(ctx.exists('target.txt'), isFalse);
      });

      test('throws FileNotFoundException for non-existing file', () {
        expect(
          () => ctx.delete('nonexistent.txt'),
          throwsA(isA<FileNotFoundException>()),
        );
      });

      test('FileNotFoundException carries the path', () {
        try {
          ctx.delete('absent.txt');
        } on FileNotFoundException catch (e) {
          expect(e.path, contains('absent.txt'));
          return;
        }
        fail('Expected FileNotFoundException');
      });

      test('throws PathTraversalException for "../" path', () {
        expect(
          () => ctx.delete('../escape.txt'),
          throwsA(isA<PathTraversalException>()),
        );
      });

      test(
          'throws PathTraversalException for nested traversal "a/../../escape.txt"',
          () {
        expect(
          () => ctx.delete('a/../../escape.txt'),
          throwsA(isA<PathTraversalException>()),
        );
      });

      test('reading a deleted file throws FileNotFoundException', () {
        ctx.write('file.txt', 'data');
        ctx.delete('file.txt');
        expect(
          () => ctx.read('file.txt'),
          throwsA(isA<FileNotFoundException>()),
        );
      });

      test('can delete file in subdirectory', () {
        ctx.write('sub/file.txt', 'x');
        ctx.delete('sub/file.txt');
        expect(ctx.exists('sub/file.txt'), isFalse);
      });
    });

    // ─────────────────────────────────────────────────────────────────────────
    // Exception details
    // ─────────────────────────────────────────────────────────────────────────
    group('PathTraversalException', () {
      late FileContext ctx;
      late Directory dir;

      setUp(() {
        final tmp = _tempContext();
        ctx = tmp.ctx;
        dir = tmp.dir;
      });

      tearDown(() => dir.deleteSync(recursive: true));

      test('path field holds the offending path', () {
        try {
          ctx.write('../bad.txt', 'x');
        } on PathTraversalException catch (e) {
          expect(e.path, equals('../bad.txt'));
          return;
        }
        fail('Expected PathTraversalException');
      });

      test('toString() includes the offending path', () {
        try {
          ctx.read('../secret.txt');
        } on PathTraversalException catch (e) {
          expect(e.toString(), contains('../secret.txt'));
          return;
        }
        fail('Expected PathTraversalException');
      });

      test('implements Exception', () {
        try {
          ctx.delete('../bad.txt');
        } on PathTraversalException catch (e) {
          expect(e, isA<Exception>());
          return;
        }
        fail('Expected PathTraversalException');
      });
    });

    group('FileNotFoundException', () {
      late FileContext ctx;
      late Directory dir;

      setUp(() {
        final tmp = _tempContext();
        ctx = tmp.ctx;
        dir = tmp.dir;
      });

      tearDown(() => dir.deleteSync(recursive: true));

      test('toString() contains "FileNotFoundException"', () {
        try {
          ctx.read('gone.txt');
        } on FileNotFoundException catch (e) {
          expect(e.toString(), contains('FileNotFoundException'));
          return;
        }
        fail('Expected FileNotFoundException');
      });

      test('implements Exception', () {
        try {
          ctx.read('gone.txt');
        } on FileNotFoundException catch (e) {
          expect(e, isA<Exception>());
          return;
        }
        fail('Expected FileNotFoundException');
      });
    });

    // ─────────────────────────────────────────────────────────────────────────
    // Path traversal edge cases (cross-method security tests)
    // ─────────────────────────────────────────────────────────────────────────
    group('path traversal edge cases', () {
      late FileContext ctx;
      late Directory dir;

      setUp(() {
        final tmp = _tempContext();
        ctx = tmp.ctx;
        dir = tmp.dir;
      });

      tearDown(() => dir.deleteSync(recursive: true));

      // Traversal patterns that MUST be rejected by _resolve()
      final traversalPaths = <String, String>{
        '../escape.txt': 'simple parent escape',
        '../../escape.txt': 'double parent escape',
        'a/../../escape.txt': 'nested single-level escape',
        'a/b/../../../escape.txt': 'nested multi-level escape',
        './../../escape.txt': 'dot-slash with parent escape',
        'sub/../../../etc/passwd': 'deep nested traversal',
      };

      for (final entry in traversalPaths.entries) {
        test('write() rejects "${entry.key}" (${entry.value})', () {
          expect(
            () => ctx.write(entry.key, 'malicious'),
            throwsA(isA<PathTraversalException>()),
          );
        });
      }

      for (final entry in traversalPaths.entries) {
        test('read() rejects "${entry.key}" (${entry.value})', () {
          expect(
            () => ctx.read(entry.key),
            throwsA(isA<PathTraversalException>()),
          );
        });
      }

      for (final entry in traversalPaths.entries) {
        test('exists() rejects "${entry.key}" (${entry.value})', () {
          expect(
            () => ctx.exists(entry.key),
            throwsA(isA<PathTraversalException>()),
          );
        });
      }

      for (final entry in traversalPaths.entries) {
        test('append() rejects "${entry.key}" (${entry.value})', () {
          expect(
            () => ctx.append(entry.key, 'malicious'),
            throwsA(isA<PathTraversalException>()),
          );
        });
      }

      for (final entry in traversalPaths.entries) {
        test('delete() rejects "${entry.key}" (${entry.value})', () {
          expect(
            () => ctx.delete(entry.key),
            throwsA(isA<PathTraversalException>()),
          );
        });
      }

      // Paths that MUST be allowed (they resolve inside the workspace)
      test('allows "a/../b.txt" (resolves to b.txt inside workspace)', () {
        expect(() => ctx.write('a/../b.txt', 'ok'), returnsNormally);
      });

      test('allows "a/b/../c.txt" (resolves inside workspace)', () {
        // Create 'a/' so the path is valid
        ctx.write('a/placeholder.txt', '');
        expect(() => ctx.write('a/b/../c.txt', 'ok'), returnsNormally);
      });

      test('allows simple filename without path', () {
        expect(() => ctx.write('file.txt', 'ok'), returnsNormally);
      });

      test('allows deeply nested valid path', () {
        expect(
            () => ctx.write('a/b/c/d/e/file.txt', 'ok'), returnsNormally);
      });
    });
  });
}
