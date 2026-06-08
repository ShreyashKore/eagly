import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../services/log_file_service.dart';
import '../../services/preferences_service.dart';
import '../../session/device_session_controller.dart';
import 'log_controller.dart';

/// Manages the ordered list of log tabs (live + imported) for one device
/// session. The first live tab is permanent; additional live or imported tabs
/// can be added and closed freely.
class LogSessionManager extends ChangeNotifier {
  LogSessionManager({required DeviceSessionController session})
    : _session = session {
    _tabs.add(_createLiveTab());
  }

  final DeviceSessionController _session;
  final List<LogController> _tabs = [];
  int _selectedIndex = 0;
  bool _disposed = false;

  List<LogController> get tabs => List.unmodifiable(_tabs);
  int get selectedIndex => _selectedIndex;
  LogController? get selectedTab =>
      _tabs.isEmpty ? null : _tabs[_selectedIndex];

  /// Human-readable label for the tab at [index].
  String labelFor(int index) {
    final tab = _tabs[index];
    if (tab.isImported) {
      final name = tab.importedFileName ?? 'Imported';
      final dot = name.lastIndexOf('.');
      return dot > 0 ? name.substring(0, dot) : name;
    }
    // Rank among live-only tabs to decide whether to show a number.
    final liveRank = _tabs
        .sublist(0, index + 1)
        .where((t) => !t.isImported)
        .length;
    return liveRank <= 1 ? 'Logs' : 'Logs $liveRank';
  }

  /// Whether the tab at [index] can be closed. Imported tabs are always
  /// closable; a live tab is closable when there is more than one live tab.
  bool canClose(int index) {
    if (index < 0 || index >= _tabs.length) return false;
    if (_tabs[index].isImported) return true;
    return _tabs.where((t) => !t.isImported).length > 1;
  }

  /// Activates the first live tab — called once when the device session is
  /// first selected.
  void activateFirst() {
    if (_tabs.isNotEmpty) _tabs.first.activate();
  }

  /// Opens a new live log tab and immediately starts capture.
  void addLiveTab() {
    if (_disposed) return;
    final tab = _createLiveTab();
    _tabs.add(tab);
    _selectedIndex = _tabs.length - 1;
    tab.activate();
    _notify();
  }

  /// Shows a file picker, parses the chosen log file, and opens the result in
  /// a new imported tab. Returns the [LogImportResult] (may be cancelled).
  Future<LogImportResult> importLog() async {
    if (_disposed) return LogImportResult.cancelled();
    final result = await LogFileService.importLogs();
    if (!result.isSuccess) return result;

    final tab = LogController.imported(
      _session,
      initialSettings: PreferencesService.defaultTabSettings,
    );
    tab.loadImportedEntries(result.logs!, result.fileName!);
    _tabs.add(tab);
    _selectedIndex = _tabs.length - 1;
    _notify();
    return result;
  }

  void selectTab(int index) {
    if (index == _selectedIndex || index < 0 || index >= _tabs.length) return;
    _selectedIndex = index;
    _notify();
  }

  void closeTab(int index) {
    if (!canClose(index)) return;
    _tabs[index].dispose();
    _tabs.removeAt(index);
    _selectedIndex = _selectedIndex.clamp(0, math.max(0, _tabs.length - 1));
    _notify();
  }

  LogController _createLiveTab() => LogController(
    _session,
    initialSettings: PreferencesService.defaultTabSettings,
  );

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final tab in _tabs) {
      tab.dispose();
    }
    super.dispose();
  }
}
