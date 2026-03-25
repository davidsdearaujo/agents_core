// API key configuration example.
//
// Demonstrates how to initialise `AgentsCoreConfig` with an API key for
// authenticated LM Studio requests. Shows three approaches:
//
// 1. Explicit constructor parameter
// 2. Environment variable via `fromEnvironment()`
// 3. Using `copyWith` to add/remove an API key from an existing config
//
// ## Run
//
//   dart run example/api_key_config.dart
import 'package:agents_core/agents_core.dart';

void main() {
  // ── 1. Explicit API key via constructor ──────────────────────────────────
  final config = AgentsCoreConfig(
    apiKey: 'my-secret-api-key',
    logger: const SilentLogger(),
  );

  print('1. Explicit API key');
  print('   Has API key: ${config.apiKey != null}');
  print('   Config:      $config\n');

  // ── 2. API key from environment variables ────────────────────────────────
  // In production, set AGENTS_API_KEY in your shell environment.
  // Here we simulate it with a map for demonstration purposes.
  final envConfig = AgentsCoreConfig.fromEnvironment(
    environment: {
      'AGENTS_API_KEY': 'env-provided-key',
      'AGENTS_DEFAULT_MODEL': 'llama-3-8b',
    },
    logger: const SilentLogger(),
  );

  print('2. API key from environment');
  print('   Has API key: ${envConfig.apiKey != null}');
  print('   Model:       ${envConfig.defaultModel}\n');

  // ── 3. copyWith — add or remove an API key ───────────────────────────────
  final withKey = config.copyWith(apiKey: 'new-key');
  print('3a. copyWith (replace key)');
  print('    Has API key: ${withKey.apiKey != null}\n');

  final withoutKey = config.copyWith(clearApiKey: true);
  print('3b. copyWith (clear key)');
  print('    Has API key: ${withoutKey.apiKey != null}\n');

  // ── 4. No API key (default) ──────────────────────────────────────────────
  final noAuth = AgentsCoreConfig(logger: const SilentLogger());
  print('4. No API key (default)');
  print('   API key: ${noAuth.apiKey}');
  print('   Config:  $noAuth');
}
