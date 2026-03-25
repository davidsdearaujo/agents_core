import 'dart:io';

import '../agent/agent_result.dart';
import '../agent/react_agent.dart';
import '../client/lm_studio_client.dart';
import '../config/agents_core_config.dart';
import '../context/file_context.dart';
import '../docker/docker_client.dart';
import '../exceptions/docker_exceptions.dart';
import '../models/tool_definition.dart';
import 'file_context_tools.dart';
import 'python_execution_tool.dart';

/// An agent that can execute Python code in a sandboxed Docker container.
///
/// [PythonToolAgent] extends [ReActAgent] with pre-configured tools for
/// Python execution and (optionally) file-system access within a shared
/// workspace.
///
/// On each [run] call the agent:
///
/// 1. Verifies Docker is available — throws [DockerNotAvailableException]
///    with an actionable message if not.
/// 2. Pulls the Docker image if it is not cached locally.
/// 3. Enters the ReAct loop, where the model can call `execute_python`
///    (and optionally `read_file`, `write_file`, `list_files`).
///
/// ```dart
/// final agent = PythonToolAgent(
///   name: 'data-analyst',
///   client: LmStudioClient(config),
///   config: config,
///   dockerClient: DockerClient(logger: config.logger),
///   fileContext: FileContext(workspacePath: '/tmp/workspace'),
/// );
///
/// final result = await agent.run('Compute the mean of [1, 2, 3, 4, 5]');
/// print(result.output);
/// ```
class PythonToolAgent extends ReActAgent {
  /// Creates a [PythonToolAgent] with auto-registered `execute_python` tool.
  ///
  /// [dockerClient] is used for Docker availability checks, image pulls, and
  /// container execution.
  ///
  /// [fileContext] is the sandboxed workspace shared between the host and the
  /// Docker container (mounted at `/workspace`). When `null`, a temporary
  /// workspace is created under [Directory.systemTemp].
  ///
  /// [dockerImage] is the Docker image used for Python execution. Defaults to
  /// `'python:3.12-slim'`.
  ///
  /// [executionTimeout] limits how long each Python execution may run inside
  /// the container. Defaults to 120 seconds.
  ///
  /// [enableFileTools] registers `read_file`, `write_file`, and `list_files`
  /// tools that let the model interact with the workspace. Defaults to
  /// `false`.
  ///
  /// [additionalTools] and [additionalToolHandlers] allow extending the
  /// agent with custom tools beyond the built-in ones.
  ///
  /// [maxIterations] defaults to 15 (higher than [ReActAgent]'s default of
  /// 10) to accommodate multi-step Python workflows.
  factory PythonToolAgent({
    required String name,
    required LmStudioClient client,
    required AgentsCoreConfig config,
    required DockerClient dockerClient,
    FileContext? fileContext,
    String dockerImage = 'python:3.12-slim',
    Duration executionTimeout = const Duration(seconds: 120),
    bool enableFileTools = false,
    String? model,
    int? maxTotalTokens,
    int maxIterations = 15,
    List<ToolDefinition> additionalTools = const [],
    Map<String, ToolHandler> additionalToolHandlers = const {},
    String? systemPrompt,
  }) {
    // Resolve or create the workspace.
    final context = fileContext ??
        FileContext(
          workspacePath:
              '$_systemTempPath/agents_core_${DateTime.now().millisecondsSinceEpoch}',
        );

    // ── Build tool definitions ──────────────────────────────────────────
    final tools = <ToolDefinition>[
      executePythonToolDefinition,
      if (enableFileTools) ...fileContextToolDefinitions,
      ...additionalTools,
    ];

    // ── Build tool handlers ─────────────────────────────────────────────
    final handlers = <String, ToolHandler>{
      'execute_python': createExecutePythonHandler(
        context: context,
        dockerClient: dockerClient,
        logger: config.logger,
        image: dockerImage,
        timeout: executionTimeout,
      ),
      if (enableFileTools) ...createFileContextHandlers(context: context),
      ...additionalToolHandlers,
    };

    // ── Build system prompt ─────────────────────────────────────────────
    final prompt = systemPrompt ?? _buildDefaultSystemPrompt(enableFileTools);

    return PythonToolAgent._(
      name: name,
      client: client,
      config: config,
      dockerClient: dockerClient,
      dockerImage: dockerImage,
      fileContext: context,
      toolHandlers: handlers,
      tools: tools,
      systemPrompt: prompt,
      model: model,
      maxIterations: maxIterations,
      maxTotalTokens: maxTotalTokens,
    );
  }

