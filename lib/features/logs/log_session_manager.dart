import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'data/models/log_entry.dart';
import 'services/log_file_service.dart';
import '../../services/preferences_service.dart';
import '../../session/device_session_controller.dart';
import 'log_controller.dart';

/// Manages the ordered list of log tabs (live + imported) for one device
/// session. The first live tab is permanent; additional live or imported tabs
/// can be added and closed freely.
class LogSessionManager extends ChangeNotifier {
  LogSessionManager({required DeviceSessionController session})
    : _session = session,
      _importsOnly = false {
    _tabs.add(_createLiveTab());
  }

  /// Creates a manager with no permanent live tab, for the device-less
  /// "Imported Logs" workspace. Tabs are added via [addImportedEntries]; the
  /// first imported tab becomes permanent.
  LogSessionManager.importsOnly({required DeviceSessionController session})
    : _session = session,
      _importsOnly = true;

  final DeviceSessionController _session;

  /// When true there is no permanent live tab — every tab is an imported file.
  final bool _importsOnly;
  final List<LogController> _tabs = [];
  int _selectedIndex = 0;
  bool _disposed = false;

  List<LogController> get tabs => List.unmodifiable(_tabs);
  int get selectedIndex => _selectedIndex;
  LogController? get selectedTab =>
      _tabs.isEmpty ? null : _tabs[_selectedIndex];

  /// True for the device-less "Imported Logs" workspace, which has no live
  /// capture — new tabs come from importing files, not [addLiveTab].
  bool get isImportsOnly => _importsOnly;

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

  /// Whether the tab at [index] can be closed. In the imports-only workspace
  /// at least one tab is always kept (the first imported file is permanent).
  /// Otherwise imported tabs are always closable and a live tab is closable
  /// when there is more than one live tab.
  bool canClose(int index) {
    if (index < 0 || index >= _tabs.length) return false;
    if (_importsOnly) return _tabs.length > 1;
    if (_tabs[index].isImported) return true;
    return _tabs.where((t) => !t.isImported).length > 1;
  }

  /// Activates the first live tab — called once when the device session is
  /// first selected.
  void activateFirst() {
    if (_tabs.isNotEmpty) _tabs.first.activate();
  }

  /// Opens a new live log tab and immediately starts capture. No-op in the
  /// imports-only workspace, which has no live capture.
  void addLiveTab() {
    if (_disposed || _importsOnly) return;
    final tab = _createLiveTab();
    _tabs.add(tab);
    _selectedIndex = _tabs.length - 1;
    tab.activate();
    _notify();
  }

  /// Parses a log file ([path] re-opens a recent file; otherwise a picker is
  /// shown) and opens the result in a new imported tab. Returns the
  /// [LogImportResult] (may be cancelled).
  Future<LogImportResult> importLog({String? path}) async {
    if (_disposed) return LogImportResult.cancelled();
    final result = await LogFileService.importLogs(path: path);
    if (!result.isSuccess) return result;

    addImportedEntries(result.logs!, result.fileName!);
    return result;
  }

  /// Opens already-parsed [entries] in a new imported tab and selects it.
  void addImportedEntries(List<LogEntry> entries, String fileName) {
    if (_disposed) return;
    final tab = LogController.imported(
      _session,
      initialSettings: PreferencesService.defaultTabSettings,
    );
    tab.loadImportedEntries(entries, fileName);
    _tabs.add(tab);
    _selectedIndex = _tabs.length - 1;
    _notify();
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
