import '../features/logs/data/models/log_level.dart';
import '../features/logs/log_controller.dart' show LogcatState;

/// An immutable snapshot of exactly the state the desktop menu bar cares about.
///
/// [AppMenuController] recomputes this from the active device/log and notifies
/// listeners **only when this snapshot actually changes** (it has value
/// equality). That lets the menu bar rebuild — and stay reactive to app state —
/// without closing the open native menu on every unrelated notification.
class AppMenuState {
  const AppMenuState({
    required this.hasActiveLog,
    required this.isImported,
    required this.deviceConnected,
    required this.logcatState,
    required this.hasLogs,
    required this.isIos,
    required this.selectedLogLevel,
    required this.wrapText,
    required this.autoScroll,
    required this.searchBarVisible,
  });

  /// State when no device is selected (Home screen / no active log tab).
  static const empty = AppMenuState(
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
  );

  final bool hasActiveLog;
  final bool isImported;
  final bool deviceConnected;
  final LogcatState logcatState;
  final bool hasLogs;
  final bool isIos;
  final LogLevel? selectedLogLevel;
  final bool wrapText;
  final bool autoScroll;
  final bool searchBarVisible;

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
          other.searchBarVisible == searchBarVisible;

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
  );
}
