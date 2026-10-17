import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../features/logs/data/models/log_entry.dart';
import '../../features/app_log/app_logger.dart';
import '../../utils/tools_path.dart';
import '../../utils/log_entry_utils.dart';

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
      stdoutEncoding: null,
      stderrEncoding: null,
    );
    return ToolCommandResult(
      exitCode: result.exitCode,
      stdout: Utf8Decoder(
        allowMalformed: true,
      ).convert(result.stdout as List<int>),
      stderr: Utf8Decoder(
        allowMalformed: true,
      ).convert(result.stderr as List<int>),
    );
  }

  /// Like [runText], but kills the process and returns exit code `-1` when it
  /// runs longer than [timeout]. `Process.run` cannot be interrupted, so this
  /// starts the process instead and collects its output itself — use it for
  /// commands whose runtime is not bounded by the tool (arbitrary `adb shell`
  /// lines, libimobiledevice calls against a locked device, …).
  Future<ToolCommandResult> runTextWithTimeout(
    List<String> arguments, {
    Duration timeout = const Duration(seconds: 30),
    bool closeStdin = false,
  }) async {
    final process = await startProcess(arguments);
    // A tool that asks a question mid-run blocks forever on a stdin pipe that
    // never closes; closing it makes the tool take its own default instead.
    // (`avdmanager create avd` offers to build a custom hardware profile.)
    if (closeStdin) {
      unawaited(process.stdin.close().catchError((_) {}));
    }
    const decoder = Utf8Decoder(allowMalformed: true);
    final stdoutFuture = process.stdout.transform(decoder).join();
    final stderrFuture = process.stderr.transform(decoder).join();

    var timedOut = false;
    final exitCode = await process.exitCode.timeout(
      timeout,
      onTimeout: () {
        timedOut = true;
        process.kill(ProcessSignal.sigkill);
        return -1;
      },
    );

    final stdout = await stdoutFuture;
    final stderr = await stderrFuture;
    return ToolCommandResult(
      exitCode: exitCode,
      stdout: stdout,
      stderr: timedOut
          ? '${stderr.trimRight()}\n'
                'Timed out after ${timeout.inSeconds}s and was terminated.'
          : stderr,
    );
  }

  /// Runs the tool and returns its raw stdout bytes (for binary output such as
  /// `adb exec-out screencap -p`). Throws [ProcessException] on a non-zero exit.
  Future<List<int>> runBytes(List<String> arguments) async {
    final result = await Process.run(
      executable,
      arguments,
      environment: _toolEnvironment(),
      workingDirectory: _toolWorkingDirectory(),
      stdoutEncoding: null,
    );
    if (result.exitCode != 0) {
      final stderr = result.stderr is String ? result.stderr as String : '';
      throw ProcessException(executable, arguments, stderr, result.exitCode);
    }
    return result.stdout as List<int>;
  }

  /// Every non-detached child this app has spawned and not yet reaped.
  ///
  /// Nothing kills these for us: on macOS and Linux a child outlives its
  /// parent and is reparented to init, so a long-running `adb track-devices`
  /// or `adb logcat` survives the app that started it and holds its adb server
  /// connection open forever. Quitting eagly repeatedly used to leave one
  /// orphan per launch. [terminateAllProcesses] is what closes them out.
  ///
  /// Detached processes are deliberately excluded — `AdbTool.ensureServerRunning`
  /// starts the adb server that way precisely so it *does* outlive us.
  static final Set<Process> _liveProcesses = <Process>{};

  /// Terminates every tracked child. Called on app exit; also safe to call
  /// mid-session (a process that already exited is simply not in the set).
  ///
  /// Only covers a graceful shutdown — a `SIGKILL`ed app still orphans its
  /// children, since no cleanup of ours can run.
  static Future<void> terminateAllProcesses() async {
    final processes = _liveProcesses.toList(growable: false);
    _liveProcesses.clear();
    await Future.wait(processes.map(_terminate));
  }

  static Future<void> _terminate(Process process) async {
    process.kill(ProcessSignal.sigterm);
    try {
      await process.exitCode.timeout(const Duration(milliseconds: 500));
    } catch (_) {
      process.kill(ProcessSignal.sigkill);
    }
  }

  Future<Process> startProcess(
    List<String> arguments, {
    ProcessStartMode mode = ProcessStartMode.normal,
  }) async {
    final process = await Process.start(
      executable,
      arguments,
      environment: _toolEnvironment(),
      workingDirectory: _toolWorkingDirectory(),
      mode: mode,
    );
    if (mode != ProcessStartMode.detached &&
        mode != ProcessStartMode.detachedWithStdio) {
      _liveProcesses.add(process);
      unawaited(
        process.exitCode.whenComplete(() => _liveProcesses.remove(process)),
      );
    }
    return process;
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

  void logError(String message, [Object? error]) {
    logger.error(message, detail: error?.toString());
  }

  void logWarning(String message, [Object? detail]) {
    logger.warning(message, detail: detail?.toString());
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
    return LogEntryUtils.buildToolError(
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
