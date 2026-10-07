import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/device.dart';
import '../../services/app_icon_cache.dart';
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
  AppsController(super.session, {AppIconCache? iconCache})
    : _iconStore = iconCache ?? AppIconCache.instance;

  static const int _maxConcurrentIconFetches = 4;

  /// Maximum consecutive failed fetches before an app's icon is left alone for
  /// the rest of the session (its cached icon, if any, keeps showing).
  static const int _maxIconRetries = 5;

  /// Backoff base: how long to wait after a failed icon fetch before retrying,
  /// doubled per consecutive failure up to [iconRetryMaxDelay].
  @visibleForTesting
  static Duration iconRetryBaseDelay = const Duration(seconds: 2);

  /// Upper bound on the per-app retry backoff, so low-end devices aren't
  /// hammered by a stuck package.
  @visibleForTesting
  static Duration iconRetryMaxDelay = const Duration(minutes: 2);

  AppLoadState loadState = AppLoadState.idle;
  String? error;
  List<AppInfo> _apps = const [];
  String _searchText = '';
  bool _showSystemApps = false;
  double paneWidth = 420;

  bool _busy = false;
  String? busyLabel;
  final Set<String> _busyPackages = {};

  /// Persistent, cross-device icon store injected so tests can substitute a
  /// fake instead of touching the real filesystem.
  final AppIconCache _iconStore;

  /// Best-known icon bytes per package (fresh fetch or disk cache). Absence
  /// means "no icon yet" — the tile then shows its fallback initial.
  final Map<String, Uint8List> _iconCache = {};

  /// Packages whose disk-cached icon has been requested at least once, so we
  /// only hit the disk once per package per session.
  final Set<String> _iconDiskChecked = {};

  /// Signature (version + recency) we've successfully fetched per package, so
  /// an unchanged app isn't re-fetched within a session.
  final Map<String, String> _iconFetchedSignature = {};

  /// Packages still awaiting a successful fetch this session → the signature
  /// we want. Covers queued, in-flight and backoff-waiting retries.
  final Map<String, String> _iconPending = {};

  /// Packages currently being fetched (holding a concurrency slot).
  final Set<String> _iconInFlight = {};

  /// Consecutive fetch failures per package (drives exponential backoff).
  final Map<String, int> _iconFailures = {};

  /// Packages waiting for a free fetch slot.
  final List<String> _iconQueue = [];

  /// Backoff timers per package, so [dispose] can cancel them.
  final Map<String, Timer> _iconRetryTimers = {};

  /// Recency (epoch ms) per package, used to prioritize newly installed or
  /// updated apps ahead of the rest of the icon queue.
  final Map<String, int> _iconRecency = {};

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

  /// Prepares [app]'s icon for display. First surfaces the globally-cached icon
  /// (from disk, if any) so the tile shows it instead of its initial while a
  /// fresh icon is still being fetched, then schedules that fetch. Newly
  /// installed/updated apps (higher recency) jump the fetch queue.
  void ensureIconLoaded(AppInfo app) {
    final package = app.packageName;
    _iconRecency[package] = _recencyOf(app);
    _loadCachedIconOnce(package);
    _requestFreshIcon(package, _signatureOf(app));
  }

  /// Loads the disk-cached icon for [package] at most once per session. Always
  /// asynchronous: even an in-memory hit is surfaced from a microtask so
  /// [notifyListeners] never fires during a widget build.
  void _loadCachedIconOnce(String package) {
    if (_iconDiskChecked.contains(package)) return;
    _iconDiskChecked.add(package);
    unawaited(_loadCachedIconFromDisk(package));
  }

  Future<void> _loadCachedIconFromDisk(String package) async {
    final bytes = await _iconStore.load(package);
    if (_disposed || bytes == null) return;
    // A fresh fetch may have won the race already; don't clobber it with the
    // older cached bytes.
    if (!_iconCache.containsKey(package)) {
      _iconCache[package] = bytes;
      _notify();
    }
  }

  void _requestFreshIcon(String package, String signature) {
    if (_disposed) return;
    if (_iconFetchedSignature[package] == signature) return;
    // Already trying (queued / in-flight / backoff). If the signature changed
    // underneath an in-flight fetch, the next [ensureIconLoaded] self-heals.
    if (_iconPending.containsKey(package)) return;
    _iconPending[package] = signature;
    _iconFailures[package] = 0;
    _scheduleIconAttempt(package);
  }

  /// Starts a fetch for [package] now, parks it behind a backoff timer, or
  /// queues it behind the concurrency cap.
  void _scheduleIconAttempt(String package) {
    if (_disposed) return;
    if (_iconInFlight.contains(package) || _iconQueue.contains(package)) {
      return;
    }
    if (_iconInFlight.length >= _maxConcurrentIconFetches) {
      _iconQueue.add(package);
      return;
    }
    _iconInFlight.add(package);
    unawaited(_fetchIcon(package));
  }

  Future<void> _fetchIcon(String package) async {
    final signature = _iconPending[package];
    Uint8List? bytes;
    try {
      bytes = await service.fetchAppIcon(package);
    } catch (_) {
      bytes = null;
    }
    try {
      if (_disposed) return;
      _iconInFlight.remove(package);
      if (bytes != null) {
        _iconPending.remove(package);
        _iconFailures.remove(package);
        _iconCache[package] = bytes;
        if (signature != null) _iconFetchedSignature[package] = signature;
        unawaited(_iconStore.store(package, bytes));
        _notify();
      } else {
        _handleIconFailure(package);
      }
    } finally {
      if (!_disposed) _drainIconQueue();
    }
  }

  void _handleIconFailure(String package) {
    final failures = (_iconFailures[package] ?? 0) + 1;
    _iconFailures[package] = failures;
    if (failures >= _maxIconRetries) {
      // Give up for the session — the cached icon (if any) keeps showing.
      _iconPending.remove(package);
      _iconRetryTimers.remove(package);
      return;
    }
    final delay = _iconRetryDelay(failures);
    _iconRetryTimers[package] = Timer(delay, () {
      _iconRetryTimers.remove(package);
      _scheduleIconAttempt(package);
    });
  }

  Duration _iconRetryDelay(int failures) {
    var ms = iconRetryBaseDelay.inMilliseconds;
    for (var i = 1; i < failures; i++) {
      ms *= 2;
      if (ms >= iconRetryMaxDelay.inMilliseconds) {
        ms = iconRetryMaxDelay.inMilliseconds;
        break;
      }
    }
    return Duration(milliseconds: ms);
  }

  /// Starts the next-highest-priority queued fetch while slots are free.
  void _drainIconQueue() {
    while (_iconInFlight.length < _maxConcurrentIconFetches &&
        _iconQueue.isNotEmpty) {
      final package = _popHighestPriorityIcon();
      _iconInFlight.add(package);
      unawaited(_fetchIcon(package));
    }
  }

  /// Removes and returns the queued package with the highest recency (most
  /// recently installed/updated), so those icons surface first.
  String _popHighestPriorityIcon() {
    var bestIndex = 0;
    var best = _iconQueue[0];
    var bestRecency = _iconRecency[best] ?? 0;
    for (var i = 1; i < _iconQueue.length; i++) {
      final recency = _iconRecency[_iconQueue[i]] ?? 0;
      if (recency > bestRecency) {
        bestIndex = i;
        best = _iconQueue[i];
        bestRecency = recency;
      }
    }
    return _iconQueue.removeAt(bestIndex);
  }

  /// Epoch ms of the app's most recent activity (last update, else install),
  /// used to order icon fetches. Falls back to 0 when neither is known.
  int _recencyOf(AppInfo app) {
    var recency = 0;
    final install = app.installTime;
    final update = app.updateTime;
    if (install != null) recency = install.millisecondsSinceEpoch;
    if (update != null && update.millisecondsSinceEpoch > recency) {
      recency = update.millisecondsSinceEpoch;
    }
    return recency;
  }

  /// Identifies a specific build of an app so a version bump or reinstall
  /// (changed update time) triggers a fresh icon fetch.
  String _signatureOf(AppInfo app) =>
      '${app.versionCode ?? ''}|${app.versionName ?? ''}|${_recencyOf(app)}';

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
    for (final timer in _iconRetryTimers.values) {
      timer.cancel();
    }
    _iconRetryTimers.clear();
    super.dispose();
  }
}
