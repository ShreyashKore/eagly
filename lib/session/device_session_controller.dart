import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../data/device.dart';
import '../features/apps/apps_controller.dart';
import '../features/crash_reports/crash_report_controller.dart';
import '../features/device_home/device_home_controller.dart';
import '../features/file_manager/file_manager_controller.dart';
import '../features/logs/log_session_manager.dart';
import '../features/mirror/mirror_controller.dart';
import '../features/utilities/utilities_controller.dart';
import '../services/app_breadcrumbs.dart';
import '../services/app_install_service.dart';
import '../services/device_session_repository.dart';
import '../utils/utils.dart';

/// Summary of a drag-and-drop onto a device: which apps were installed, which
/// files were copied (into [copyDirectory]) and any per-item [errors]. Build a
/// user-facing string from [message].
class DropHandlingResult {
  const DropHandlingResult({
    this.installed = const [],
    this.copied = const [],
    this.copyDirectory,
    this.errors = const [],
  });

  final List<String> installed;
  final List<String> copied;
  final String? copyDirectory;
  final List<String> errors;

  /// A single status line summarising the drop, or `null` when nothing
  /// happened (e.g. an empty drop).
  String? get message {
    final parts = <String>[];
    if (installed.isNotEmpty) {
      parts.add(
        installed.length == 1
            ? 'Installed ${installed.single}.'
            : 'Installed ${installed.length} apps.',
      );
    }
    if (copied.isNotEmpty) {
      final where = copyDirectory == null ? '' : ' to $copyDirectory';
      parts.add(
        copied.length == 1
            ? 'Copied ${copied.single}$where.'
            : 'Copied ${copied.length} files$where.',
      );
    }
    parts.addAll(errors);
    return parts.isEmpty ? null : parts.join(' ');
  }
}

/// Owns everything for a single device session: the live [Device] + its
/// connectivity, the [DeviceSessionRepository], and (lazily) the per-feature
/// controllers. It does not own feature state — that lives in the feature
/// controllers.
class DeviceSessionController extends ChangeNotifier {
  DeviceSessionController({
    required Device device,
    DeviceSessionRepository? service,
  }) : this._(device: device, service: service);

  /// Creates the device-less "Imported Logs" workspace session: a session that
  /// hosts only imported log tabs (no live capture, mirror, files, etc.). It is
  /// backed by a synthetic, never-connected [device].
  DeviceSessionController.importedWorkspace({
    required Device device,
    DeviceSessionRepository? service,
  }) : this._(device: device, service: service, isImportedWorkspace: true);

  DeviceSessionController._({
    required Device device,
    DeviceSessionRepository? service,
    this.isImportedWorkspace = false,
  }) : _device = device,
       service = service ?? DeviceSessionRepository(device: device) {
    this.service.sessionLabel = device.id;
  }

  /// True for the synthetic workspace that only shows imported log files.
  final bool isImportedWorkspace;

  Device _device;
  final DeviceSessionRepository service;

  LogSessionManager? _logSessionManager;
  MirrorController? _mirrorController;
  CrashReportController? _crashReportController;
  FileManagerController? _fileManagerController;
  DeviceHomeController? _homeController;
  AppsController? _appsController;
  UtilitiesController? _utilitiesController;

  bool _homeOpen = true;
  bool _logsOpen = false;
  bool _mirrorOpen = false;
  bool _crashReportsOpen = false;
  bool _filesOpen = false;
  bool _appsOpen = false;
  bool _utilitiesOpen = false;
  bool _activated = false;
  bool _disposed = false;

  String get id => _device.id;
  Device get device => _device;
  DevicePlatform get platform => _device.platform;
  bool get isConnected => _device.isConnected;
  bool get isMirrorOpen => _mirrorOpen;
  bool get isCrashReportsOpen => _crashReportsOpen;
  bool get isFilesOpen => _filesOpen;
  bool get isAppsOpen => _appsOpen;
  bool get isUtilitiesOpen => _utilitiesOpen;
  bool get isLogsOpen => _logsOpen;
  bool get isHomeOpen => _homeOpen;
  bool get isActivated => _activated;

  /// Closing a pane must never leave nothing selected — fall back to Home
  /// when it would otherwise be the last one standing.
  void _ensureSelection() {
    if (!_homeOpen &&
        !_logsOpen &&
        !_mirrorOpen &&
        !_crashReportsOpen &&
        !_filesOpen &&
        !_appsOpen &&
        !_utilitiesOpen) {
      _homeOpen = true;
    }
  }

  /// Whether this device can be screen-mirrored right now.
  bool get canMirror => _device is AndroidDevice && _device.isConnected;

  /// Whether crash reports can be read for this device (iOS only).
  bool get canReadCrashReports => _device is IosDevice;

  /// Whether the file manager can browse this device right now (both
  /// platforms, when connected).
  bool get canManageFiles => _device.isConnected;

