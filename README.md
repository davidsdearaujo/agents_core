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

Chain agents together in a sequential pipeline. Steps can be single-agent
(`AgentStep`) or produce-review loops (`AgentLoopStep`):

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
  final reviewer = SimpleAgent(
    name: 'reviewer', client: client, config: config,
    systemPrompt: 'Review the summary. Reply with APPROVED if acceptable.',
  );

  final orchestrator = Orchestrator(
    context: ctx,
    steps: [
      // Single-agent step
      AgentStep(agent: researcher, taskPrompt: 'Research quantum computing'),
      // Produce-review loop step
      AgentLoopStep(
        producer: writer,
        reviewer: reviewer,
        isAccepted: (result, _) => result.output.contains('APPROVED'),
        taskPrompt: 'Write and refine a summary of the research',
        maxIterations: 3,
      ),
    ],
    onError: OrchestratorErrorPolicy.continueOnError,
  );

  final result = await orchestrator.run();

  for (final stepResult in result.stepResults) {
    print('Output: ${stepResult.output}');
    print('Tokens: ${stepResult.tokensUsed}');

    if (stepResult is AgentLoopStepResult) {
      print('Loop accepted: ${stepResult.accepted}');
      print('Iterations: ${stepResult.iterationCount}');
    }
  }

  print('Duration: ${result.duration}');
  client.dispose();
}
```

### Produce-review loop (AgentLoop)

Run iterative refinement between a producer and a reviewer agent. The loop
continues until the reviewer accepts the output or `maxIterations` is reached:

```dart
import 'dart:io';
import 'package:agents_core/agents_core.dart';

Future<void> main() async {
  final config = AgentsCoreConfig();
  final client = LmStudioClient(config);
  final context = FileContext(
    workspacePath: '${Directory.systemTemp.path}/loop_demo',
  );

  // Producer: generates work each iteration.
  final developer = SimpleAgent(
    name: 'developer',
    client: client,
    config: config,
    model: 'llama-3-8b',
    systemPrompt: 'You are a senior Dart developer. Write clean, idiomatic code. '
        'When given review feedback, revise your code to address every issue.',
  );

  // Reviewer: evaluates the producer's output.
  final qa = SimpleAgent(
    name: 'qa-reviewer',
    client: client,
    config: config,
    model: 'llama-3-8b',
    systemPrompt: 'You are a strict code reviewer. '
        'If the code meets all criteria, begin your response with "APPROVED". '
        'Otherwise, list the issues that must be fixed.',
  );

  // Create the loop — runs up to 4 produce-review rounds.
  final loop = AgentLoop(
    context: context,
    producer: developer,
    reviewer: qa,
    isAccepted: (AgentResult reviewerResult, int iteration) =>
        reviewerResult.output.trim().toUpperCase().startsWith('APPROVED'),
    maxIterations: 4,
  );

  // Run the loop with a task description.
  final result = await loop.run(
    'Write a Dart function `int fibonacci(int n)` that returns the n-th '
    'Fibonacci number. Handle negative inputs by throwing an ArgumentError.',
  );

  // ── Inspect each iteration via AgentLoopIteration ──────────────────
  for (final iteration in result.iterations) {
    print('Iteration ${iteration.index}:');
    print('  Producer tokens: ${iteration.producerResult.tokensUsed}');
    print('  Reviewer tokens: ${iteration.reviewerResult.tokensUsed}');
  }

  // ── Read the overall AgentLoopResult ───────────────────────────────
  print('Accepted:          ${result.accepted}');
  print('Iterations:        ${result.iterationCount}');
  print('Total tokens:      ${result.totalTokensUsed}');
  print('Duration:          ${result.duration.inMilliseconds} ms');
  print('Reached max iter:  ${result.reachedMaxIterations}');

  // The final producer output is accessible directly:
  print(result.lastProducerResult.output);

  client.dispose();
}
```

**How it works:**

1. Each iteration, `AgentLoop` builds a prompt and runs the **producer** agent.
2. The producer's output is forwarded to the **reviewer** agent for evaluation.
3. The `isAccepted` callback inspects the reviewer's `AgentResult` and the
   current iteration index — return `true` to accept and stop the loop.
4. If the reviewer rejects, its feedback is automatically appended to the next
   producer prompt so the producer can address the issues.
5. The loop stops when `isAccepted` returns `true` or `maxIterations` is
   reached (whichever comes first).

**Custom prompt builders:** For advanced scenarios you can supply
`buildProducerPrompt` and `buildReviewerPrompt` callbacks to control exactly
what each agent receives:

```dart
final loop = AgentLoop(
  context: context,
  producer: developer,
  reviewer: qa,
  isAccepted: (result, _) => result.output.contains('APPROVED'),
  buildProducerPrompt: (task, ctx, iteration, prevReview) async {
    final files = ctx.listFiles();
    return '$task\n\nWorkspace files: $files'
        '${prevReview != null ? '\n\nFeedback: ${prevReview.output}' : ''}';
  },
  buildReviewerPrompt: (task, ctx, iteration, producerResult) async {
    return 'Iteration $iteration — review:\n${producerResult.output}';
  },
);
```

**Key classes:**

| Class | Purpose |
|---|---|
| `AgentLoop` | Orchestrates the produce-review cycle |
| `AgentLoopIteration` | One iteration record with `index`, `producerResult`, and `reviewerResult` |
| `AgentLoopResult` | Overall result — `accepted`, `iterationCount`, `totalTokensUsed`, `duration`, `reachedMaxIterations` |

### Loop detection

Agents and loops can detect when the LLM is stuck repeating itself. Enable it
by passing a `LoopDetectionConfig`:

```dart
import 'package:agents_core/agents_core.dart';

