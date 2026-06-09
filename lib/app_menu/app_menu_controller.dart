import 'package:flutter/foundation.dart';

import '../session/device_session_controller.dart';
import '../session/device_session_manager.dart';
import '../features/logs/data/models/log_level.dart';
import '../features/logs/log_controller.dart';
import '../features/logs/log_session_manager.dart';
import 'app_menu_state.dart';

/// Drives the desktop menu bar.
///
/// It listens down the live chain — [DeviceSessionManager] → selected
/// [DeviceSessionController] → its [LogSessionManager] → the active
/// [LogController] — and projects all of that into a single value-equatable
/// [AppMenuState]. Because it only [notifyListeners] when that snapshot
/// actually changes, the menu bar can observe it and rebuild without closing
/// the open native menu on every unrelated state change.
///
/// It also exposes the (context-free) capture/search/filter/view commands the
/// menu and keyboard shortcuts invoke, so command behavior lives in one place.
class AppMenuController extends ChangeNotifier {
  AppMenuController(this._manager) {
    _manager.addListener(_resync);
    _resync();
  }

  final DeviceSessionManager _manager;

  // Currently observed links of the chain (so we can detach when they change).
  DeviceSessionController? _session;
  LogSessionManager? _logManager;
  LogController? _log;

  AppMenuState _state = AppMenuState.empty;
  AppMenuState get state => _state;

  LogController? get _activeLog =>
      _manager.selected?.logSessionManager.selectedTab;

  /// Re-resolves the active chain, re-subscribes if it changed, recomputes the
  /// snapshot, and notifies listeners only when the snapshot differs.
  void _resync() {
    final session = _manager.selected;
    final logManager = session?.logSessionManager;
    final log = logManager?.selectedTab;

    if (!identical(session, _session)) {
      _session?.removeListener(_resync);
      session?.addListener(_resync);
      _session = session;
    }
    if (!identical(logManager, _logManager)) {
      _logManager?.removeListener(_resync);
      logManager?.addListener(_resync);
      _logManager = logManager;
    }
    if (!identical(log, _log)) {
      _log?.removeListener(_resync);
      log?.addListener(_resync);
      _log = log;
    }

    final next = _computeState(session, log);
    if (next != _state) {
      _state = next;
      notifyListeners();
    }
  }

  AppMenuState _computeState(
    DeviceSessionController? session,
    LogController? log,
  ) {
    if (session == null || log == null) return AppMenuState.empty;
    return AppMenuState(
      hasActiveLog: true,
      isImported: log.isImported,
      deviceConnected: session.isConnected,
      logcatState: log.logcatState,
      hasLogs: log.hasLogs,
      isIos: log.isIosLogContext,
      selectedLogLevel: log.selectedLogLevel,
      wrapText: log.wrapText,
      autoScroll: log.autoScroll,
      searchBarVisible: log.searchBarVisible,
    );
  }

  // ── Commands (no-op when there is no active log) ───────────────────────────
  void reloadDevices() => _manager.refreshDevices();
  void startOrRestartLogcat() => _activeLog?.startLogcat();
  void togglePauseResume() => _activeLog?.togglePauseResume();
  void clearLogs() => _activeLog?.clearLogs();
  void scrollToEnd() => _activeLog?.scrollToEnd();
  void activateSearch() => _activeLog?.activateSearchFromSelection();
  void searchNext() => _activeLog?.onSearchNext();
  void searchPrevious() => _activeLog?.onSearchPrev();
  void focusFilter() => _activeLog?.focusFilterInputs();
  void clearFilter() => _activeLog?.clearFilter();
  void setLogLevel(LogLevel level) => _activeLog?.setSelectedLogLevel(level);
  void toggleWrapText() => _activeLog?.toggleWrapText();
  void toggleAutoScroll() => _activeLog?.toggleAutoScroll();

  @override
  void dispose() {
    _manager.removeListener(_resync);
    _session?.removeListener(_resync);
    _logManager?.removeListener(_resync);
    _log?.removeListener(_resync);
    super.dispose();
  }
}