  /// Whether the Apps feature can list/manage apps right now (both
  /// platforms, when connected).
  bool get canManageApps => _device.isConnected;

  /// Whether the Utilities feature has anything to offer this device. The
  /// pane itself stays usable while disconnected (commands are just disabled),
  /// so this only excludes the device-less imported-logs workspace.
  bool get canRunUtilities => !isImportedWorkspace;

  LogSessionManager get logSessionManager =>
      _logSessionManager ??= isImportedWorkspace
      ? LogSessionManager.importsOnly(session: this)
      : LogSessionManager(session: this);

  MirrorController get mirrorController =>
      _mirrorController ??= MirrorController(this);

  CrashReportController get crashReportController =>
      _crashReportController ??= CrashReportController(this);

  FileManagerController get fileManagerController =>
      _fileManagerController ??= FileManagerController(this);

  DeviceHomeController get homeController =>
      _homeController ??= DeviceHomeController(this);

  AppsController get appsController => _appsController ??= AppsController(this);

  UtilitiesController get utilitiesController =>
      _utilitiesController ??= UtilitiesController(this);

  void openHome() {
    if (_homeOpen) return;
    _homeOpen = true;
    _navigate('Home');
    _notify();
  }

  void closeHome() {
    if (!_homeOpen) return;
    _homeOpen = false;
    _ensureSelection();
    _notify();
  }

  void toggleHome() => _homeOpen ? closeHome() : openHome();

  /// Home and the feature workspace are two mutually-exclusive *views* over
  /// state that both stay alive underneath. Opening a feature pane switches
  /// the view to the workspace and marks the pane open, but never touches the
  /// open/closed flags of the other panes — so returning to Home and back
  /// restores whatever combination of panes was showing before.
  void openLogs() {
    final viewChanged = _homeOpen || !_logsOpen;
    _logsOpen = true;
    _homeOpen = false;
    if (viewChanged) {
      _navigate('Logs');
      _notify();
    }
  }

  void closeLogs() {
    if (!_logsOpen) return;
    _logsOpen = false;
    _ensureSelection();
    _notify();
  }