  /// Private constructor — use the factory [PythonToolAgent()] instead.
  PythonToolAgent._({
    required super.name,
    required super.client,
    required super.config,
    required super.toolHandlers,
    required super.tools,
    required super.systemPrompt,
    super.model,
    super.maxIterations,
    super.maxTotalTokens,
    required this.dockerClient,
    required this.dockerImage,
    required this.fileContext,
  });

  /// The Docker client used for availability checks, image pulls, and
  /// container execution.
  final DockerClient dockerClient;

  /// The Docker image used for Python execution.
  final String dockerImage;

  /// The sandboxed workspace shared between host and container.
  final FileContext fileContext;

  /// Executes the agent's task with Docker pre-checks.
  ///
  /// Before entering the ReAct loop, this method:
  ///
  /// 1. Verifies Docker is available by calling
  ///    [DockerClient.isAvailable]. Throws
  ///    [DockerNotAvailableException] if the daemon is unreachable.
  /// 2. Checks whether [dockerImage] is cached locally. If not, pulls it
  ///    from the registry.
  ///
  /// Then delegates to [ReActAgent.run] for the standard reasoning loop.
  ///
  /// Throws [DockerNotAvailableException] if Docker is not available.
  /// Throws [DockerExecutionException] if the image pull fails.
  @override
  Future<AgentResult> run(String task, {FileContext? context}) async {
    config.logger.info('[$name] Pre-flight: checking Docker availability');

    // ── Step 1: Docker daemon check ───────────────────────────────────
    final available = await dockerClient.isAvailable();
    if (!available) {
      throw DockerNotAvailableException(
        message: 'Docker is not available. '
            'Please ensure Docker is installed and the daemon is running. '
            'On macOS/Windows, open Docker Desktop. '
            'On Linux, run: sudo systemctl start docker',
      );
    }

    // ── Step 2: Image availability check + pull ─────────────────────────
    final imageAvailable = await dockerClient.isImageAvailable(dockerImage);
    if (!imageAvailable) {
      config.logger.info(
        '[$name] Image "$dockerImage" not found locally, pulling...',
      );
      await dockerClient.pullImage(dockerImage);
    }

    config.logger.info('[$name] Pre-flight complete, starting ReAct loop');

    // ── Step 3: Delegate to ReActAgent.run ───────────────────────────────
    return super.run(task, context: context ?? fileContext);
  }

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  /// Builds the default system prompt based on enabled features.
  static String _buildDefaultSystemPrompt(bool enableFileTools) {
    final buffer = StringBuffer()
      ..writeln('You are a helpful AI assistant with Python code execution '
          'capabilities.')
      ..writeln()
      ..writeln('You have access to a sandboxed Python environment running '
          'in a Docker container. The working directory is /workspace.')
      ..writeln()
      ..writeln('## execute_python tool')
      ..writeln('- Use this tool to run Python code for computations, data '
          'analysis, file processing, or any task that benefits from code '
          'execution.')
      ..writeln('- You can install pip packages by providing a '
          '"requirements" list.')
      ..writeln('- The container has no network access for security.')
      ..writeln('- The /workspace directory is shared between executions, '
          'so files written by one execution are available to the next.');

    if (enableFileTools) {
      buffer
        ..writeln()
        ..writeln('## File tools')
        ..writeln('- Use read_file, write_file, and list_files to interact '
            'with the /workspace directory directly.')
        ..writeln('- These tools operate on the same workspace as '
            'execute_python, so you can prepare input files before '
            'execution and inspect output files after.');
    }

    buffer
      ..writeln()
      ..writeln('## Guidelines')
      ..writeln('- Break complex tasks into smaller steps.')
      ..writeln('- When code fails, read the error message carefully and '
          'fix the issue.')
      ..writeln('- Prefer using print() to show results rather than '
          'returning values.')
      ..writeln('- Always explain your reasoning before and after running '
          'code.');

    return buffer.toString().trimRight();
  }

  /// The system temporary directory path, obtained once.
  static final String _systemTempPath =
      Directory.systemTemp.path;
}
