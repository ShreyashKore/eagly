import 'dart:async';
import 'dart:typed_data';

import '../../data/device.dart';
import '../../session/feature_controller.dart';
import '../../utils/utils.dart';
import '../wireless_connection/data/wireless_debug_models.dart';
import 'data/app_info.dart';

enum AppLoadState { idle, loading, ready, error }

/// Per-device app-management feature. Owns the installed-app inventory,
/// search/system-apps filters, per-app action busy state, and a small
/// concurrency-limited icon cache (icons are fetched lazily, one per app
/// tile, the first time that tile is built).
///
/// Pane *visibility* lives on the owning [DeviceSessionController]; this
/// controller only manages the feature's own data.
class AppsController extends FeatureController {
  AppsController(super.session);

  static const int _maxConcurrentIconFetches = 4;

  AppLoadState loadState = AppLoadState.idle;
  String? error;
  List<AppInfo> _apps = const [];
  String _searchText = '';
  bool _showSystemApps = false;
  double paneWidth = 420;

  bool _busy = false;
  String? busyLabel;
  final Set<String> _busyPackages = {};

  final Map<String, Uint8List?> _iconCache = {};
  final Set<String> _iconRequested = {};
  final List<String> _iconQueue = [];
  int _activeIconFetches = 0;

  bool _disposed = false;
  bool _loadedOnce = false;
  bool _reloadRequested = false;

  bool get isLoading => loadState == AppLoadState.loading;
  bool get isBusy => _busy;
  String get searchText => _searchText;
  bool get showSystemApps => _showSystemApps;

  /// Android exposes system apps via `pm list packages`; iOS's installer
  /// only ever lists user apps, so the toggle is meaningless there.
  bool get canShowSystemApps => device is AndroidDevice;

  /// Whether [launch] works for this device (no bundled iOS tool can launch
  /// an arbitrary app without a mounted developer disk image).
  bool get canLaunchApps => device is AndroidDevice;

  /// Whether force-stop / clear-data / "App info" are available — Android
  /// OS features with no iOS equivalent exposed by libimobiledevice.
  bool get canManageAppState => device is AndroidDevice;

  List<AppInfo> get apps => _apps;

  /// [apps] narrowed by [searchText] (matches display name or package name,
  /// case-insensitive).
  List<AppInfo> get filteredApps {
    final query = _searchText.trim().toLowerCase();
    if (query.isEmpty) return _apps;
    return _apps
        .where(
          (app) =>
              app.displayName.toLowerCase().contains(query) ||
              app.packageName.toLowerCase().contains(query),
        )
        .toList();
  }

  bool isBusyWith(String packageName) => _busyPackages.contains(packageName);
  Uint8List? iconFor(String packageName) => _iconCache[packageName];

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Loads the inventory the first time the pane is shown. Idempotent.
  Future<void> ensureLoaded() async {
    if (_loadedOnce) return;
    await refresh();
  }

  Future<void> refresh() async {
    if (_disposed) return;
    if (!isConnected) {
      loadState = AppLoadState.error;
      error = 'The device is disconnected. Reconnect it to manage apps.';
      _notify();
      return;
    }
    if (isLoading) return;

    _loadedOnce = true;
    loadState = AppLoadState.loading;
    error = null;
    _notify();

    try {
      final result = await service.listApps(includeSystemApps: _showSystemApps);
      if (_disposed) return;
      _apps = result;
      loadState = AppLoadState.ready;
      _notify();
    } catch (err) {
      if (_disposed) return;
      loadState = AppLoadState.error;
      error = describeError(err);
      _notify();
    } finally {
      if (!_disposed && _reloadRequested) {
        _reloadRequested = false;
        unawaited(refresh());
      }
    }
  }

  void setSearchText(String value) {
    if (_searchText == value) return;
    _searchText = value;
    _notify();
  }

  /// Toggling while a load is already in flight can't just fire a second
  /// [refresh] (it would be dropped by the `isLoading` guard above) — so it's
  /// queued and re-run with the latest [_showSystemApps] once the in-flight
  /// load finishes.
  void setShowSystemApps(bool value) {
    if (_showSystemApps == value) return;
    _showSystemApps = value;
    _notify();
    if (isLoading) {
      _reloadRequested = true;
    } else {
      unawaited(refresh());
    }
  }

