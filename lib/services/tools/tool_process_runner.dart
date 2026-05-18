import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../data/log_entry.dart';
import '../../features/app_log/app_logger.dart';
import '../../utils/adb_path.dart';

class ToolCommandResult {
  const ToolCommandResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  factory ToolCommandResult.fromProcessResult(ProcessResult result) {
    return ToolCommandResult(
      exitCode: result.exitCode,
      stdout: result.stdout is String ? result.stdout as String : '',
      stderr: result.stderr is String ? result.stderr as String : '',
    );
  }

  final int exitCode;
  final String stdout;
  final String stderr;

  bool get isSuccess => exitCode == 0;

  String get combinedOutput {
    final trimmedStdout = stdout.trim();
    final trimmedStderr = stderr.trim();

    if (trimmedStdout.isEmpty) return trimmedStderr;
    if (trimmedStderr.isEmpty) return trimmedStdout;
    return '$trimmedStdout\n$trimmedStderr';
  }
}

class ToolStreamSession<T> {
  ToolStreamSession({
    required this.stream,
    required Future<void> Function() onStop,
  }) : _onStop = onStop;

  final Stream<T> stream;
  final Future<void> Function() _onStop;

  Future<void> stop() => _onStop();
}

abstract class ToolProcessRunner {
  ToolProcessRunner({required this.executableName, String? executablePath})
    : executable =
          executablePath ??
          resolveBundledExecutablePath(executableName) ??
          executableName {
    logger = AppLogger(source: runtimeType.toString());
  }

  final String executableName;
  final String executable;

  late final AppLogger logger;

  Future<ToolCommandResult> runText(List<String> arguments) async {
    final result = await Process.run(
      executable,
      arguments,
      environment: _toolEnvironment(),
      workingDirectory: _toolWorkingDirectory(),
    );
    return ToolCommandResult.fromProcessResult(result);
  }

  Future<Process> startProcess(List<String> arguments) {
    return Process.start(
      executable,
      arguments,
      environment: _toolEnvironment(),
      workingDirectory: _toolWorkingDirectory(),
    );
  }

  Stream<String> stdoutLines(Process process) {
    return process.stdout
        .transform(Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter());
  }

  Future<String> stderrText(Process process) {
    return process.stderr.transform(utf8.decoder).join();
  }

  Future<void> stopProcess(Process? process) async {
    if (process == null) return;
    if (process.kill(ProcessSignal.sigterm)) {
      try {
        await process.exitCode.timeout(const Duration(seconds: 1));
      } catch (_) {}
    }
  }

  String describeCommandFailure(String fallback, ToolCommandResult result) {
    final output = result.combinedOutput;
    if (output.isNotEmpty) {
      return output;
    }
    return '$fallback (exit code ${result.exitCode}).';
  }

  String describeError(Object error) {
    final message = error.toString();
    return message.startsWith('Exception: ')
        ? message.substring('Exception: '.length)
        : message;
  }

  void logError(String message, [Object? error]) {
    logger.error(message, detail: error?.toString());
  }

  void logInfo(String message) {
    logger.info(message);
  }

  void logSuccess(String message) {
    logger.success(message);
  }

  LogEntry buildToolErrorEntry(
    String message, {
    required String tag,
    required String processName,
  }) {
    return LogEntry.toolError(
      message: message,
      tag: tag,
      processName: processName,
    );
  }

  Map<String, String>? _toolEnvironment() {
    final toolDirectory = _toolDirectoryPath();
    if (toolDirectory == null) {
      return null;
    }

    final environment = <String, String>{};
    _prependEnvironmentPath(environment, 'PATH', toolDirectory);

    if (Platform.isWindows) {
      _prependEnvironmentPath(environment, _windowsPathKey, toolDirectory);
    } else if (Platform.isLinux) {
      _prependEnvironmentPath(environment, 'LD_LIBRARY_PATH', toolDirectory);
    } else if (Platform.isMacOS) {
      _prependEnvironmentPath(environment, 'DYLD_LIBRARY_PATH', toolDirectory);
    }

    return environment.isEmpty ? null : environment;
  }

  String? _toolWorkingDirectory() => _toolDirectoryPath();

  String? _toolDirectoryPath() {
    final absoluteExecutable = File(executable);
    if (absoluteExecutable.isAbsolute) {
      return absoluteExecutable.parent.path;
    }

    return resolveBundledToolsDirectory()?.path;
  }

  void _prependEnvironmentPath(
    Map<String, String> environment,
    String key,
    String directoryPath,
  ) {
    final pathSeparator = Platform.isWindows ? ';' : ':';
    final inheritedValue =
        environment[key] ??
        Platform.environment[key] ??
        (Platform.isWindows && key != 'PATH'
            ? Platform.environment['PATH']
            : null) ??
        '';
    environment[key] = inheritedValue.isEmpty
        ? directoryPath
        : '$directoryPath$pathSeparator$inheritedValue';
  }

  String get _windowsPathKey {
    for (final key in Platform.environment.keys) {
      if (key.toLowerCase() == 'path') {
        return key;
      }
    }
    return 'Path';
  }
}
