import 'data/models/log_entry.dart';
import 'services/log_file_service.dart';
import '../../services/preferences_service.dart';
import '../../session/device_session_controller.dart';
import '../../session/tab_list_manager.dart';
import 'log_controller.dart';

/// Manages the ordered list of log tabs (live + imported) for one device
/// session. The first live tab is permanent; additional live or imported tabs
/// can be added and closed freely.
class LogSessionManager extends TabListManager<LogController> {
  new({required this._session}) : _importsOnly = false {
    appendTab(_createLiveTab(), notify: false);
  }

  /// Creates a manager with no permanent live tab, for the device-less
  /// "Imported Logs" workspace. Tabs are added via [addImportedEntries]; the
  /// first imported tab becomes permanent.
  new importsOnly({required this._session}) : _importsOnly = true;

  final DeviceSessionController _session;

  /// When true there is no permanent live tab — every tab is an imported file.
  final bool _importsOnly;

  LogController? get selectedTab => tabCount == 0 ? null : tabAt(selectedIndex);

  /// True for the device-less "Imported Logs" workspace, which has no live
  /// capture — new tabs come from importing files, not [addLiveTab].
  bool get isImportsOnly => _importsOnly;

  /// Human-readable label for the tab at [index].
  String labelFor(int index) {
    final tab = tabAt(index);
    if (tab.isImported) {
      final name = tab.importedFileName ?? 'Imported';
      final dot = name.lastIndexOf('.');
      return dot > 0 ? name.substring(0, dot) : name;
    }
    // Rank among live-only tabs to decide whether to show a number.
    final liveRank = tabs
        .sublist(0, index + 1)
        .where((t) => !t.isImported)
        .length;
    return liveRank <= 1 ? 'Logs' : 'Logs $liveRank';
  }

  /// Whether the tab at [index] can be closed. In the imports-only workspace
  /// at least one tab is always kept (the first imported file is permanent).
  /// Otherwise imported tabs are always closable and a live tab is closable
  /// when there is more than one live tab.
  @override
  bool canClose(int index) {
    if (index < 0 || index >= tabCount) return false;
    if (_importsOnly) return tabCount > 1;
    if (tabAt(index).isImported) return true;
    return tabs.where((t) => !t.isImported).length > 1;
  }

  /// Activates the first live tab — called once when the device session is
  /// first selected.
  void activateFirst() {
    if (tabCount > 0) tabAt(0).activate();
  }

  /// Opens a new live log tab and immediately starts capture. No-op in the
  /// imports-only workspace, which has no live capture.
  void addLiveTab() {
    if (isDisposed || _importsOnly) return;
    final tab = _createLiveTab();
    appendTab(tab);
    tab.activate();
  }

  /// Parses a log file ([path] re-opens a recent file; otherwise a picker is
  /// shown) and opens the result in a new imported tab. Returns the
  /// [LogImportResult] (may be cancelled).
  Future<LogImportResult> importLog({String? path}) async {
    if (isDisposed) return LogImportResult.cancelled();
    final result = await LogFileService.importLogs(path: path);
    if (!result.isSuccess) return result;

    addImportedEntries(result.logs!, result.fileName!);
    return result;
  }

  /// Opens already-parsed [entries] in a new imported tab and selects it.
  void addImportedEntries(List<LogEntry> entries, String fileName) {
    if (isDisposed) return;
    final tab = LogController.imported(
      _session,
      initialSettings: PreferencesService.defaultTabSettings,
    );
    tab.loadImportedEntries(entries, fileName);
    appendTab(tab);
  }

  LogController _createLiveTab() => LogController(
    _session,
    initialSettings: PreferencesService.defaultTabSettings,
  );
}