  /// While Home is showing, tapping a pane's rail item always reveals the
  /// workspace (opening the pane if it wasn't already); it only closes the
  /// pane when the workspace is already the active view.
  void toggleLogs() => _logsOpen && !_homeOpen ? closeLogs() : openLogs();

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
    AppBreadcrumbs.action(
      'Opened device tab for ${device.displayName}',
      category: 'navigation.device_tab',
      data: {'platform': platform.name, 'deviceId': id},
    );
    logSessionManager.activateFirst();
    _notify();
  }

  void openMirror() {
    final viewChanged = _homeOpen || !_mirrorOpen;
    _mirrorOpen = true;
    _homeOpen = false;
    if (viewChanged) {
      _navigate('Mirror');
      _notify();
    }
    if (canMirror) {
      mirrorController.show();
    }
  }

  void closeMirror() {
    if (!_mirrorOpen) return;
    _mirrorOpen = false;
    _ensureSelection();
    _notify();
  }

  void toggleMirror() =>
      _mirrorOpen && !_homeOpen ? closeMirror() : openMirror();

  void openCrashReports() {
    final viewChanged = _homeOpen || !_crashReportsOpen;
    _crashReportsOpen = true;
    _homeOpen = false;
    if (viewChanged) {
      _navigate('Crash Reports');
      _notify();
    }
    if (canReadCrashReports) {
      unawaited(crashReportController.ensureLoaded());
    }
  }

  void closeCrashReports() {
    if (!_crashReportsOpen) return;
    _crashReportsOpen = false;
    _ensureSelection();
    _notify();
  }

  void toggleCrashReports() => _crashReportsOpen && !_homeOpen
      ? closeCrashReports()
      : openCrashReports();

  void openFiles() {
    final viewChanged = _homeOpen || !_filesOpen;
    _filesOpen = true;
    _homeOpen = false;
    if (viewChanged) {
      _navigate('Files');
      _notify();
    }
    unawaited(fileManagerController.ensureLoaded());
  }

  void closeFiles() {
    if (!_filesOpen) return;
    _filesOpen = false;
    _ensureSelection();
    _notify();
  }

  void toggleFiles() => _filesOpen && !_homeOpen ? closeFiles() : openFiles();

  void openApps() {
    final viewChanged = _homeOpen || !_appsOpen;
    _appsOpen = true;
    _homeOpen = false;
    if (viewChanged) {
      _navigate('Apps');
      _notify();
    }
    unawaited(appsController.ensureLoaded());
  }

  void closeApps() {
    if (!_appsOpen) return;
    _appsOpen = false;
    _ensureSelection();
    _notify();
  }

  void toggleApps() => _appsOpen && !_homeOpen ? closeApps() : openApps();

  void openUtilities() {
    final viewChanged = _homeOpen || !_utilitiesOpen;
    _utilitiesOpen = true;
    _homeOpen = false;
    if (viewChanged) {
      _navigate('Utilities');
      _notify();
    }
  }

  void closeUtilities() {
    if (!_utilitiesOpen) return;
    _utilitiesOpen = false;
    _ensureSelection();
    _notify();
  }

  void toggleUtilities() =>
      _utilitiesOpen && !_homeOpen ? closeUtilities() : openUtilities();

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
    AppBreadcrumbs.action(
      'Installing $fileName on ${device.displayName}',
      category: 'install',
      data: {'file': fileName, 'deviceId': id},
    );
    _notify();

    try {
      await AppInstallService.rememberDialogDirectoryFromPath(normalizedPath);
      final result = await service.installApp(filePath: normalizedPath);
      if (_disposed) {
        return AppInstallResult.cancelled();
      }
      if (!result.isSuccess) {
        AppBreadcrumbs.action(
          'Install failed for $fileName',
          category: 'install',
          level: SentryLevel.error,
          data: {'file': fileName, 'error': result.error ?? 'unknown'},
        );
        return AppInstallResult.failure(
          fileName: fileName,
          device: device,
          error:
              'Failed to install $fileName on ${device.displayName}: ${result.error ?? 'Unknown error.'}',
        );
      }

      AppBreadcrumbs.action(
        'Installed $fileName on ${device.displayName}',
        category: 'install',
      );
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

  // ── Drag-and-drop (device-level) ─────────────────────────────────────────
  bool _isHandlingDrop = false;

  /// True while a dropped batch is being installed/copied.
  bool get isHandlingDrop => _isHandlingDrop;

  /// Handles files dropped onto this device's screen. Installable binaries that
  /// match this device (APK on Android; IPA/.app on iOS) are installed; every
  /// other file is copied into the device's drop directory. Installables for
  /// the *other* platform are rejected rather than copied as plain data. Mixed
  /// drops are handled item by item. Returns `null` when busy or nothing was
  /// dropped; otherwise a [DropHandlingResult] to surface.
  Future<DropHandlingResult?> handleDroppedPaths(Iterable<String> paths) async {
    if (_isHandlingDrop) return null;
    final normalizedPaths = paths
        .map((path) => path.trim())
        .where((path) => path.isNotEmpty)
        .toList(growable: false);
    if (normalizedPaths.isEmpty) return null;
    if (!isConnected) {
      return DropHandlingResult(
        errors: ['Reconnect ${device.displayName} before dropping files.'],
      );
    }

    final toInstall = <String>[];
    final toCopy = <String>[];
    final errors = <String>[];
    for (final path in normalizedPaths) {
      final installablePlatform = AppInstallService.inferSupportedPlatform(
        path,
      );
      if (installablePlatform == null) {
        toCopy.add(path);
      } else if (installablePlatform == platform) {
        toInstall.add(path);
      } else {
        errors.add(
          '${extractFileName(path)} can\'t be installed on '
          '${device.displayName} — it needs a '
          '${AppInstallService.supportedFormatLabelFor(device)}.',
        );
      }
    }

    AppBreadcrumbs.action(
      'Files dropped on ${device.displayName}',
      category: 'drag_drop',
      data: {
        'toInstall': toInstall.length,
        'toCopy': toCopy.length,
        'rejected': errors.length,
      },
    );
    _isHandlingDrop = true;
    _notify();
    final installed = <String>[];
    try {
      // Installs run through the device-level guard one at a time.
      for (final path in toInstall) {
        final result = await installAppFromPath(path);
        if (_disposed) return null;
        if (result.isSuccess) {
          installed.add(result.fileName ?? extractFileName(path));
        } else if (!result.cancelled) {
          errors.add(
            result.error ?? 'Failed to install ${extractFileName(path)}.',
          );
        }
      }

      final copyResult = toCopy.isEmpty
          ? null
          : await fileManagerController.copyExternalFiles(toCopy);
      if (_disposed) return null;
      if (copyResult != null) errors.addAll(copyResult.errors);

      return DropHandlingResult(
        installed: installed,
        copied: copyResult?.copied ?? const [],
        copyDirectory: copyResult?.directory,
        errors: errors,
      );
    } finally {
      _isHandlingDrop = false;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Records a pane switch within this device's workspace as a Sentry
  /// navigation breadcrumb.
  void _navigate(String pane) {
    AppBreadcrumbs.navigation(
      from: device.displayName,
      to: '$pane (${device.displayName})',
      category: 'navigation.pane',
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _logSessionManager?.dispose();
    _mirrorController?.dispose();
    _crashReportController?.dispose();
    _fileManagerController?.dispose();
    _homeController?.dispose();
    _appsController?.dispose();
    _utilitiesController?.dispose();
    unawaited(service.dispose());
    super.dispose();
  }
}
