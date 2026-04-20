/// The reason an agent or agent loop stopped generating.
///
/// Replaces the magic-string `stoppedReason` field with a typed enum so that
/// consumers get exhaustiveness checking from the Dart compiler and IDEs
/// provide accurate auto-complete.
///
/// Used as the type of [AgentResult.stoppedReason] (produced by
/// [ReActAgent]) and [AgentLoopResult.stoppedReason] (produced by
/// [AgentLoop]).
///
/// ```dart
/// final result = await agent.run('task');
/// switch (result.stoppedReason) {
///   case AgentStopReason.completed:
///     print('Done naturally');
///   case AgentStopReason.maxIterations:
///     print('Hit iteration cap');
///   case AgentStopReason.maxTotalTokens:
///     print('Token budget exceeded');
///   case AgentStopReason.terminalTool:
///     print('Terminal tool signalled completion');
///   case AgentStopReason.loopDetected:
///     print('Repetitive pattern detected');
///   case AgentStopReason.accepted:
///     print('Reviewer accepted the output');
///   case null:
///     print('No stop reason recorded');
/// }
/// ```
enum AgentStopReason {
  /// The model produced a response with no tool calls — natural end of the
  /// ReAct loop.
  completed,

  /// The maximum number of iterations ([ReActAgent.maxIterations] or
  /// [AgentLoop.maxIterations]) was reached without a natural completion or
  /// reviewer acceptance.
  maxIterations,

  /// The cumulative token usage exceeded [ReActAgent.maxTotalTokens].
  maxTotalTokens,

  /// A tool whose name is in [ReActAgent.terminalTools] was called,
  /// signalling that no further iterations are needed.
  terminalTool,

  /// A repetitive output or tool-call pattern was detected by the
  /// [LoopDetector] (configured via [ReActAgent.loopDetectionConfig] or
  /// [AgentLoop.loopDetectionConfig]).
  loopDetected,

  /// The reviewer agent accepted the producer's output
  /// ([AgentLoop] only).
  accepted,
}
