import 'dart:io';

import 'package:flutter/foundation.dart';

import 'tool_process_runner.dart';

class IdeviceIdTool extends ToolProcessRunner {
  IdeviceIdTool({super.executablePath}) : super(executableName: 'idevice_id');

  // libimobiledevice prints this (and exits non-zero) when it cannot reach
  // usbmuxd — distinct from "no devices attached", which exits 0 with empty
  // output. On Windows usbmuxd is supplied by Apple Mobile Device Support, not
  // the bundle, so this is the expected state when that service is missing.
  static const String _usbmuxdUnavailableMarker = 'Unable to retrieve device';

  // usbmuxd being unavailable is a steady-state environment condition, not a
  // transient error: the polling refresh would otherwise spam an identical
  // error every few seconds. We latch the state, log the guidance once on the
  // way in, and stay quiet until a later success clears it.
  bool _usbmuxdUnavailable = false;

  /// Whether the last poll failed because usbmuxd (the muxd socket these tools
  /// connect to) was unreachable. On Windows that service ships with Apple
  /// Mobile Device Support; the UI uses this to guide the user to install it.
  bool get usbmuxdUnavailable => _usbmuxdUnavailable;

  Future<List<String>> getDeviceIds() async {
    try {
      final result = await runText(['-l']);
      return parseDeviceIds(result);
    } on ProcessException catch (error) {
      logError('ProcessException while listing iOS device ids', error);
      return const [];
    } catch (error) {
      logError('Unexpected error while listing iOS device ids', error);
      return const [];
    }
  }

  @visibleForTesting
  List<String> parseDeviceIds(ToolCommandResult result) {
    if (!result.isSuccess) {
      _reportListFailure(result.combinedOutput);
      return const [];
    }

    _usbmuxdUnavailable = false;
    return result.stdout
        .trim()
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
  }

  void _reportListFailure(String output) {
    if (output.contains(_usbmuxdUnavailableMarker)) {
      // Latch + log only on the transition into the unavailable state.
      if (_usbmuxdUnavailable) return;
      _usbmuxdUnavailable = true;
      logWarning(
        'iOS device detection is unavailable: usbmuxd is not reachable.',
        _usbmuxdSetupHint(),
      );
      return;
    }

    logError('idevice_id -l returned non-zero exit code', output);
  }

  String _usbmuxdSetupHint() {
    if (Platform.isWindows) {
      return 'Connecting iOS devices needs Apple Mobile Device Support, which '
          'provides the usbmuxd service these tools rely on. Install the '
          '"Apple Devices" app from the Microsoft Store (or iTunes), then '
          'reconnect the device.';
    }
    if (Platform.isLinux) {
      return 'The usbmuxd daemon is not running. Install and start the '
          '"usbmuxd" package, then reconnect the device.';
    }
    return 'usbmuxd is not responding. Reconnect the device or restart '
        'usbmuxd, then try again.';
  }
}
