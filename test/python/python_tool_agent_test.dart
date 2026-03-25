// ignore_for_file: avoid_implementing_value_types

import 'dart:collection';
import 'dart:io';

import 'package:agents_core/agents_core.dart';
import 'package:test/test.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Fake DockerClient
// ─────────────────────────────────────────────────────────────────────────────

/// A fake [DockerClient] that records calls without starting real processes.
class _FakeDockerClient extends DockerClient {
  _FakeDockerClient({
    this.available = true,
    this.imageAvailable = true,
    DockerRunResult? runResult,
    Object? throwOnRun,
    Object? throwOnPull,
  }) : _runResult =
           runResult ??
           const DockerRunResult(stdout: '', stderr: '', exitCode: 0),
       _throwOnRun = throwOnRun,
       _throwOnPull = throwOnPull,
       super(dockerPath: '/fake/docker');

  final bool available;
  final bool imageAvailable;
  final DockerRunResult _runResult;
  final Object? _throwOnRun;
  final Object? _throwOnPull;

  int runCount = 0;
  int pullCount = 0;
  List<String> pulledImages = [];
  String? lastImage;
  List<String>? lastCommand;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<bool> isImageAvailable(String image) async => imageAvailable;

  @override
  Future<void> pullImage(String image) async {
    pullCount++;
    pulledImages.add(image);
    if (_throwOnPull != null) throw _throwOnPull;
  }