Future<void> main() async {
  final config = AgentsCoreConfig();
  final client = LmStudioClient(config);

  final agent = ReActAgent(
    name: 'researcher',
    client: client,
    config: config,
    model: 'llama-3-8b',
    systemPrompt: 'You are a research assistant.',
    tools: [readFileTool, writeFileTool],
    toolHandlers: createHandlers(
      FileContext(workspacePath: '/tmp/workspace'),
    ),
    maxIterations: 15,
    // Stop if the LLM makes the same tool calls 3 times in a row,
    // or produces near-identical outputs 3 times in a row.
    loopDetectionConfig: const LoopDetectionConfig(
      maxConsecutiveIdenticalToolCalls: 3,
      maxConsecutiveIdenticalOutputs: 3,
      similarityThreshold: 0.85, // bigram Sørensen–Dice
    ),
  );

  final result = await agent.run('Summarise the workspace files.');
  print(result.output);
  print(result.stoppedReason); // "completed", "loop_detected", etc.

  client.dispose();
}
```

`AgentLoop` supports the same parameter — the detector tracks producer outputs
and stops early when repetition is found:

```dart
final loop = AgentLoop(
  context: ctx,
  producer: writer,
  reviewer: reviewer,
  isAccepted: (result, _) => result.output.contains('APPROVED'),
  maxIterations: 5,
  loopDetectionConfig: const LoopDetectionConfig(),
);

final result = await loop.run('Write a summary');
print(result.stoppedReason); // "accepted", "max_iterations", or "loop_detected"
print(result.loopDetected);  // true if stopped due to loop
```

## Module Overview

| Module | Key Classes | Description |
|---|---|---|
| **Agent** | `Agent`, `SimpleAgent`, `ReActAgent`, `AgentResult` | Define and run AI agents with tool calling |
| **Client** | `LmStudioClient`, `LmStudioHttpClient`, `SseParser` | HTTP client for LM Studio's OpenAI-compatible API |
| **Models** | `ChatMessage`, `ChatCompletionRequest`, `ChatCompletionResponse`, `ChatCompletionChunk`, `ToolDefinition`, `ToolCall`, `LmModel` | Request/response data structures |
| **Config** | `AgentsCoreConfig`, `Logger`, `StderrLogger`, `SilentLogger` | Configuration and logging |
| **File Context** | `FileContext`, `readFileTool`, `writeFileTool`, `listFilesTool`, `createHandlers` | Sandboxed file operations with tool definitions |
| **Orchestrator** | `Orchestrator`, `OrchestratorStep`, `AgentStep`, `AgentLoopStep`, `OrchestratorResult`, `StepResult`, `AgentStepResult`, `AgentLoopStepResult`, `OrchestratorErrorPolicy` | Sequential multi-agent pipelines with mixed step types |
| **AgentLoop** | `AgentLoop`, `AgentLoopIteration`, `AgentLoopResult` | Iterative produce-review refinement loop |
| **Loop Detection** | `LoopDetectionConfig`, `LoopDetector`, `LoopCheckResult` | Detect and break repetitive LLM loops via tool-call fingerprinting and bigram similarity |
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
- [`agent_loop.dart`](example/agent_loop.dart) — Produce-review loop with AgentLoop
- [`orchestrator_with_agent_loop.dart`](example/orchestrator_with_agent_loop.dart) — Orchestrator pipeline mixing AgentStep with AgentLoopStep
- [`feature_development_pipeline.dart`](example/feature_development_pipeline.dart) — Realistic 5-stage software development pipeline
- [`bugfix_pipeline.dart`](example/bugfix_pipeline.dart) — End-to-end bugfix workflow with 7 agents across 5 pipeline steps
- [`api_key_config.dart`](example/api_key_config.dart) — API key configuration (explicit, env var, copyWith)

## Configuration

`AgentsCoreConfig` accepts these parameters:

| Parameter | Default | Description |
|---|---|---|
| `lmStudioBaseUrl` | `http://localhost:1234` | LM Studio server URL |
| `defaultModel` | `lmstudio-community/default` | Default model identifier |
| `requestTimeout` | `60 seconds` | HTTP connection timeout |
| `dockerImage` | `python:3.12-slim` | Docker image for Python execution |
| `workspacePath` | `/tmp/agents_workspace` | Default workspace path |
| `apiKey` | `null` | Optional Bearer token for authenticated LM Studio requests |
| `loggingEnabled` | `true` | Global toggle to enable/disable all logging |
| `logger` | `StderrLogger(level: LogLevel.info)` | Logger instance |

