import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../features/emulator_manager/data/device_profile.dart';
import '../../features/wireless_connection/data/wireless_debug_models.dart';
import '../../utils/utils.dart';
import 'tool_process_runner.dart';

/// Wraps the SDK's `avdmanager`, which is what creates and deletes AVDs.
///
/// Like the emulator binary this is not bundled — it comes from the user's
/// `cmdline-tools`, which is an *optional* SDK package. An SDK without it can
/// still list and launch AVDs, so nothing here may gate the feature as a
/// whole; see `AndroidSdkLocation.canManageAvds`.
///
/// Every call pays a JVM start (~1.5s measured), so results worth keeping are
/// cached by the caller rather than re-read.
class AvdManagerTool extends ToolProcessRunner {
  AvdManagerTool({required String executablePath})
    : super(executableName: 'avdmanager', executablePath: executablePath);

  /// Generous because the JVM start dominates and a cold SDK repository scan
  /// can add several seconds on top.
  static const Duration timeout = Duration(seconds: 90);

  /// The hardware profiles this SDK knows about.
  ///
  /// Empty on failure rather than throwing: a create sheet with no profiles
  /// still works, since `-d` is optional.
  Future<List<DeviceProfile>> listDeviceProfiles() async {
    try {
      final result = await runTextWithTimeout(
        ['list', 'device'],
        timeout: timeout,
        closeStdin: true,
      );

      if (!result.isSuccess) {
        logWarning(
          'Listing device profiles failed',
          describeCommandFailure('avdmanager list device failed', result),
        );
        return const [];
      }
      return parseDeviceProfiles(result.stdout);
    } catch (error) {
      logError('Failed to list device profiles', error);
      return const [];
    }
  }

  /// Parses the record-per-profile listing:
  ///
  ///     id: 28 or "pixel"
  ///         Name: Pixel
  ///         OEM : Google
  ///         Tag : android-tv
  ///     ---------
  ///
  /// `Tag` is absent for phones and tablets. The quoted id is the one `-d`
  /// takes and can contain spaces (`"Galaxy Nexus"`), so it is never split.
  @visibleForTesting
  List<DeviceProfile> parseDeviceProfiles(String stdout) {
    final profiles = <DeviceProfile>[];
    String? id;
    String? name;
    String? oem;
    String? tag;

    void flush() {
      if (id != null && id!.isNotEmpty) {
        profiles.add(
          DeviceProfile(id: id!, name: name ?? id!, oem: oem, tag: tag),
        );
      }
      id = null;
      name = null;
      oem = null;
      tag = null;
    }

    for (final line in const LineSplitter().convert(stdout)) {
      final trimmed = line.trim();
      final idMatch = _idPattern.firstMatch(trimmed);
      if (idMatch != null) {
        flush();
        id = idMatch.group(1);
        continue;
      }
      if (id == null) continue;

      final value = _fieldValue(trimmed);
      if (trimmed.startsWith('Name')) {
        name = value;
      } else if (trimmed.startsWith('OEM')) {
        oem = value;
      } else if (trimmed.startsWith('Tag')) {
        tag = value;
      }
    }
    flush();

    return profiles;
  }

  /// Creates an AVD from an already-installed system image.
  ///
  /// [deviceProfileId] is passed whenever there is one, and not only for
  /// looks: without `-d`, `avdmanager` asks on stdin whether to build a custom
  /// hardware profile. Stdin is closed as well, so a future prompt cannot
  /// wedge the call either.
  Future<DeviceCommandResult> createAvd({
    required String name,
    required String packagePath,
    String? deviceProfileId,
    bool replaceExisting = false,
  }) async {
    final invalid = describeInvalidName(name);
    if (invalid != null) return DeviceCommandResult.failure(error: invalid);

    final arguments = buildCreateArguments(
      name: name,
      packagePath: packagePath,
      deviceProfileId: deviceProfileId,
      replaceExisting: replaceExisting,
    );
    logInfo('Creating AVD $name (${arguments.join(' ')})');

    try {
      final result = await runTextWithTimeout(
        arguments,
        timeout: timeout,
        closeStdin: true,
      );
      if (!result.isSuccess) {
        final error = describeFailure(result, 'Could not create $name.');
        logError('Creating AVD $name failed', error);
        return DeviceCommandResult.failure(error: error);
      }

      logSuccess('Created AVD $name');
      return DeviceCommandResult.success(message: 'Created $name.');
    } catch (error) {
      logError('Exception while creating $name', error);
      return DeviceCommandResult.failure(
        error: 'Could not create $name: ${describeError(error)}',
      );
    }
  }

