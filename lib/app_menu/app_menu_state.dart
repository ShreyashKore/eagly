import '../features/logs/data/models/log_level.dart';
import '../features/logs/log_controller.dart' show LogcatState;

/// An immutable snapshot of exactly the state the desktop menu bar cares about.
///
/// [AppMenuController] recomputes this from the active device/log and notifies
/// listeners **only when this snapshot actually changes** (it has value
/// equality). That lets the menu bar rebuild — and stay reactive to app state —
/// without closing the open native menu on every unrelated notification.
class const AppMenuState({
  required final bool hasActiveLog,
  required final bool isImported,
  required final bool deviceConnected,
  required final LogcatState logcatState,
  required final bool hasLogs,
  required final bool isIos,
  required final LogLevel? selectedLogLevel,
  required final bool wrapText,
  required final bool autoScroll,
  required final bool searchBarVisible,
  required final bool canSaveLayout,
  required final bool hasSavedLayout,
}) {
  /// State when no device is selected (Home screen / no active log tab).
  /// Home can still clear a [hasSavedLayout].
  const new idle({bool hasSavedLayout = false})
    : this(
        hasActiveLog: false,
        isImported: false,
        deviceConnected: false,
        logcatState: LogcatState.stopped,
        hasLogs: false,
        isIos: false,
        selectedLogLevel: null,
        wrapText: false,
        autoScroll: false,
        searchBarVisible: false,
        canSaveLayout: false,
        hasSavedLayout: hasSavedLayout,
      );

  static const empty = AppMenuState.idle();

  bool get isRunning => logcatState != LogcatState.stopped;
  bool get isPaused => logcatState == LogcatState.paused;

  // ── Per-command availability (the single source of "is this enabled") ──────
  /// Capture controls only apply to a connected, live (non-imported) tab.
  bool get canCapture => hasActiveLog && !isImported && deviceConnected;
  bool get canPauseResume => hasActiveLog && !isImported && isRunning;
  bool get canClear => hasActiveLog && !isImported && hasLogs;
  bool get canInstallApp => deviceConnected;
  bool get canExport => hasActiveLog && hasLogs;

  /// Search/filter/scroll/level act on whatever log tab is showing, including
  /// imported ones.
  bool get canInteractWithLog => hasActiveLog;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppMenuState &&
          other.hasActiveLog == hasActiveLog &&
          other.isImported == isImported &&
          other.deviceConnected == deviceConnected &&
          other.logcatState == logcatState &&
          other.hasLogs == hasLogs &&
          other.isIos == isIos &&
          other.selectedLogLevel == selectedLogLevel &&
          other.wrapText == wrapText &&
          other.autoScroll == autoScroll &&
          other.searchBarVisible == searchBarVisible &&
          other.canSaveLayout == canSaveLayout &&
          other.hasSavedLayout == hasSavedLayout;

  @override
  int get hashCode => Object.hash(
    hasActiveLog,
    isImported,
    deviceConnected,
    logcatState,
    hasLogs,
    isIos,
    selectedLogLevel,
    wrapText,
    autoScroll,
    searchBarVisible,
    canSaveLayout,
    hasSavedLayout,
  );
}