  void setPaneWidth(double width) {
    final clamped = width.clamp(320.0, 900.0);
    if (clamped == paneWidth) return;
    paneWidth = clamped;
    _notify();
  }

  // ── Actions ────────────────────────────────────────────────────────────

  Future<String?> uninstall(AppInfo app) {
    return _runAction(
      app,
      label: 'Uninstalling ${app.displayName}…',
      action: () async {
        final result = await service.uninstallApp(app.packageName);
        if (result.isSuccess) {
          _apps = _apps
              .where((candidate) => candidate.packageName != app.packageName)
              .toList();
        }
        return result;
      },
    );
  }

  Future<String?> launch(AppInfo app) {
    return _runAction(
      app,
      label: 'Opening ${app.displayName}…',
      action: () => service.launchApp(app.packageName),
    );
  }

  Future<String?> forceStop(AppInfo app) {
    return _runAction(
      app,
      label: 'Force-stopping ${app.displayName}…',
      action: () => service.forceStopApp(app.packageName),
    );
  }

  Future<String?> clearData(AppInfo app) {
    return _runAction(
      app,
      label: 'Clearing data for ${app.displayName}…',
      action: () => service.clearAppData(app.packageName),
    );
  }

  Future<void> openAppInfo(AppInfo app) async {
    if (!isConnected) return;
    try {
      await service.openAppInfoSettings(app.packageName);
    } catch (_) {
      // Best-effort — there's no user-facing feedback channel for a settings
      // deep link, so a failure here is silently ignored.
    }
  }

  /// Opens a fresh live log tab pre-filtered to this app's package name and
  /// switches to the Logs pane.
  void viewLogs(AppInfo app) {
    session.logSessionManager.addLiveTab();
    final tab = session.logSessionManager.tabs.last;
    tab.applyPackageFilter(app.packageName);
    session.openLogs();
  }

  /// Runs a per-app mutating [action], tracking busy state for that package
  /// and turning the resulting [DeviceCommandResult] into a user-facing
  /// message for the caller to show as a snackbar.
  Future<String?> _runAction(
    AppInfo app, {
    required String label,
    required Future<DeviceCommandResult> Function() action,
  }) async {
    if (_busyPackages.contains(app.packageName)) return null;
    _busyPackages.add(app.packageName);
    _busy = true;
    busyLabel = label;
    _notify();
    try {
      final result = await action();
      if (_disposed) return null;
      return result.isSuccess
          ? (result.message ?? label)
          : (result.error ?? 'Something went wrong.');
    } catch (err) {
      if (_disposed) return null;
      return describeError(err);
    } finally {
      _busyPackages.remove(app.packageName);
      _busy = _busyPackages.isNotEmpty;
      if (!_busy) busyLabel = null;
      _notify();
    }
  }

  // ── Icons ──────────────────────────────────────────────────────────────

  /// Kicks off a best-effort icon fetch for [packageName] the first time
  /// it's requested (an app tile's first build) — cached for the life of
  /// this controller, with a small concurrency cap so scrolling a long list
  /// doesn't spawn dozens of simultaneous `adb pull`s at once.
  void ensureIconLoaded(String packageName) {
    if (_iconRequested.contains(packageName)) return;
    _iconRequested.add(packageName);
    if (_activeIconFetches >= _maxConcurrentIconFetches) {
      _iconQueue.add(packageName);
      return;
    }
    unawaited(_fetchIcon(packageName));
  }

  Future<void> _fetchIcon(String packageName) async {
    _activeIconFetches++;
    try {
      final bytes = await service.fetchAppIcon(packageName);
      if (_disposed) return;
      _iconCache[packageName] = bytes;
      _notify();
    } catch (_) {
      if (!_disposed) _iconCache[packageName] = null;
    } finally {
      _activeIconFetches--;
      if (!_disposed && _iconQueue.isNotEmpty) {
        final next = _iconQueue.removeAt(0);
        unawaited(_fetchIcon(next));
      }
    }
  }

  @override
  void onDeviceConnected() {
    if (_loadedOnce) unawaited(refresh());
  }

  // Apps already loaded remain visible (read-only) after a disconnect —
  // actions naturally fail via the `isConnected` checks in the repository,
  // so no special handling is needed here.

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