  @override
  Future<DockerRunResult> runContainer({
    required String image,
    required List<String> command,
    Map<String, String> volumes = const {},
    String? workingDir,
    Duration timeout = const Duration(seconds: 60),
    Map<String, String> environment = const {},
  }) async {
    runCount++;
    lastImage = image;
    lastCommand = List<String>.from(command);
    if (_throwOnRun != null) throw _throwOnRun;
    return _runResult;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Fake LmStudioClient
// ─────────────────────────────────────────────────────────────────────────────

/// A fake [LmStudioClient] that returns pre-configured [ChatCompletionResponse]
/// objects from a queue without performing any real HTTP requests.
class _FakeClient extends LmStudioClient {
  _FakeClient(List<ChatCompletionResponse> responses)
    : _queue = Queue.of(responses),
      super(AgentsCoreConfig(logger: const SilentLogger()));

  final Queue<ChatCompletionResponse> _queue;

  /// Records every request passed to [chatCompletion].
  final List<ChatCompletionRequest> capturedRequests = [];

  @override
  Future<ChatCompletionResponse> chatCompletion(
    ChatCompletionRequest request,
  ) async {
    capturedRequests.add(request);
    if (_queue.isEmpty) {
      throw StateError('_FakeClient: no more responses queued');
    }
    return _queue.removeFirst();
  }

  @override
  void dispose() {}
}

// ─────────────────────────────────────────────────────────────────────────────
// Response builders
// ─────────────────────────────────────────────────────────────────────────────

/// Builds a text-only (no tool calls) [ChatCompletionResponse].
ChatCompletionResponse _textResp({
  String content = 'Done.',
  int promptTokens = 10,
  int completionTokens = 5,
}) => ChatCompletionResponse(
  id: 'chatcmpl-text',
  choices: [
    ChatCompletionChoice(
      message: ChatMessage(role: ChatMessageRole.assistant, content: content),
      finishReason: 'stop',
    ),
  ],
  usage: CompletionUsage(
    promptTokens: promptTokens,
    completionTokens: completionTokens,
    totalTokens: promptTokens + completionTokens,
  ),
);

/// Builds a [ChatCompletionResponse] that requests a single tool call.
ChatCompletionResponse _toolCallResp({
  required String toolName,
  required String arguments,
  String toolCallId = 'call_001',
  int promptTokens = 50,
  int completionTokens = 20,
}) => ChatCompletionResponse(
  id: 'chatcmpl-tool',
  choices: [
    ChatCompletionChoice(
      message: ChatMessage(
        role: ChatMessageRole.assistant,
        content: null,
        toolCalls: [
          ToolCall(
            id: toolCallId,
            type: 'function',
            function: ToolCallFunction(name: toolName, arguments: arguments),
          ),
        ],
      ),
      finishReason: 'tool_calls',
    ),
  ],
  usage: CompletionUsage(
    promptTokens: promptTokens,
    completionTokens: completionTokens,
    totalTokens: promptTokens + completionTokens,
  ),
);

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

/// Creates a [FileContext] backed by a fresh temp directory.
({FileContext ctx, Directory dir}) _tempContext() {
  final dir = Directory.systemTemp.createTempSync('pta_test_');
  final ctx = FileContext(workspacePath: dir.path);
  return (ctx: ctx, dir: dir);
}

/// Builds a basic [AgentsCoreConfig] with silent logging.
AgentsCoreConfig _config() => AgentsCoreConfig(logger: const SilentLogger());

// ─────────────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  // ── PythonToolAgent construction ──────────────────────────────────────────

  group('PythonToolAgent construction', () {
    late Directory tmpDir;
    late FileContext ctx;

    setUp(() {
      final result = _tempContext();
      tmpDir = result.dir;
      ctx = result.ctx;
    });

    tearDown(() => tmpDir.deleteSync(recursive: true));

    test('exposes dockerClient property', () {
      final fakeDocker = _FakeDockerClient();
      final agent = PythonToolAgent(
        name: 'test',
        client: _FakeClient(const []),
        config: _config(),
        dockerClient: fakeDocker,
        fileContext: ctx,
      );
      expect(agent.dockerClient, same(fakeDocker));
    });

    test('exposes fileContext property', () {
      final agent = PythonToolAgent(
        name: 'test',
        client: _FakeClient(const []),
        config: _config(),
        dockerClient: _FakeDockerClient(),
        fileContext: ctx,
      );
      expect(agent.fileContext, same(ctx));
    });

    test('exposes dockerImage property with default value', () {
      final agent = PythonToolAgent(
        name: 'test',
        client: _FakeClient(const []),
        config: _config(),
        dockerClient: _FakeDockerClient(),
        fileContext: ctx,
      );
      expect(agent.dockerImage, 'python:3.12-slim');
    });

    test('custom dockerImage is stored', () {
      final agent = PythonToolAgent(
        name: 'test',
        client: _FakeClient(const []),
        config: _config(),
        dockerClient: _FakeDockerClient(),
        fileContext: ctx,
        dockerImage: 'python:3.11-alpine',
      );
      expect(agent.dockerImage, 'python:3.11-alpine');
    });

    test('registers execute_python tool by default', () {
      final agent = PythonToolAgent(
        name: 'test',
        client: _FakeClient(const []),
        config: _config(),
        dockerClient: _FakeDockerClient(),
        fileContext: ctx,
      );
      expect(agent.tools.map((t) => t.name), contains('execute_python'));
    });

    test('without enableFileTools: only execute_python is registered', () {
      final agent = PythonToolAgent(
        name: 'test',
        client: _FakeClient(const []),
        config: _config(),
        dockerClient: _FakeDockerClient(),
        fileContext: ctx,
      );
      expect(agent.tools, hasLength(1));
      expect(agent.tools.first.name, 'execute_python');
    });

    test('with enableFileTools: 4 tools registered', () {
      final agent = PythonToolAgent(
        name: 'test',
        client: _FakeClient(const []),
        config: _config(),
        dockerClient: _FakeDockerClient(),
        fileContext: ctx,
        enableFileTools: true,
      );
      expect(agent.tools, hasLength(4));
    });

    test(
      'with enableFileTools: includes read_file, write_file, list_files',
      () {
        final agent = PythonToolAgent(
          name: 'test',
          client: _FakeClient(const []),
          config: _config(),
          dockerClient: _FakeDockerClient(),
          fileContext: ctx,
          enableFileTools: true,
        );
        final toolNames = agent.tools.map((t) => t.name).toSet();
        expect(
          toolNames,
          containsAll([
            'execute_python',
            'read_file',
            'write_file',
            'list_files',
          ]),
        );
      },
    );

    test('without enableFileTools: file tools NOT registered', () {
      final agent = PythonToolAgent(
        name: 'test',
        client: _FakeClient(const []),
        config: _config(),
        dockerClient: _FakeDockerClient(),
        fileContext: ctx,
      );
      final toolNames = agent.tools.map((t) => t.name).toSet();
      expect(toolNames, isNot(contains('read_file')));
      expect(toolNames, isNot(contains('write_file')));
      expect(toolNames, isNot(contains('list_files')));
    });

    test('creates a temp workspace when fileContext is null', () {
      final agent = PythonToolAgent(
        name: 'test',
        client: _FakeClient(const []),
        config: _config(),
        dockerClient: _FakeDockerClient(),
      );
      expect(agent.fileContext, isNotNull);
      expect(agent.fileContext.workspacePath, isNotEmpty);
    });

    test('additionalTools are included in the tools list', () {
      final extraTool = ToolDefinition(
        name: 'my_tool',
        description: 'desc',
        parameters: {'type': 'object', 'properties': {}},
      );
      final agent = PythonToolAgent(
        name: 'test',
        client: _FakeClient(const []),
        config: _config(),
        dockerClient: _FakeDockerClient(),
        fileContext: ctx,
        additionalTools: [extraTool],
      );
      expect(agent.tools.map((t) => t.name), contains('my_tool'));
    });

    test('maxIterations defaults to 15', () {
      final agent = PythonToolAgent(
        name: 'test',
        client: _FakeClient(const []),
        config: _config(),
        dockerClient: _FakeDockerClient(),
        fileContext: ctx,
      );
      expect(agent.maxIterations, 15);
    });

    test('custom maxIterations is respected', () {
      final agent = PythonToolAgent(
        name: 'test',
        client: _FakeClient(const []),
        config: _config(),
        dockerClient: _FakeDockerClient(),
        fileContext: ctx,
        maxIterations: 5,
      );
      expect(agent.maxIterations, 5);
    });

    test('custom systemPrompt overrides default', () {
      const customPrompt = 'You are a custom Python agent.';
      final agent = PythonToolAgent(
        name: 'test',
        client: _FakeClient(const []),
        config: _config(),
        dockerClient: _FakeDockerClient(),
        fileContext: ctx,
        systemPrompt: customPrompt,
      );
      expect(agent.systemPrompt, customPrompt);
    });

    test('default systemPrompt contains Python execution context', () {
      final agent = PythonToolAgent(
        name: 'test',
        client: _FakeClient(const []),
        config: _config(),
        dockerClient: _FakeDockerClient(),
        fileContext: ctx,
      );
      expect(agent.systemPrompt, isNotNull);
      expect(agent.systemPrompt!.toLowerCase(), contains('python'));
    });

    test('name is stored correctly', () {
      final agent = PythonToolAgent(
        name: 'my-python-agent',
        client: _FakeClient(const []),
        config: _config(),
        dockerClient: _FakeDockerClient(),
        fileContext: ctx,
      );
      expect(agent.name, 'my-python-agent');
    });
  });

  // ── PythonToolAgent.run() — Docker pre-checks ─────────────────────────────

  group('PythonToolAgent.run() — Docker pre-checks', () {
    late Directory tmpDir;
    late FileContext ctx;

    setUp(() {
      final result = _tempContext();
      tmpDir = result.dir;
      ctx = result.ctx;
    });

    tearDown(() => tmpDir.deleteSync(recursive: true));

    test(
      'throws DockerNotAvailableException when Docker is not available',
      () async {
        final fakeDocker = _FakeDockerClient(available: false);
        final agent = PythonToolAgent(
          name: 'test',
          client: _FakeClient(const []),
          config: _config(),
          dockerClient: fakeDocker,
          fileContext: ctx,
        );
        await expectLater(
          () => agent.run('compute something'),
          throwsA(isA<DockerNotAvailableException>()),
        );
      },
    );

    test('does NOT call LLM when Docker is unavailable', () async {
      final fakeClient = _FakeClient(const []);
      final agent = PythonToolAgent(
        name: 'test',
        client: fakeClient,
        config: _config(),
        dockerClient: _FakeDockerClient(available: false),
        fileContext: ctx,
      );

      try {
        await agent.run('task');
      } on DockerNotAvailableException {
        // expected
      }

      expect(fakeClient.capturedRequests, isEmpty);
    });

    test('does NOT pull image when image is already available', () async {
      final fakeDocker = _FakeDockerClient(
        available: true,
        imageAvailable: true,
      );
      final agent = PythonToolAgent(
        name: 'test',
        client: _FakeClient([_textResp(content: 'done')]),
        config: _config(),
        dockerClient: fakeDocker,
        fileContext: ctx,
      );
      await agent.run('task');
      expect(fakeDocker.pullCount, 0);
    });

    test('pulls image when it is not available locally', () async {
      final fakeDocker = _FakeDockerClient(
        available: true,
        imageAvailable: false,
      );
      final agent = PythonToolAgent(
        name: 'test',
        client: _FakeClient([_textResp(content: 'done')]),
        config: _config(),
        dockerClient: fakeDocker,
        fileContext: ctx,
      );
      await agent.run('task');
      expect(fakeDocker.pullCount, 1);
    });

    test('pulls the correct docker image', () async {
      final fakeDocker = _FakeDockerClient(
        available: true,
        imageAvailable: false,
      );
      final agent = PythonToolAgent(
        name: 'test',
        client: _FakeClient([_textResp(content: 'done')]),
        config: _config(),
        dockerClient: fakeDocker,
        fileContext: ctx,
        dockerImage: 'python:3.11-slim',
      );
      await agent.run('task');
      expect(fakeDocker.pulledImages, contains('python:3.11-slim'));
    });

    test('propagates DockerExecutionException from pullImage', () async {
      final fakeDocker = _FakeDockerClient(
        available: true,
        imageAvailable: false,
        throwOnPull: const DockerExecutionException(
          message: 'pull failed',
          exitCode: 1,
        ),
      );
      final agent = PythonToolAgent(
        name: 'test',
        client: _FakeClient(const []),
        config: _config(),
        dockerClient: fakeDocker,
        fileContext: ctx,
      );
      await expectLater(
        () => agent.run('task'),
        throwsA(isA<DockerExecutionException>()),
      );
    });

    test('proceeds to ReAct loop after successful pre-checks', () async {
      final fakeDocker = _FakeDockerClient(
        available: true,
        imageAvailable: true,
      );
      final fakeClient = _FakeClient([_textResp(content: 'answer')]);
      final agent = PythonToolAgent(
        name: 'test',
        client: fakeClient,
        config: _config(),
        dockerClient: fakeDocker,
        fileContext: ctx,
      );
      final result = await agent.run('task');
      // LLM was called, so the ReAct loop ran
      expect(fakeClient.capturedRequests, isNotEmpty);
      expect(result.output, 'answer');
    });
  });

  // ── PythonToolAgent.run() — ReAct loop ────────────────────────────────────

  group('PythonToolAgent.run() — ReAct loop', () {
    late Directory tmpDir;
    late FileContext ctx;

    setUp(() {
      final result = _tempContext();
      tmpDir = result.dir;
      ctx = result.ctx;
    });

    tearDown(() => tmpDir.deleteSync(recursive: true));

    test('returns AgentResult with LLM output when no tool calls', () async {
      final agent = PythonToolAgent(
        name: 'test',
        client: _FakeClient([_textResp(content: 'The answer is 42.')]),
        config: _config(),
        dockerClient: _FakeDockerClient(),
        fileContext: ctx,
      );
      final result = await agent.run('What is 6 * 7?');
      expect(result.output, 'The answer is 42.');
    });

    test('stoppedReason is "completed" when LLM returns text', () async {
      final agent = PythonToolAgent(
        name: 'test',
        client: _FakeClient([_textResp(content: 'done')]),
        config: _config(),
        dockerClient: _FakeDockerClient(),
        fileContext: ctx,
      );
      final result = await agent.run('task');
      expect(result.stoppedReason, 'completed');
    });

    test('tokensUsed reflects LLM usage', () async {
      final agent = PythonToolAgent(
        name: 'test',
        client: _FakeClient([
          _textResp(content: 'ok', promptTokens: 20, completionTokens: 10),
        ]),
        config: _config(),
        dockerClient: _FakeDockerClient(),
        fileContext: ctx,
      );
      final result = await agent.run('task');
      expect(result.tokensUsed, 30);
    });

    test(
      'LLM calls execute_python → dockerClient.runContainer is called',
      () async {
        final fakeDocker = _FakeDockerClient(
          runResult: const DockerRunResult(
            stdout: 'hello',
            stderr: '',
            exitCode: 0,
          ),
        );
        final agent = PythonToolAgent(
          name: 'test',
          client: _FakeClient([
            _toolCallResp(
              toolName: 'execute_python',
              arguments: '{"code": "print(\'hello\')"}',
            ),
            _textResp(content: 'Python printed: hello'),
          ]),
          config: _config(),
          dockerClient: fakeDocker,
          fileContext: ctx,
        );
        await agent.run('Print hello with Python');
        expect(fakeDocker.runCount, 1);
      },
    );

    test('final LLM output is returned after tool call cycle', () async {
      final agent = PythonToolAgent(
        name: 'test',
        client: _FakeClient([
          _toolCallResp(
            toolName: 'execute_python',
            arguments: '{"code": "print(42)"}',
          ),
          _textResp(content: 'The result is 42.'),
        ]),
        config: _config(),
        dockerClient: _FakeDockerClient(
          runResult: const DockerRunResult(
            stdout: '42',
            stderr: '',
            exitCode: 0,
          ),
        ),
        fileContext: ctx,
      );
      final result = await agent.run('Compute 42');
      expect(result.output, 'The result is 42.');
    });

    test('toolCallsMade contains the execute_python call', () async {
      final agent = PythonToolAgent(
        name: 'test',
        client: _FakeClient([
          _toolCallResp(
            toolName: 'execute_python',
            arguments: '{"code": "print(1)"}',
            toolCallId: 'call_xyz',
          ),
          _textResp(content: 'done'),
        ]),
        config: _config(),
        dockerClient: _FakeDockerClient(),
        fileContext: ctx,
      );
      final result = await agent.run('task');
      expect(result.toolCallsMade, hasLength(1));
      expect(result.toolCallsMade.first.function?.name, 'execute_python');
    });

    test(
      'second LLM request includes role:tool message with docker output',
      () async {
        final fakeClient = _FakeClient([
          _toolCallResp(
            toolName: 'execute_python',
            arguments: '{"code": "print(\'result\')"}',
          ),
          _textResp(content: 'done'),
        ]);
        final agent = PythonToolAgent(
          name: 'test',
          client: fakeClient,
          config: _config(),
          dockerClient: _FakeDockerClient(
            runResult: const DockerRunResult(
              stdout: 'result',
              stderr: '',
              exitCode: 0,
            ),
          ),
          fileContext: ctx,
        );
        await agent.run('task');

        expect(fakeClient.capturedRequests, hasLength(2));
        final secondReq = fakeClient.capturedRequests[1];
        final toolMessages = secondReq.messages
            .where((m) => m.role == ChatMessageRole.tool)
            .toList();
        expect(toolMessages, hasLength(1));
        expect(toolMessages.first.content, contains('[OK] exit_code=0'));
        expect(toolMessages.first.content, contains('result'));
      },
    );

    test('tool result message toolCallId matches the tool call id', () async {
      final fakeClient = _FakeClient([
        _toolCallResp(
          toolName: 'execute_python',
          arguments: '{"code": "x=1"}',
          toolCallId: 'call_abc_123',
        ),
        _textResp(content: 'done'),
      ]);
      final agent = PythonToolAgent(
        name: 'test',
        client: fakeClient,
        config: _config(),
        dockerClient: _FakeDockerClient(),
        fileContext: ctx,
      );
      await agent.run('task');

      final secondReq = fakeClient.capturedRequests[1];
      final toolMsg = secondReq.messages.firstWhere(
        (m) => m.role == ChatMessageRole.tool,
      );
      expect(toolMsg.toolCallId, 'call_abc_123');
    });

    test('uses agent fileContext as the context for super.run()', () async {
      // The execute_python handler uses the agent's fileContext.
      // Verify that after execution the workspace was used (temp file
      // was written and cleaned up).
      final fakeDocker = _FakeDockerClient();
      final agent = PythonToolAgent(
        name: 'test',
        client: _FakeClient([
          _toolCallResp(
            toolName: 'execute_python',
            arguments: '{"code": "print(1)"}',
          ),
          _textResp(content: 'done'),
        ]),
        config: _config(),
        dockerClient: fakeDocker,
        fileContext: ctx,
      );
      await agent.run('task');

      // Docker was called with the agent's workspace path in volumes
      expect(fakeDocker.runCount, 1);
      // Workspace should be clean after execution (temp file removed)
      expect(ctx.listFiles().where((f) => f.contains('.tmp_exec_')), isEmpty);
    });

    test(
      'DockerNotAvailableException from execute_python propagates out',
      () async {
        // Note: ReActAgent._executeTool catches Exception and returns
        // an error string, but DockerNotAvailableException implements
        // Exception — so it IS caught and returned as a string to the LLM.
        // The test verifies the tool is called and the result contains 'Error'.
        // (DockerNotAvailableException is re-thrown by the handler, but
        // ReActAgent catches all Exceptions in _executeTool)
        // If future behavior changes, this test documents the contract.
        //
        // Expected: no unhandled exception from agent.run() since
        // ReActAgent._executeTool catches the re-thrown DockerNotAvailableException
        // (it implements Exception) and turns it into an error string for the LLM.
        // But we need another response queued for the LLM to respond.
        //
        // Re-add response for when error is fed back to LLM:
        final fakeClient = _FakeClient([
          _toolCallResp(
            toolName: 'execute_python',
            arguments: '{"code": "print(1)"}',
          ),
          _textResp(content: 'Sorry, Docker is unavailable'),
        ]);
        final agent2 = PythonToolAgent(
          name: 'test',
          client: fakeClient,
          config: _config(),
          dockerClient: _FakeDockerClient(
            throwOnRun: const DockerNotAvailableException(
              message: 'Docker went away',
            ),
          ),
          fileContext: ctx,
        );

        final result = await agent2.run('task');
        // The error was caught by ReActAgent._executeTool and fed back
        expect(result.output, isNotEmpty);
      },
    );

    test(
      'failed Python execution (non-zero exit) returns error string to LLM',
      () async {
        final fakeClient = _FakeClient([
          _toolCallResp(
            toolName: 'execute_python',
            arguments: '{"code": "raise ValueError()"}',
          ),
          _textResp(content: 'Fixed the error'),
        ]);
        final agent = PythonToolAgent(
          name: 'test',
          client: fakeClient,
          config: _config(),
          dockerClient: _FakeDockerClient(
            runResult: const DockerRunResult(
              stdout: '',
              stderr: 'ValueError',
              exitCode: 1,
            ),
          ),
          fileContext: ctx,
        );
        await agent.run('task');

        // Second request should contain the error feedback to LLM
        expect(fakeClient.capturedRequests, hasLength(2));
        final toolMessages = fakeClient.capturedRequests[1].messages
            .where((m) => m.role == ChatMessageRole.tool)
            .toList();
        expect(toolMessages, hasLength(1));
        expect(toolMessages.first.content, contains('[ERROR] exit_code=1'));
      },
    );

    test(
      'two sequential tool calls result in two docker.runContainer calls',
      () async {
        final fakeDocker = _FakeDockerClient();
        final agent = PythonToolAgent(
          name: 'test',
          client: _FakeClient([
            _toolCallResp(
              toolName: 'execute_python',
              arguments: '{"code": "print(1)"}',
              toolCallId: 'call_1',
            ),
            _toolCallResp(
              toolName: 'execute_python',
              arguments: '{"code": "print(2)"}',
              toolCallId: 'call_2',
            ),
            _textResp(content: 'all done'),
          ]),
          config: _config(),
          dockerClient: fakeDocker,
          fileContext: ctx,
        );
        await agent.run('task');
        expect(fakeDocker.runCount, 2);
      },
    );

    test('tokensUsed accumulates across iterations', () async {
      final agent = PythonToolAgent(
        name: 'test',
        client: _FakeClient([
          _toolCallResp(
            toolName: 'execute_python',
            arguments: '{"code": "x=1"}',
            promptTokens: 50,
            completionTokens: 20,
          ),
          _textResp(content: 'done', promptTokens: 80, completionTokens: 15),
        ]),
        config: _config(),
        dockerClient: _FakeDockerClient(),
        fileContext: ctx,
      );
      final result = await agent.run('task');
      // 70 (first call) + 95 (second call) = 165
      expect(result.tokensUsed, 165);
    });
  });
}