  @visibleForTesting
  List<String> buildCreateArguments({
    required String name,
    required String packagePath,
    String? deviceProfileId,
    bool replaceExisting = false,
  }) => [
    'create',
    'avd',
    '-n',
    name,
    '-k',
    packagePath,
    if (deviceProfileId != null && deviceProfileId.isNotEmpty) ...[
      '-d',
      deviceProfileId,
    ],
    if (replaceExisting) '--force',
  ];

  /// Deletes an AVD, files and all. There is no undo.
  Future<DeviceCommandResult> deleteAvd(String name) async {
    final invalid = describeInvalidName(name);
    if (invalid != null) return DeviceCommandResult.failure(error: invalid);

    logInfo('Deleting AVD $name');
    try {
      final result = await runTextWithTimeout(
        ['delete', 'avd', '-n', name],
        timeout: timeout,
        closeStdin: true,
      );

      if (!result.isSuccess) {
        final error = describeFailure(result, 'Could not delete $name.');
        logError('Deleting AVD $name failed', error);
        return DeviceCommandResult.failure(error: error);
      }

      logSuccess('Deleted AVD $name');
      return DeviceCommandResult.success(message: 'Deleted $name.');
    } catch (error) {
      logError('Exception while deleting $name', error);
      return DeviceCommandResult.failure(
        error: 'Could not delete $name: ${describeError(error)}',
      );
    }
  }

  /// Why [name] cannot be an AVD id, or `null` when it can.
  ///
  /// Checked here rather than left to `avdmanager`, so a typo costs a frame
  /// instead of a JVM start. The alphabet is the one `avdmanager` itself
  /// reports: `Allowed characters are: a-z A-Z 0-9 . _ -`.
  static String? describeInvalidName(String name) {
    if (name.trim().isEmpty) return 'Enter a name for the emulator.';
    if (!_namePattern.hasMatch(name)) {
      return 'Names may only use letters, numbers, dots, underscores and '
          'hyphens — no spaces.';
    }
    return null;
  }

  /// Pulls the useful line out of a failure.
  ///
  /// `avdmanager` reports errors as `Error: <reason>` on stderr and then
  /// prints the exception's message, which is often the literal text `null`.
  /// Passing that through verbatim would be worse than saying nothing.
  @visibleForTesting
  static String describeFailure(ToolCommandResult result, String fallback) {
    final lines = const LineSplitter()
        .convert(result.combinedOutput)
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty && line != 'null')
        .toList();

    final error = lines.where((line) => line.startsWith('Error:')).firstOrNull;
    if (error != null) {
      final detail = error.substring('Error:'.length).trim();
      return detail.isEmpty ? fallback : detail;
    }
    return lines.isEmpty ? fallback : lines.last;
  }

  static String? _fieldValue(String line) {
    final separator = line.indexOf(':');
    if (separator < 0) return null;
    final value = line.substring(separator + 1).trim();
    return value.isEmpty ? null : value;
  }

  static final RegExp _idPattern = RegExp(r'^id:\s*\d+\s+or\s+"(.*)"$');
  static final RegExp _namePattern = RegExp(r'^[A-Za-z0-9._-]+$');
}