You can also create configuration from environment variables:

```dart
final config = AgentsCoreConfig.fromEnvironment();
```

Supported environment variables: `LM_STUDIO_BASE_URL`, `AGENTS_DEFAULT_MODEL`,
`AGENTS_DOCKER_IMAGE`, `AGENTS_WORKSPACE_PATH`, `AGENTS_REQUEST_TIMEOUT_SECONDS`,
`AGENTS_API_KEY`, `AGENTS_LOGGING_ENABLED`.

### Logging

Logging is **enabled by default** — all library components write timestamped
diagnostic messages to stderr via `StderrLogger`.

#### Disable logging globally

Pass `loggingEnabled: false` to suppress all log output without replacing the
logger instance:

```dart
final config = AgentsCoreConfig(loggingEnabled: false);
```

Or set the `AGENTS_LOGGING_ENABLED` environment variable:

```sh
export AGENTS_LOGGING_ENABLED=false  # also accepts "0"
```

Then create the config from the environment:

```dart
final config = AgentsCoreConfig.fromEnvironment();
// Logging is now disabled — all logger calls are silently discarded.
```

#### Re-enable logging on an existing config

Use `copyWith` to toggle logging at any point:

```dart
final silent = AgentsCoreConfig(loggingEnabled: false);
final verbose = silent.copyWith(loggingEnabled: true);
```

#### Custom log level

Control the minimum severity emitted by the default `StderrLogger`:

```dart
final config = AgentsCoreConfig(
  logger: StderrLogger(level: LogLevel.debug), // debug, info, warn, error
);
```

#### Custom logger

Implement the `Logger` interface to integrate with your own logging framework:

```dart
class MyLogger extends Logger {
  @override
  LogLevel get level => LogLevel.info;

  @override
  void debug(String message) { /* ... */ }
  @override
  void info(String message)  { /* ... */ }
  @override
  void warn(String message)  { /* ... */ }
  @override
  void error(String message) { /* ... */ }
}

final config = AgentsCoreConfig(logger: MyLogger());
```

> **Note:** When `loggingEnabled` is `false`, the `config.logger` getter
> returns a `SilentLogger` transparently — your custom logger is preserved
> internally and becomes active again when logging is re-enabled.

### Authentication

When the LM Studio server is deployed behind an API gateway or reverse proxy
that requires authentication, provide an `apiKey`. The key is sent as a `Bearer`
token in the `Authorization` header of every outgoing HTTP request.

```dart
// Explicit API key
final config = AgentsCoreConfig(
  apiKey: 'my-secret-key',
);

// Or read from the AGENTS_API_KEY environment variable
final config = AgentsCoreConfig.fromEnvironment();

// Add or remove a key from an existing config
final authenticated = config.copyWith(apiKey: 'new-key');
final anonymous = config.copyWith(clearApiKey: true);
```

> **Tip:** For local development without authentication, omit the `apiKey`
> parameter — it defaults to `null` and no `Authorization` header is sent.

See [`example/api_key_config.dart`](example/api_key_config.dart) for a complete
runnable example.

## License

MIT — see [LICENSE](LICENSE) for details.

Copyright 2026 David Araujo
