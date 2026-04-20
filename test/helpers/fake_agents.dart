import 'package:agents_core/agents_core.dart';

import 'mock_llm_client.dart';

/// Queue-based [Agent] fake that supports multiple sequential calls.
///
/// Tracks every captured task and context, making it suitable for both
/// single-step agents and multi-iteration producer/reviewer loops.
class FakeAgent extends Agent {
  FakeAgent({
    super.name = 'fake',
    List<AgentResult>? results,
    List<Object>? errors,
  }) : _results = results ?? const [],
       _errors = errors ?? const [],
       super(
         client: MockLlmClient(),
         config: AgentsCoreConfig(logger: const SilentLogger()),
       );

  /// Convenience: always return one fixed result regardless of call count.
  FakeAgent.single({
    String name = 'fake',
    AgentResult result = const AgentResult(output: 'fake output'),
  }) : this(name: name, results: [result]);

  /// Convenience: always throw a fixed error on the first call.
  FakeAgent.throwing({String name = 'fake', required Object error})
    : this(name: name, errors: [error]);

  final List<AgentResult> _results;
  final List<Object> _errors;

  final List<String> capturedTasks = [];
  final List<FileContext?> capturedContexts = [];
  int callCount = 0;

  /// The task from the most recent [run] call, or `null` if never called.
  ///
  /// Convenience accessor for single-call tests that need to check the
  /// last captured value rather than indexing into [capturedTasks].
  String? get capturedTask =>
      capturedTasks.isEmpty ? null : capturedTasks.last;

  /// The [FileContext] from the most recent [run] call, or `null`.
  ///
  /// Convenience accessor for single-call tests that need to check the
  /// last captured value rather than indexing into [capturedContexts].
  FileContext? get capturedContext =>
      capturedContexts.isEmpty ? null : capturedContexts.last;

  @override
  Future<AgentResult> run(String task, {FileContext? context}) async {
    final index = callCount;
    callCount++;
    capturedTasks.add(task);
    capturedContexts.add(context);

    if (_errors.isNotEmpty && index < _errors.length) {
      throw _errors[index];
    }

    if (_results.isNotEmpty) {
      return _results[index % _results.length];
    }
    return const AgentResult(output: 'fake output');
  }
}

/// A [FakeAgent] variant that writes a file to the [FileContext] when it runs.
///
/// Used to simulate step 1 agents that produce artefacts consumed by later steps.
class WritingFakeAgent extends Agent {
  WritingFakeAgent({
    super.name = 'writing-fake',
    required this.fileName,
    required this.fileContent,
    AgentResult? result,
  }) : _result = result ?? AgentResult(output: fileContent),
       super(
         client: MockLlmClient(),
         config: AgentsCoreConfig(logger: const SilentLogger()),
       );

  final String fileName;
  final String fileContent;
  final AgentResult _result;

  String? capturedTask;
  FileContext? capturedContext;
  int callCount = 0;

  @override
  Future<AgentResult> run(String task, {FileContext? context}) async {
    callCount++;
    capturedTask = task;
    capturedContext = context;
    // Write the artefact into the shared workspace so later steps can read it.
    context?.write(fileName, fileContent);
    return _result;
  }
}
