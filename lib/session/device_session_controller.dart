import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../data/app_install_conflict.dart';
import '../data/device.dart';
import '../features/apps/apps_controller.dart';
import '../features/crash_reports/crash_report_controller.dart';
import '../features/device_home/device_home_controller.dart';
import '../features/file_manager/file_manager_controller.dart';
import '../features/logs/log_session_manager.dart';
import '../features/mirror/ios/ios_mirror_session.dart';
import '../features/mirror/mirror_controller.dart';
import '../features/network/network_controller.dart';
import '../features/terminal/terminal_session_manager.dart';
import '../features/utilities/utilities_controller.dart';
import '../services/app_breadcrumbs.dart';
import '../services/app_install_service.dart';
import '../services/device_session_repository.dart';
import '../utils/utils.dart';
import 'workspace_layout.dart';

/// Summary of a drag-and-drop onto a device: which apps were installed, which
/// files were copied (into [copyDirectory]) and any per-item [errors]. Build a
/// user-facing string from [message].
class const DropHandlingResult({
  final List<String> installed = const [],
  final List<String> copied = const [],
  final String? copyDirectory,
  final List<String> errors = const [],

  /// Installs blocked by the device's copy of the app, left out of [errors]
  /// so the caller can offer to replace each one.
  final List<AppInstallResult> conflicts = const [],
}) {
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
class DeviceSessionController._({
  required var Device _device,
  DeviceSessionRepository? service,
  WorkspaceLayoutMemory? layoutMemory,

  /// True for the synthetic workspace that only shows imported log files.
  final bool isImportedWorkspace = false,
}) extends ChangeNotifier {
  new({
    required Device device,
    DeviceSessionRepository? service,
    WorkspaceLayoutMemory? layoutMemory,
  }) : this._(device: device, service: service, layoutMemory: layoutMemory);

  /// Creates the device-less "Imported Logs" workspace session: a session that
  /// hosts only imported log tabs (no live capture, mirror, files, etc.). It is
  /// backed by a synthetic, never-connected [device].
  new importedWorkspace({
    required Device device,
    DeviceSessionRepository? service,
  }) : this._(device: device, service: service, isImportedWorkspace: true);

  this
    : service = service ?? DeviceSessionRepository(device: _device),
      workspaceLayout = WorkspaceLayout(memory: layoutMemory) {
    this.service.sessionLabel = _device.id;
    workspaceLayout.addListener(_handleWorkspaceChanged);
  }

  final DeviceSessionRepository service;

  /// Which feature panes are open and how they are arranged — split,
  /// stacked or grouped into tabs. The source of truth for every
  /// `is…Open` getter below.
  final WorkspaceLayout workspaceLayout;

  LogSessionManager? _logSessionManager;
  MirrorController? _mirrorController;
  CrashReportController? _crashReportController;
  FileManagerController? _fileManagerController;
  DeviceHomeController? _homeController;
  AppsController? _appsController;
  UtilitiesController? _utilitiesController;
  TerminalSessionManager? _terminalSessionManager;
  NetworkController? _networkController;

  bool _homeOpen = true;
  bool _activated = false;

  /// Set while this controller edits [workspaceLayout] itself, so the
  /// change notifies once, from the verb, rather than also from the layout.
  bool _editingLayout = false;
  bool _disposed = false;

  String get id => _device.id;
  Device get device => _device;
  DevicePlatform get platform => _device.platform;
  bool get isConnected => _device.isConnected;
  bool get isMirrorOpen => isPaneOpen(WorkspacePane.mirror);
  bool get isCrashReportsOpen => isPaneOpen(WorkspacePane.crashReports);
  bool get isFilesOpen => isPaneOpen(WorkspacePane.files);
  bool get isAppsOpen => isPaneOpen(WorkspacePane.apps);
  bool get isUtilitiesOpen => isPaneOpen(WorkspacePane.utilities);
  bool get isTerminalOpen => isPaneOpen(WorkspacePane.terminal);
  bool get isNetworkOpen => isPaneOpen(WorkspacePane.network);
  bool get isLogsOpen => isPaneOpen(WorkspacePane.logs);
  bool get isHomeOpen => _homeOpen;
  bool get isActivated => _activated;

  bool isPaneOpen(WorkspacePane pane) => workspaceLayout.isOpen(pane);

  /// Closing a pane must never leave nothing selected — fall back to Home
  /// when it would otherwise be the last one standing.
  void _ensureSelection() {
    if (!_homeOpen && workspaceLayout.isEmpty) _homeOpen = true;
  }

  /// Whether this device can be screen-mirrored right now.
  bool get canMirror =>
      _device.isConnected &&
      switch (_device) {
        AndroidDevice() => true,
        IosDevice() => IosMirrorSession.isAvailableOnHost,
      };

  /// Why [canMirror] is false, for a disabled Mirror button's tooltip.
  String get mirrorUnavailableReason => !_device.isConnected
      ? 'Connect the device to mirror its screen'
      : 'Mirroring an iPhone needs macOS or the Rust iOS backend';

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

  /// Whether the Terminal feature has a device to send commands to. Like
  /// Utilities the pane stays usable while disconnected, so this only excludes
  /// the device-less imported-logs workspace.
  bool get canUseTerminal => !isImportedWorkspace;

  /// Whether the Network pane is offered. It shows what this device's apps
  /// send, so the device-less imported-logs workspace has none.
  bool get canInspectNetwork => !isImportedWorkspace;

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

  TerminalSessionManager get terminalSessionManager =>
      _terminalSessionManager ??= TerminalSessionManager(session: this);

  NetworkController get networkController =>
      _networkController ??= NetworkController(this);

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

  // ── Feature panes ─────────────────────────────────────────────────────

  /// Home and the feature workspace are two mutually-exclusive *views* over
  /// state that both stay alive underneath. Opening a pane switches the view
  /// to the workspace and puts the pane where it stood last time (or along
  /// the right edge), or brings it to the front of its tab group. It never
  /// touches the other panes, so returning to Home and back restores
  /// whatever arrangement was showing before.
  void openPane(WorkspacePane pane) {
    final viewChanged = _homeOpen || !workspaceLayout.isShown(pane);
    _homeOpen = false;
    _editLayout(() => workspaceLayout.show(pane));
    if (viewChanged) {
      _navigate(pane.label);
      _notify();
    }
    _startPane(pane);
  }

  /// What opening [pane] sets going: loading its data, starting the mirror.
  void _startPane(WorkspacePane pane) {
    switch (pane) {
      case WorkspacePane.mirror:
        if (canMirror) mirrorController.show();
      case WorkspacePane.crashReports:
        if (canReadCrashReports) {
          unawaited(crashReportController.ensureLoaded());
        }
      case WorkspacePane.files:
        unawaited(fileManagerController.ensureLoaded());
      case WorkspacePane.apps:
        unawaited(appsController.ensureLoaded());
      case WorkspacePane.logs:
      case WorkspacePane.utilities:
      case WorkspacePane.terminal:
      case WorkspacePane.network:
        break;
    }
  }

  /// Whether this device can host [pane] at all — what the saved layout is
  /// cut down to. Platform and host decide it, not the connection: a pane
  /// that waits for the device to connect is still hosted.
  bool supportsPane(WorkspacePane pane) => switch (pane) {
    WorkspacePane.crashReports => canReadCrashReports,
    WorkspacePane.mirror => switch (_device) {
      AndroidDevice() => true,
      IosDevice() => IosMirrorSession.isAvailableOnHost,
    },
    WorkspacePane.logs || WorkspacePane.files || WorkspacePane.apps => true,
    WorkspacePane.utilities ||
    WorkspacePane.terminal ||
    WorkspacePane.network => !isImportedWorkspace,
  };

  /// Whether the open panes can be saved as the layout every device opens
  /// with: a real device's workspace with at least one pane open.
  bool get canSaveLayout => !isImportedWorkspace && !workspaceLayout.isEmpty;

  /// Whether the open panes already are the saved layout, as this device
  /// would open it. False when no layout is saved.
  bool get matchesSavedLayout {
    final saved = workspaceLayout.memory.saved;
    return saved != null &&
        workspaceLayout.matchesSaved(saved, _supportedPanes);
  }

  /// Whether there is a saved layout to put the open panes back to.
  bool get canResetLayout =>
      !isImportedWorkspace && workspaceLayout.memory.saved != null;

  /// Puts the open panes back the way the saved layout has them, undoing
  /// every move, resize, open and close since.
  void resetLayout() {
    if (!canResetLayout) return;
    AppBreadcrumbs.action(
      'Reset the pane layout of ${device.displayName}',
      category: 'workspace.layout',
    );
    _openSavedLayout();
    _ensureSelection();
    _notify();
  }

  Set<WorkspacePane> get _supportedPanes => {
    for (final pane in WorkspacePane.values)
      if (supportsPane(pane)) pane,
  };

  /// Opens the saved layout, if there is one, cut down to the panes this
  /// device supports, and shows the workspace instead of Home.
  void _openSavedLayout() {
    final saved = workspaceLayout.memory.saved;
    if (isImportedWorkspace || saved == null) return;
    var opened = const <WorkspacePane>{};
    _editLayout(
      () => opened = workspaceLayout.applySaved(saved, _supportedPanes),
    );
    if (opened.isEmpty) return;
    _homeOpen = false;
    _navigate('Saved layout');
    opened.forEach(_startPane);
  }

  void closePane(WorkspacePane pane) {
    if (!workspaceLayout.isOpen(pane)) return;
    _editLayout(() => workspaceLayout.hide(pane));
    _ensureSelection();
    _notify();
  }

  /// While Home is showing, tapping a pane's rail item always reveals the
  /// workspace (opening the pane if it wasn't already), and a pane hidden
  /// behind another tab of its group is brought to the front. Only a pane
  /// already in view is closed.
  void togglePane(WorkspacePane pane) =>
      !_homeOpen && workspaceLayout.isShown(pane)
      ? closePane(pane)
      : openPane(pane);

  void openLogs() => openPane(WorkspacePane.logs);
  void closeLogs() => closePane(WorkspacePane.logs);
  void toggleLogs() => togglePane(WorkspacePane.logs);

  void openMirror() => openPane(WorkspacePane.mirror);
  void closeMirror() => closePane(WorkspacePane.mirror);
  void toggleMirror() => togglePane(WorkspacePane.mirror);

  void openCrashReports() => openPane(WorkspacePane.crashReports);
  void closeCrashReports() => closePane(WorkspacePane.crashReports);
  void toggleCrashReports() => togglePane(WorkspacePane.crashReports);

  void openFiles() => openPane(WorkspacePane.files);
  void closeFiles() => closePane(WorkspacePane.files);
  void toggleFiles() => togglePane(WorkspacePane.files);

  void openApps() => openPane(WorkspacePane.apps);
  void closeApps() => closePane(WorkspacePane.apps);
  void toggleApps() => togglePane(WorkspacePane.apps);

  void openUtilities() => openPane(WorkspacePane.utilities);
  void closeUtilities() => closePane(WorkspacePane.utilities);
  void toggleUtilities() => togglePane(WorkspacePane.utilities);

  void openTerminal() => openPane(WorkspacePane.terminal);
  void closeTerminal() => closePane(WorkspacePane.terminal);
  void toggleTerminal() => togglePane(WorkspacePane.terminal);

  void openNetwork() => openPane(WorkspacePane.network);
  void closeNetwork() => closePane(WorkspacePane.network);
  void toggleNetwork() => togglePane(WorkspacePane.network);

  void _editLayout(VoidCallback edit) {
    _editingLayout = true;
    try {
      edit();
    } finally {
      _editingLayout = false;
    }
  }

  /// Edits made in the workspace itself — a tab's close button, a strip's
  /// "Close all" — reach the session only through the layout.
  void _handleWorkspaceChanged() {
    if (_editingLayout) return;
    _ensureSelection();
    _notify();
  }

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
    _openSavedLayout();
    _notify();
  }

  // ── App install (device-level) ──────────────────────────────────────────
  bool _isInstallingApp = false;
  String? _installingAppName;
  DateTime? _installStartedAt;

  bool get isInstallingApp => _isInstallingApp;
  String? get installingAppName => _installingAppName;

  /// When the running install began — kept here rather than in the progress
  /// banner so its elapsed time survives switching device tabs.
  DateTime? get installStartedAt => _installStartedAt;

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

  Future<AppInstallResult> installAppFromPath(String path) =>
      _installAppFromPath(path);

  /// Installs [path] after uninstalling the device's copy that [conflict]
  /// says blocks it — which deletes that app's data, so only call this once
  /// the user has agreed to that.
  Future<AppInstallResult> forceInstallAppFromPath(
    String path,
    AppInstallConflict conflict,
  ) => _installAppFromPath(path, replacing: conflict);

  Future<AppInstallResult> _installAppFromPath(
    String path, {
    AppInstallConflict? replacing,
  }) async {
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
    _installStartedAt = DateTime.now();
    AppBreadcrumbs.action(
      'Installing $fileName on ${device.displayName}',
      category: 'install',
      data: {'file': fileName, 'deviceId': id},
    );
    _notify();

    try {
      await AppInstallService.rememberDialogDirectoryFromPath(normalizedPath);
      if (replacing != null) {
        AppBreadcrumbs.action(
          'Uninstalling ${replacing.packageName} to replace it',
          category: 'install',
          data: {'file': fileName, 'reason': replacing.kind.name},
        );
        final uninstall = await service.uninstallApp(replacing.packageName);
        if (_disposed) return AppInstallResult.cancelled();
        if (!uninstall.isSuccess) {
          return AppInstallResult.failure(
            fileName: fileName,
            device: device,
            error:
                'Could not uninstall ${replacing.packageName} from '
                '${device.displayName}, so $fileName was not installed: '
                '${uninstall.error}',
          );
        }
      }
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
          filePath: normalizedPath,
          conflict: result.installConflict,
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
      _installStartedAt = null;
      _notify();
    }
  }

  // ── Drag-and-drop (device-level) ─────────────────────────────────────────
  bool _isHandlingDrop = false;

  /// True while a dropped batch is being installed/copied.
  bool get isHandlingDrop => _isHandlingDrop;

  /// Handles files dropped onto this device. Installable binaries that match
  /// this device (APK on Android; IPA/.app on iOS) are installed unless
  /// [installApps] is false, in which case they are copied like any other
  /// file. Everything else is copied into [copyDirectory], or the device's
  /// drop directory when none is given.
  ///
  /// Installables for the *other* platform are rejected on a plain drop onto
  /// the device, but copied when [copyDirectory] is given — the user aimed at
  /// a folder, so they asked for a file, not an install. Mixed drops are
  /// handled item by item. Returns `null` when busy or nothing was dropped;
  /// otherwise a [DropHandlingResult] to surface.
  Future<DropHandlingResult?> handleDroppedPaths(
    Iterable<String> paths, {
    String? copyDirectory,
    bool installApps = true,
  }) async {
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
        (installApps ? toInstall : toCopy).add(path);
      } else if (copyDirectory != null) {
        toCopy.add(path);
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
    final conflicts = <AppInstallResult>[];
    try {
      // Installs run through the device-level guard one at a time.
      for (final path in toInstall) {
        final result = await installAppFromPath(path);
        if (_disposed) return null;
        if (result.isSuccess) {
          installed.add(result.fileName ?? extractFileName(path));
        } else if (result.conflict != null) {
          conflicts.add(result);
        } else if (!result.cancelled) {
          errors.add(
            result.error ?? 'Failed to install ${extractFileName(path)}.',
          );
        }
      }

      final copyResult = toCopy.isEmpty
          ? null
          : await fileManagerController.copyExternalFiles(
              toCopy,
              directory: copyDirectory,
            );
      if (_disposed) return null;
      if (copyResult != null) errors.addAll(copyResult.errors);

      return DropHandlingResult(
        installed: installed,
        copied: copyResult?.copied ?? const [],
        copyDirectory: copyResult?.directory,
        errors: errors,
        conflicts: conflicts,
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
    _terminalSessionManager?.dispose();
    _networkController?.dispose();
    workspaceLayout
      ..removeListener(_handleWorkspaceChanged)
      ..dispose();
    unawaited(service.dispose());
    super.dispose();
  }
}
