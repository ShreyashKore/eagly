import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/device.dart';
import '../features/crash_reports/crash_report_controller.dart';
import '../features/file_manager/file_manager_controller.dart';
import '../features/logs/log_session_manager.dart';
import '../features/mirror/mirror_controller.dart';
import '../services/app_install_service.dart';
import '../services/device_session_service.dart';
import '../utils/utils.dart';

/// Owns everything for a single device session: the live [Device] + its
/// connectivity, the [DeviceSessionService], and (lazily) the per-feature
/// controllers. It does not own feature state — that lives in the feature
/// controllers.
class DeviceSessionController extends ChangeNotifier {
  DeviceSessionController({
    required Device device,
    DeviceSessionService? service,
  }) : _device = device,
       service = service ?? DeviceSessionService(device: device) {
    this.service.sessionLabel = device.id;
  }

  Device _device;
  final DeviceSessionService service;

  LogSessionManager? _logSessionManager;
  MirrorController? _mirrorController;
  CrashReportController? _crashReportController;
  FileManagerController? _fileManagerController;

  bool _mirrorOpen = false;
  bool _crashReportsOpen = false;
  bool _filesOpen = false;
  bool _activated = false;
  bool _disposed = false;

  String get id => _device.id;
  Device get device => _device;
  DevicePlatform get platform => _device.platform;
  bool get isConnected => _device.isConnected;
  bool get isMirrorOpen => _mirrorOpen;
  bool get isCrashReportsOpen => _crashReportsOpen;
  bool get isFilesOpen => _filesOpen;
  bool get isActivated => _activated;

  /// Whether this device can be screen-mirrored right now.
  bool get canMirror => _device is AndroidDevice && _device.isConnected;

  /// Whether crash reports can be read for this device (iOS only).
  bool get canReadCrashReports => _device is IosDevice;

  /// Whether the file manager can browse this device right now (both
  /// platforms, when connected).
  bool get canManageFiles => _device.isConnected;

  LogSessionManager get logSessionManager =>
      _logSessionManager ??= LogSessionManager(session: this);

  MirrorController get mirrorController =>
      _mirrorController ??= MirrorController(this);

  CrashReportController get crashReportController =>
      _crashReportController ??= CrashReportController(this);

  FileManagerController get fileManagerController =>
      _fileManagerController ??= FileManagerController(this);

  /// Updates the live device snapshot from the repository. Feature controllers
  /// listen to this controller and react to connectivity transitions.
  void updateDevice(Device next) {
    if (_device == next) return;
    _device = next;
    _notify();
  }

  /// Called when this device's tab is first opened/selected. Starts log capture
  /// on first activation (capture-on-open). Idempotent.
  void activate() {
    if (_disposed || _activated) return;
    _activated = true;
    logSessionManager.activateFirst();
    _notify();
  }

  void openMirror() {
    if (!_mirrorOpen) {
      _mirrorOpen = true;
      _notify();
    }
    if (canMirror) {
      mirrorController.show();
    }
  }

  void closeMirror() {
    if (!_mirrorOpen) return;
    _mirrorOpen = false;
    _notify();
  }

  void toggleMirror() => _mirrorOpen ? closeMirror() : openMirror();

  void openCrashReports() {
    if (!_crashReportsOpen) {
      _crashReportsOpen = true;
      _notify();
    }
    if (canReadCrashReports) {
      unawaited(crashReportController.ensureLoaded());
    }
  }

  void closeCrashReports() {
    if (!_crashReportsOpen) return;
    _crashReportsOpen = false;
    _notify();
  }

  void toggleCrashReports() =>
      _crashReportsOpen ? closeCrashReports() : openCrashReports();

  void openFiles() {
    if (!_filesOpen) {
      _filesOpen = true;
      _notify();
    }
    unawaited(fileManagerController.ensureLoaded());
  }

  void closeFiles() {
    if (!_filesOpen) return;
    _filesOpen = false;
    _notify();
  }

  void toggleFiles() => _filesOpen ? closeFiles() : openFiles();

  // ── App install (device-level) ──────────────────────────────────────────
  bool _isInstallingApp = false;
  String? _installingAppName;

  bool get isInstallingApp => _isInstallingApp;
  String? get installingAppName => _installingAppName;

  Future<AppInstallResult> installAppFromPicker() async {
    if (!isConnected) {
      return AppInstallResult.failure(
        device: device,
        error: 'Reconnect the device before installing an app.',
      );
    }

    final selection = await AppInstallService.pickInstallable(device);
    if (_disposed || selection.cancelled) {
      return AppInstallResult.cancelled();
    }
    if (!selection.isSuccess || selection.filePath == null) {
      return AppInstallResult.failure(
        fileName: selection.fileName,
        device: device,
        error: selection.error ?? 'Failed to select an app to install.',
      );
    }

    return installAppFromPath(selection.filePath!);
  }

  Future<AppInstallResult> installDroppedPaths(Iterable<String> paths) async {
    final normalizedPaths = paths
        .map((path) => path.trim())
        .where((path) => path.isNotEmpty)
        .toList(growable: false);
    if (normalizedPaths.isEmpty) {
      return AppInstallResult.failure(error: 'No installable app was dropped.');
    }
    if (normalizedPaths.length > 1) {
      return AppInstallResult.failure(
        error: 'Drop a single app binary at a time.',
      );
    }

    return installAppFromPath(normalizedPaths.single);
  }

  Future<AppInstallResult> installAppFromPath(String path) async {
    final normalizedPath = path.trim();
    final fileName = extractFileName(normalizedPath);
    if (_isInstallingApp) {
      return AppInstallResult.failure(
        fileName: fileName,
        error: 'Another app installation is already in progress.',
      );
    }
    if (!isConnected) {
      return AppInstallResult.failure(
        fileName: fileName,
        device: device,
        error:
            'The device is disconnected. Reconnect it before installing $fileName.',
      );
    }

    final validationError = AppInstallService.validateInstallableForDevice(
      device,
      normalizedPath,
    );
    if (validationError != null) {
      return AppInstallResult.failure(
        fileName: fileName,
        device: device,
        error: validationError,
      );
    }

    _isInstallingApp = true;
    _installingAppName = fileName;
    _notify();

    try {
      await AppInstallService.rememberDialogDirectoryFromPath(normalizedPath);
      final result = await service.installApp(filePath: normalizedPath);
      if (_disposed) {
        return AppInstallResult.cancelled();
      }
      if (!result.isSuccess) {
        return AppInstallResult.failure(
          fileName: fileName,
          device: device,
          error:
              'Failed to install $fileName on ${device.displayName}: ${result.error ?? 'Unknown error.'}',
        );
      }

      return AppInstallResult.success(
        fileName: fileName,
        device: device,
        message: 'Installed $fileName on ${device.displayName}.',
      );
    } finally {
      _isInstallingApp = false;
      _installingAppName = null;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _logSessionManager?.dispose();
    _mirrorController?.dispose();
    _crashReportController?.dispose();
    _fileManagerController?.dispose();
    unawaited(service.dispose());
    super.dispose();
  }
}
