import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../features/emulator_manager/data/emulator_launch_options.dart';
import '../../utils/utils.dart';
import 'tool_process_runner.dart';

/// Wraps the Android SDK's `emulator` binary.
///
/// Unlike every other [ToolProcessRunner] in here, the executable is not
/// bundled — it belongs to the user's own SDK and is located by
/// `utils/android_sdk_path.dart`, so [executablePath] is required rather than
/// resolved. There is no sensible fallback to a bare `emulator` on PATH: the
/// binary refuses to run unless it can find its sibling `lib64/` payload, so a
/// wrong copy fails in a far more confusing way than no copy at all.
class EmulatorTool extends ToolProcessRunner {
  EmulatorTool({required String executablePath})
    : super(executableName: 'emulator', executablePath: executablePath);

  /// `-list-avds` is quick, but a half-installed SDK can wedge it, and this
  /// runs behind a user-visible refresh.
  static const Duration listTimeout = Duration(seconds: 15);

  /// AVD ids known to this SDK, in the order the emulator reports them.
  ///
  /// Returns an empty list on failure rather than throwing — an SDK that
  /// cannot list AVDs is a state the dialog renders, not an exception.
  Future<List<String>> listAvds() async {
    try {
      final result = await runTextWithTimeout([
        '-list-avds',
      ], timeout: listTimeout);
      return parseAvdNames(result);
    } catch (error) {
      logError('Failed to list AVDs', error);
      return const [];
    }
  }

  /// Names come back one per line on stdout, and stderr stays empty on a
  /// healthy SDK. A build that logs (`INFO | …`) or an SDK that complains
  /// would otherwise contribute lines that are not AVD names, so anything
  /// that cannot be an AVD id is dropped rather than shown as a broken entry.
  @visibleForTesting
  List<String> parseAvdNames(ToolCommandResult result) {
    if (!result.isSuccess) {
      logWarning(
        'Listing AVDs failed',
        describeCommandFailure('emulator -list-avds failed', result),
      );
      return const [];
    }

    return [
      for (final line in const LineSplitter().convert(result.stdout))
        if (_avdNamePattern.hasMatch(line.trim())) line.trim(),
    ];
  }

  /// Starts [avdName].
  ///
  /// **Detached on purpose, and it has to be.** An emulator must outlive the
  /// app that started it: [ToolProcessRunner.terminateAllProcesses] kills
  /// every tracked child when eagly quits, and killing a running emulator
  /// mid-write is how AVDs get corrupted. Detached children are excluded from
  /// that set — the same reason `AdbTool.ensureServerRunning` detaches the adb
  /// server.
  ///
  /// The cost is that Dart gives a detached child neither stdio nor an exit
  /// code, so a failed launch cannot be read off the process. The alternative,
  /// `detachedWithStdio`, would hand us the emulator's error output but leaves
  /// the child writing into pipes whose read end closes when eagly exits —
  /// trading a clean quit for a possible SIGPIPE'd emulator, which is the
  /// exact failure this is avoiding.
  ///
  /// So failures are caught on either side instead: callers check [avdName]
  /// against [listAvds] first (an unknown name is the common case, and the
  /// emulator exits 1 on it), and a launch that spawns but never boots is
  /// reported by the caller watching for the device to appear in `adb
  /// devices`.
  Future<EmulatorLaunchOutcome> launch(
    String avdName, {
    EmulatorLaunchOptions options = EmulatorLaunchOptions.normal,
  }) async {
    final arguments = buildLaunchArguments(avdName, options);
    logInfo('Launching AVD $avdName (${arguments.join(' ')})');

    try {
      final process = await startProcess(
        arguments,
        mode: ProcessStartMode.detached,
      );
      logSuccess('Started the emulator process for $avdName (${process.pid})');
      return EmulatorLaunchOutcome.success(process.pid);
    } catch (error) {
      logError('Failed to launch $avdName', error);
      return EmulatorLaunchOutcome.failure(
        'Could not start $avdName: ${describeError(error)}',
      );
    }
  }

  @visibleForTesting
  List<String> buildLaunchArguments(
    String avdName,
    EmulatorLaunchOptions options,
  ) => ['-avd', avdName, ...options.toArguments()];

  /// AVD ids are created from a restricted alphabet — the AVD Manager rejects
  /// anything else, and `emulator -avd` cannot address it.
  static final RegExp _avdNamePattern = RegExp(r'^[A-Za-z0-9._-]+$');
}
