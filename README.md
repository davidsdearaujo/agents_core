# agents_core

A Dart library for orchestrating multi-agent AI workflows with LM Studio
integration. Define agents, manage multi-turn conversations, execute Python in
Docker, and coordinate multi-step pipelines — all with zero runtime dependencies.

## Prerequisites

- **Dart SDK** >= 3.10.9
- **[LM Studio](https://lmstudio.ai/)** running locally (default `http://localhost:1234`)
  with at least one model loaded
- **Docker** (optional) — required only for `PythonToolAgent` and sandboxed code execution

## Installation

Add `agents_core` to your `pubspec.yaml`:

```sh
dart pub add agents_core
dart pub get
```

## Quick Start

### One-shot question

The simplest way to get a response from an LLM:

```dart
import 'package:agents_core/agents_core.dart';

Future<void> main() async {
  final answer = await ask(
    'What is the capital of France?',
    config: AgentsCoreConfig(),
    model: 'llama-3-8b',
    systemPrompt: 'You are a helpful geography assistant.',
  );
  print(answer); // Paris is the capital of France.
}
```

### Chat completion with LmStudioClient

For full control over requests and responses:

```dart
import 'package:agents_core/agents_core.dart';

Future<void> main() async {
  final config = AgentsCoreConfig();
  final client = LmStudioClient(config);

  try {
    final response = await client.chatCompletion(
      ChatCompletionRequest(
        model: 'llama-3-8b',
        messages: [
          ChatMessage(role: ChatMessageRole.system, content: 'Be concise.'),
          ChatMessage(role: ChatMessageRole.user, content: 'Explain Dart isolates.'),
        ],
        temperature: 0.7,
      ),
    );

    print(response.choices.first.message.content);
    print('Tokens used: ${response.usage.totalTokens}');
  } finally {
    client.dispose();
  }
}
```

### Multi-turn conversation

Maintain chat history automatically across multiple exchanges:

```dart
import 'package:agents_core/agents_core.dart';

Future<void> main() async {
  final conv = Conversation(
    config: AgentsCoreConfig(),
    model: 'llama-3-8b',
    systemPrompt: 'You are a helpful tutor.',
  );

  final reply1 = await conv.send('What is recursion?');
  print(reply1);

  final reply2 = await conv.send('Give me a Dart example.');
  print(reply2);

  print('History: ${conv.history.length} messages');
}
```

### File context operations

Read and write files in a sandboxed workspace:

```dart
import 'package:agents_core/agents_core.dart';

void main() {
  final ctx = FileContext(workspacePath: '/tmp/my_workspace');

  ctx.write('notes.txt', 'Hello, world!');
  print(ctx.read('notes.txt')); // Hello, world!

  ctx.append('notes.txt', '\nSecond line.');
  print(ctx.listFiles()); // [notes.txt]
}
```

### Agent with tool calling (ReActAgent)

Run a multi-turn agent that can call tools:

```dart
import 'package:agents_core/agents_core.dart';

Future<void> main() async {
  final config = AgentsCoreConfig();
  final client = LmStudioClient(config);
  final ctx = FileContext(workspacePath: '/tmp/agent_workspace');
  final handlers = createHandlers(ctx);

  final agent = ReActAgent(
    name: 'researcher',
    client: client,
    config: config,
    model: 'llama-3-8b',
    systemPrompt: 'You are a research assistant with file access.',
    tools: [readFileTool, writeFileTool, listFilesTool],
    toolHandlers: handlers,
    maxIterations: 5,
  );

  final result = await agent.run(
    'List all files in the workspace and summarise their contents.',
    context: ctx,
  );

  print(result.output);
  print('Tool calls made: ${result.toolCallsMade.length}');
  client.dispose();
}
```

### Multi-agent pipeline (Orchestrator)

Chain agents together in a sequential pipeline:

```dart
import 'package:agents_core/agents_core.dart';

Future<void> main() async {
  final config = AgentsCoreConfig();
  final client = LmStudioClient(config);
  final ctx = FileContext(workspacePath: '/tmp/pipeline');

  final researcher = SimpleAgent(
    name: 'researcher', client: client, config: config,
    systemPrompt: 'Research and write findings to a file.',
  );
  final writer = SimpleAgent(
    name: 'writer', client: client, config: config,
    systemPrompt: 'Write a polished summary.',
  );

  final orchestrator = Orchestrator(
    context: ctx,
    steps: [
      AgentStep(agent: researcher, taskPrompt: 'Research quantum computing'),
      AgentStep(agent: writer, taskPrompt: 'Summarise the research'),
    ],
    onError: OrchestratorErrorPolicy.continueOnError,
  );

  final result = await orchestrator.run();
  print('Steps completed: ${result.stepResults.length}');
  print('Duration: ${result.duration}');
  client.dispose();
}
```

## Module Overview

| Module | Key Classes | Description |
|---|---|---|
| **Agent** | `Agent`, `SimpleAgent`, `ReActAgent`, `AgentResult` | Define and run AI agents with tool calling |
| **Client** | `LmStudioClient`, `LmStudioHttpClient`, `SseParser` | HTTP client for LM Studio's OpenAI-compatible API |
| **Models** | `ChatMessage`, `ChatCompletionRequest`, `ChatCompletionResponse`, `ChatCompletionChunk`, `ToolDefinition`, `ToolCall`, `LmModel` | Request/response data structures |
| **Config** | `AgentsCoreConfig`, `Logger`, `StderrLogger`, `SilentLogger` | Configuration and logging |
| **File Context** | `FileContext`, `readFileTool`, `writeFileTool`, `listFilesTool`, `createHandlers` | Sandboxed file operations with tool definitions |
| **Orchestrator** | `Orchestrator`, `AgentStep`, `OrchestratorResult`, `OrchestratorErrorPolicy` | Sequential multi-agent pipelines |
| **Docker** | `DockerClient`, `DockerRunResult` | Container management for sandboxed execution |
| **Python** | `PythonToolAgent`, `PythonExecutionTool` | Python code execution in Docker |
| **Quick** | `ask`, `askStream`, `Conversation` | Convenience functions for common patterns |
| **Exceptions** | `AgentsCoreException`, `LmStudioApiException`, `LmStudioConnectionException`, `FileNotFoundException`, `PathTraversalException` | Structured error hierarchy |

## Examples

See the [`example/`](example/) directory for runnable examples:

- [`quick_ask.dart`](example/quick_ask.dart) — One-shot `ask()` and `askStream()` usage
- [`conversation.dart`](example/conversation.dart) — Multi-turn conversation with history
- [`simple_agent.dart`](example/simple_agent.dart) — SimpleAgent with FileContext
- [`python_agent.dart`](example/python_agent.dart) — PythonToolAgent with Docker execution
- [`multi_agent.dart`](example/multi_agent.dart) — Multi-agent orchestration pipeline

## Configuration

`AgentsCoreConfig` accepts these parameters:

| Parameter | Default | Description |
|---|---|---|
| `lmStudioBaseUrl` | `http://localhost:1234` | LM Studio server URL |
| `defaultModel` | `lmstudio-community/default` | Default model identifier |
| `requestTimeout` | `60 seconds` | HTTP connection timeout |
| `dockerImage` | `python:3.12-slim` | Docker image for Python execution |
| `workspacePath` | `/tmp/agents_workspace` | Default workspace path |
| `logger` | `StderrLogger(level: LogLevel.info)` | Logger instance |

You can also create configuration from environment variables:

```dart
final config = AgentsCoreConfig.fromEnvironment();
```

Supported environment variables: `LM_STUDIO_BASE_URL`, `AGENTS_DEFAULT_MODEL`,
`AGENTS_DOCKER_IMAGE`, `AGENTS_WORKSPACE_PATH`, `AGENTS_REQUEST_TIMEOUT_SECONDS`.

## License

MIT — see [LICENSE](LICENSE) for details.

Copyright 2026 David Araujo
