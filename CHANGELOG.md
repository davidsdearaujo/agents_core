# Changelog

## 0.1.0 — 2026-03-25

First feature-complete release of `agents_core`.

### Features

#### Agent Framework
- `Agent` abstract base class with `run(String task, {FileContext? context})` method.
- `SimpleAgent` — single-round chat completion agent.
- `ReActAgent` — multi-turn Reason + Act loop with tool calling, configurable
  `maxIterations` and `maxTotalTokens` budget.
- `AgentResult` — structured output with `output`, `tokensUsed`,
  `toolCallsMade`, `filesModified`, and `stoppedReason`.

#### LM Studio Client
- `LmStudioClient` — high-level typed API for LM Studio's OpenAI-compatible
  endpoints (`chatCompletion`, `chatCompletionStream`, `chatCompletionStreamText`,
  `completion`, `completionStream`, `listModels`).
- `LmStudioHttpClient` — HTTP transport with automatic retry and exponential
  backoff (`maxRetries`, configurable `delay`).
- `SseParser` — Server-Sent Events stream transformer that handles multi-line
  data and `[DONE]` sentinels.

#### Data Models (OpenAI-compatible)
- `ChatMessage` and `ChatMessageRole` enum (`system`, `user`, `assistant`, `tool`).
- `ChatCompletionRequest` / `ChatCompletionResponse` / `ChatCompletionChoice`.
- `ChatCompletionChunk` / `ChatCompletionChunkChoice` / `ChatCompletionDelta`
  for streaming responses.
- `CompletionRequest` / `CompletionResponse` / `CompletionChoice`.
- `CompletionUsage` — token usage tracking.
- `ToolDefinition` and `ToolCall` / `ToolCallFunction` for function calling.
- `LmModel` — model listing response.

#### Configuration
- `AgentsCoreConfig` — central configuration with `lmStudioBaseUrl`,
  `defaultModel`, `requestTimeout`, `dockerImage`, `workspacePath`, and `logger`.
- `AgentsCoreConfig.fromEnvironment()` factory — reads `LM_STUDIO_BASE_URL`,
  `AGENTS_DEFAULT_MODEL`, `AGENTS_DOCKER_IMAGE`, `AGENTS_WORKSPACE_PATH`, and
  `AGENTS_REQUEST_TIMEOUT_SECONDS` from environment variables.
- `AgentsCoreConfig.copyWith()` for immutable modifications.
- `Logger` abstraction with `StderrLogger` and `SilentLogger` implementations.

#### File Context
- `FileContext` — sandboxed file-system abstraction with `read`, `write`,
  `append`, `delete`, `exists`, and `listFiles` (with glob filtering).
- Path traversal protection on all file operations.
- Pre-built tool definitions: `readFileTool`, `writeFileTool`, `listFilesTool`,
  `appendFileTool`, and `createHandlers()` factory.

#### Orchestrator
- `Orchestrator` — sequential agent pipeline with shared `FileContext`.
- `AgentStep` — static or dynamic (`AgentStep.dynamic`) task prompts with
  optional `condition` guards.
- `OrchestratorResult` — collects `stepResults`, `duration`, and `errors`.
- `OrchestratorErrorPolicy` — `stop` (default) or `continueOnError`.

#### Docker Integration
- `DockerClient` — run containers, check availability, pull images.
- `DockerRunResult` — captures `stdout`, `stderr`, and `exitCode`.

#### Python Execution
- `PythonToolAgent` — pre-configured `ReActAgent` with Docker-based Python
  execution and optional file tools.
- `PythonExecutionTool` — tool definition and handler factory for running
  Python code in sandboxed Docker containers.

#### Quick Functions
- `ask()` — one-shot chat completion that manages client lifecycle.
- `askStream()` — streaming one-shot chat completion.
- `Conversation` — stateful multi-turn wrapper with `send()`, `sendStream()`,
  `setSystemPrompt()`, and `clearHistory()`.

#### Exception Hierarchy
- `AgentsCoreException` — library base exception.
- `LmStudioHttpException` — non-2xx HTTP responses.
- `LmStudioApiException` — structured API errors with `isModelNotFound`,
  `isContextLengthExceeded`, and `isRateLimited` helpers.
- `LmStudioConnectionException` — transport failures with `socketError`,
  `httpError`, `timeout`, and `fromException` factories.
- `DockerNotAvailableException` / `DockerExecutionException`.
- `FileNotFoundException` / `PathTraversalException`.
- `SseParseException` — malformed SSE data.

## 0.0.1

- Initial project scaffold.
