import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gap/gap.dart';

import 'data/device.dart';
import 'data/log_column.dart';
import 'data/log_entry.dart';
import 'services/adb_service.dart';
import 'services/log_file_service.dart';
import 'services/preferences_service.dart';
import 'utils/log_utils.dart';
import 'widgets/action_toolbar.dart';
import 'widgets/filter_bar.dart';
import 'widgets/log_search_bar.dart';
import 'widgets/log_viewer.dart';
import 'widgets/log_viewer_table.dart';
import 'widgets/log_viewer_worksheet.dart';
import 'widgets/scroll_to_end_button.dart';
import 'package:collection/collection.dart';

enum LogcatState { stopped, running, paused }

/// Intent fired by the Ctrl+F / Cmd+F keyboard shortcut.
class _ActivateSearchIntent extends Intent {
  const _ActivateSearchIntent();
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final AdbService adbService = AdbService();
  final ScrollController _scrollController = ScrollController();

  List<Device> devices = [];
  Device? selectedDevice;

  List<LogEntry> logs = [];
  final List<LogEntry> buffer = [];

  StreamSubscription? logSub;
  Timer? flushTimer;
  Timer? _debounceTimer;
  Timer? _devicePollTimer;
  Timer? _memoryRefreshTimer;

  LogcatState logcatState = LogcatState.stopped;
  String searchQuery = '';
  String _appliedSearchQuery = ''; // The actual query used for filtering
  String selectedLogLevel = PreferencesService.selectedLogLevel;
  bool wrapText = PreferencesService.wrapText;
  bool autoScroll = PreferencesService.autoScroll;
  LogViewMode viewMode = LogViewMode.values[PreferencesService.viewMode];

  // Cached filtered logs
  List<LogEntry>? _cachedFilteredLogs;
  int _lastLogsLength = 0;
  String _lastFilterQuery = '';
  String _lastLogLevel = 'V';

  // ── Inline search (the Ctrl+F search bar) ──────────────────────────────
  bool _searchBarVisible = false;

  /// Raw value of the search text field (updates on every keystroke).
  String _inlineSearchQuery = '';

  /// Debounced value — used for actual match computation and highlighting.
  String _appliedInlineSearchQuery = '';
  Timer? _inlineSearchDebounce;
  bool _searchCaseSensitive = false;
  int _searchCurrentMatchIndex = 0;
  Set<String> _hiddenColumns = {};
  final TextEditingController _searchController = TextEditingController();

  // Cache for search match indices so we don't re-scan on every build.
  List<int>? _cachedSearchMatchIndices;
  String _smCacheQuery = '';
  bool _smCacheCaseSensitive = false;
  Set<String> _smCacheHiddenCols = {};
  int _smCacheFilteredLen = -1;

  int logLinesLimit = PreferencesService.logLinesLimit;
  bool _editingLogLinesLimit = false;
  final TextEditingController _logLinesController = TextEditingController();
  int _logsMemoryBytes = 0;
  int _bufferMemoryBytes = 0;
  int _appMemoryBytes = 0;

  final _dropdownButtonKey = GlobalKey(debugLabel: 'DeviceDropdown');

  @override
  void initState() {
    super.initState();
    _hiddenColumns = Set.of(PreferencesService.hiddenColumns);
    init();
  }

  void init() async {
    _refreshAppMemory();
    _memoryRefreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _refreshAppMemory();
    });
    await loadDevices();
    if (devices.isNotEmpty) {
      setState(() {
        selectedDevice = devices.first;
      });
    }
    startLogcat();
  }

  @override
  void dispose() {
    logSub?.cancel();
    flushTimer?.cancel();
    _debounceTimer?.cancel();
    _devicePollTimer?.cancel();
    _memoryRefreshTimer?.cancel();
    _scrollController.dispose();
    _searchController.dispose();
    _inlineSearchDebounce?.cancel();
    super.dispose();
  }

  int _estimateLogEntryBytes(LogEntry log) {
    int stringBytes(String value) => value.length * 2;

    return 128 +
        stringBytes(log.timestamp) +
        stringBytes(log.pid) +
        stringBytes(log.tid) +
        stringBytes(log.level) +
        stringBytes(log.tag) +
        stringBytes(log.message) +
        stringBytes(log.lowercaseSearchable) +
        (log.packageName == null ? 0 : stringBytes(log.packageName!));
  }

  int _estimateLogsBytes(Iterable<LogEntry> entries) {
    var total = 0;
    for (final entry in entries) {
      total += _estimateLogEntryBytes(entry);
    }
    return total;
  }

  void _refreshAppMemory() {
    final rss = ProcessInfo.currentRss;
    if (!mounted || rss == _appMemoryBytes) return;
    setState(() {
      _appMemoryBytes = rss;
    });
  }

  String _formatBytes(int bytes) {
    const units = ['B', 'KB', 'MB', 'GB'];
    var value = bytes.toDouble();
    var unitIndex = 0;

    while (value >= 1024 && unitIndex < units.length - 1) {
      value /= 1024;
      unitIndex++;
    }

    final precision = value >= 100 || unitIndex == 0 ? 0 : 1;
    return '${value.toStringAsFixed(precision)} ${units[unitIndex]}';
  }

  int get _totalLogsMemoryBytes => _logsMemoryBytes + _bufferMemoryBytes;

  Future<void> loadDevices() async {
    final fetchedDevices = await adbService.getDevices();

    if (fetchedDevices.isEmpty) {
      setState(() {
        devices = [];
      });
      _startDevicePolling();
      return;
    }

    _stopDevicePolling();
    setState(() {
      devices = fetchedDevices;
    });
    _selectFirstDevice(fetchedDevices);
    // 2. If single device, select and start logging
    if (fetchedDevices.length == 1) {
      setState(() {
        devices = fetchedDevices;
      });
      startLogcat();
      return;
    }

    // 3. If multiple devices, open dropdown (focus the dropdown)

    // Try to open the dropdown programmatically (not natively supported in Flutter)
    // Instead, show a dialog for device selection
    if (devices.length > 1) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _openDevicesDropdown();
      });
    }
  }

  void _startDevicePolling() {
    if (_devicePollTimer?.isActive ?? false) return;
    _devicePollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      loadDevices();
    });
  }

  void _stopDevicePolling() {
    _devicePollTimer?.cancel();
    _devicePollTimer = null;
  }

  void _selectFirstDevice(List<Device> fetchedDevices) {
    // 1. If logging is already in progress and device is already selected, do nothing
    if (isRunning && selectedDevice != null) return;
    setState(() {
      selectedDevice = fetchedDevices.first;
    });
  }

  void _onLogLinesLimitChanged(int value) {
    setState(() {
      logLinesLimit = value;
      _editingLogLinesLimit = false;
    });
    PreferencesService.logLinesLimit = value;
  }

  Future<void> startLogcat() async {
    if (selectedDevice == null) return;

    await logSub?.cancel();

    setState(() {
      logs.clear();
      buffer.clear();
      _logsMemoryBytes = 0;
      _bufferMemoryBytes = 0;
      _cachedFilteredLogs = null;
      logcatState = LogcatState.running;
    });

    logSub = adbService.startLogcat(selectedDevice!.id).listen((logEntry) {
      if (logcatState == LogcatState.paused) return;
      buffer.add(logEntry);
      _bufferMemoryBytes += _estimateLogEntryBytes(logEntry);
    });

    flushTimer?.cancel();
    flushTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (buffer.isEmpty) return;

      setState(() {
        logs.addAll(buffer);
        _logsMemoryBytes += _bufferMemoryBytes;
        buffer.clear();
        _bufferMemoryBytes = 0;

        if (logs.length > logLinesLimit * 1.2) {
          // Delete logs when reach over 120% of the limit to avoid trimming every flush
          final keep = (logLinesLimit).floor();
          logs = logs.sublist(logs.length - keep);
          _logsMemoryBytes = _estimateLogsBytes(logs);
        }

        _cachedFilteredLogs = null;
      });

      // Auto-scroll to bottom if enabled
      if (autoScroll && _scrollController.hasClients) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 100),
            curve: Curves.easeOut,
          );
        });
      }
    });
  }

  void stopLogcat() {
    logSub?.cancel();
    flushTimer?.cancel();
    setState(() {
      logcatState = LogcatState.stopped;
    });
  }

  void togglePauseResume() {
    setState(() {
      if (logcatState == LogcatState.running) {
        logcatState = LogcatState.paused;
      } else if (logcatState == LogcatState.paused) {
        logcatState = LogcatState.running;
      }
    });
  }

  void _openDevicesDropdown() {
    _dropdownButtonKey.currentContext?.visitChildElements((element) {
      if (element.widget is Semantics) {
        element.visitChildElements((element) {
          if (element.widget is Actions) {
            element.visitChildElements((element) {
              Actions.invoke(element, ActivateIntent());
            });
          }
        });
      }
    });
  }

  bool get isRunning => logcatState != LogcatState.stopped;
  bool get isPaused => logcatState == LogcatState.paused;

  List<LogEntry> get filteredLogs {
    final selectedLevelValue = LogUtils.levelHierarchy[selectedLogLevel] ?? 4;

    // Check if we can use cached result
    if (_cachedFilteredLogs != null &&
        _lastLogsLength == logs.length &&
        _lastFilterQuery == _appliedSearchQuery &&
        _lastLogLevel == selectedLogLevel) {
      return _cachedFilteredLogs!;
    }

    // Update cache tracking
    _lastLogsLength = logs.length;
    _lastFilterQuery = _appliedSearchQuery;
    _lastLogLevel = selectedLogLevel;

    final searchQuery = _appliedSearchQuery.toLowerCase();
    _cachedFilteredLogs = logs.where((log) {
      final logLevelValue = LogUtils.levelHierarchy[log.level] ?? 4;
      if (logLevelValue > selectedLevelValue) return false;

      if (_appliedSearchQuery.isEmpty) return true;

      return log.lowercaseSearchable.contains(searchQuery);
    }).toList();

    return _cachedFilteredLogs!;
  }

  void _onSearchChanged(String value) {
    setState(() {
      searchQuery = value;
    });

    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      setState(() {
        _appliedSearchQuery = value;
        _cachedFilteredLogs = null; // Invalidate cache
      });
    });
  }

  // ── Inline search (Ctrl+F) ────────────────────────────────────────────────

  /// Returns the list of [filteredLogs] indices that contain [_inlineSearchQuery]
  /// in at least one visible column.  Result is cached and only recomputed when
  /// the query, case-sensitivity, visible columns, or filtered-log list change.
  List<int> get _searchMatchIndices {
    final fl = filteredLogs;
    if (_cachedSearchMatchIndices != null &&
        _smCacheQuery == _appliedInlineSearchQuery &&
        _smCacheCaseSensitive == _searchCaseSensitive &&
        _smCacheHiddenCols.length == _hiddenColumns.length &&
        _smCacheHiddenCols.containsAll(_hiddenColumns) &&
        _smCacheFilteredLen == fl.length) {
      return _cachedSearchMatchIndices!;
    }
    _smCacheQuery = _appliedInlineSearchQuery;
    _smCacheCaseSensitive = _searchCaseSensitive;
    _smCacheHiddenCols = Set.of(_hiddenColumns);
    _smCacheFilteredLen = fl.length;
    _cachedSearchMatchIndices = _computeSearchMatches(fl);
    return _cachedSearchMatchIndices!;
  }

  String _logColumnValue(LogEntry log, LogColumn col) => switch (col) {
    LogColumn.timestamp => log.timestamp,
    LogColumn.pid => log.packageName ?? log.pid,
    LogColumn.tid => log.tid,
    LogColumn.level => log.level,
    LogColumn.tag => log.tag,
    LogColumn.message => log.message,
  };

  List<int> _computeSearchMatches(List<LogEntry> logs) {
    if (_appliedInlineSearchQuery.isEmpty) return [];
    final query = _searchCaseSensitive
        ? _appliedInlineSearchQuery
        : _appliedInlineSearchQuery.toLowerCase();
    final visibleCols = LogColumn.values
        .where((c) => !_hiddenColumns.contains(c.name))
        .toList();
    final result = <int>[];
    for (int i = 0; i < logs.length; i++) {
      final log = logs[i];
      for (final col in visibleCols) {
        final text = _searchCaseSensitive
            ? _logColumnValue(log, col)
            : _logColumnValue(log, col).toLowerCase();
        if (text.contains(query)) {
          result.add(i);
          break;
        }
      }
    }
    return result;
  }

  void _toggleSearchBar() {
    _inlineSearchDebounce?.cancel();
    setState(() {
      _searchBarVisible = !_searchBarVisible;
      if (!_searchBarVisible) {
        _inlineSearchQuery = '';
        _appliedInlineSearchQuery = '';
        _searchController.clear();
        _cachedSearchMatchIndices = null;
        _searchCurrentMatchIndex = 0;
      }
    });
  }

  void _onInlineSearchChanged(String value) {
    // Update the raw query immediately (keeps UI responsive during typing).
    setState(() {
      _inlineSearchQuery = value;
      _searchCurrentMatchIndex = 0;
    });

    // Debounce the expensive match computation.
    _inlineSearchDebounce?.cancel();
    _inlineSearchDebounce = Timer(const Duration(milliseconds: 300), () {
      setState(() {
        _appliedInlineSearchQuery = value;
        _cachedSearchMatchIndices = null;
      });
    });
  }

  void _onSearchNext() {
    final matches = _searchMatchIndices;
    if (matches.isEmpty) return;
    setState(() {
      _searchCurrentMatchIndex =
          (_searchCurrentMatchIndex + 1) % matches.length;
    });
  }

  void _onSearchPrev() {
    final matches = _searchMatchIndices;
    if (matches.isEmpty) return;
    setState(() {
      _searchCurrentMatchIndex =
          (_searchCurrentMatchIndex - 1 + matches.length) % matches.length;
    });
  }

  void _onHiddenColumnsChanged(Set<String> cols) {
    setState(() {
      _hiddenColumns = cols;
      _cachedSearchMatchIndices = null;
    });
  }

  void clearLogs() {
    setState(() {
      logs.clear();
      buffer.clear();
      _logsMemoryBytes = 0;
      _bufferMemoryBytes = 0;
      _cachedFilteredLogs = null; // Invalidate cache
    });
  }

  Future<void> exportLogs() async {
    await LogFileService.exportLogs(logs, selectedDevice);
  }

  Future<void> importLogs() async {
    final importedLogs = await LogFileService.importLogs();
    if (importedLogs != null) {
      setState(() {
        logs = importedLogs;
        _logsMemoryBytes = _estimateLogsBytes(logs);
        _bufferMemoryBytes = 0;
        _cachedFilteredLogs = null; // Invalidate cache
      });
    }
  }

  void scrollToEnd() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _disableAutoScroll() {
    if (autoScroll) {
      setState(() {
        autoScroll = false;
      });
      PreferencesService.autoScroll = false;
    }
  }

  /// Builds the appropriate log viewer based on the current view mode
  Widget _buildLogViewer(List<LogEntry> filtered, List<int> matches) {
    final safeIndex = matches.isEmpty
        ? null
        : matches[_searchCurrentMatchIndex.clamp(0, matches.length - 1)];

    switch (viewMode) {
      case LogViewMode.text:
        return LogViewer(
          logs: filtered,
          scrollController: _scrollController,
          wrapText: wrapText,
          onLogRowTap: _disableAutoScroll,
          searchQuery: _appliedInlineSearchQuery,
          caseSensitive: _searchCaseSensitive,
          currentMatchLogIndex:
              _searchBarVisible && _appliedInlineSearchQuery.isNotEmpty
              ? safeIndex
              : null,
          onHiddenColumnsChanged: _onHiddenColumnsChanged,
        );
      case LogViewMode.dataTable:
        return LogViewerTable(
          logs: filtered,
          scrollController: _scrollController,
          onLogRowTap: _disableAutoScroll,
        );
      case LogViewMode.worksheet:
        return LogViewerWorksheet(
          logs: filtered,
          scrollController: _scrollController,
          onLogRowTap: _disableAutoScroll,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.keyF, control: true):
            const _ActivateSearchIntent(),
        SingleActivator(LogicalKeyboardKey.keyF, meta: true):
            const _ActivateSearchIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _ActivateSearchIntent: CallbackAction<_ActivateSearchIntent>(
            onInvoke: (_) {
              _toggleSearchBar();
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('ADB Logcat'),
              scrolledUnderElevation: 0,
              elevation: 0,
              backgroundColor: Colors.white,
            ),
            backgroundColor: Colors.white,
            body: Column(
              children: [
                Row(
                  children: [
                    Gap(8),
                    DropdownButton<Device>(
                      key: _dropdownButtonKey,
                      hint: const Text('Select Device'),
                      value: devices.firstWhereOrNull(
                        (d) => d.id == selectedDevice?.id,
                      ),
                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      mouseCursor: SystemMouseCursors.click,
                      isDense: true,
                      items: devices
                          .map(
                            (d) => DropdownMenuItem(
                              value: d,
                              child: Text('${d.displayName} - ${d.status}'),
                            ),
                          )
                          .toList(),
                      onChanged: (d) => setState(() => selectedDevice = d),
                    ),
                    if (devices.isNotEmpty)
                      IconButton(
                        onPressed: loadDevices,
                        icon: Icon(Icons.refresh),
                      )
                    else ...[
                      Gap(10),
                      FilledButton(
                        onPressed: loadDevices,
                        child: const Text('Load Devices'),
                      ),
                    ],
                    const SizedBox(width: 10),
                    // Start button (play icon)
                    IconButton(
                      icon: Icon(
                        Icons.play_arrow,
                        color: selectedDevice != null
                            ? Colors.green
                            : Colors.grey,
                      ),
                      tooltip: isRunning ? 'Restart' : 'Start',
                      onPressed: selectedDevice == null ? null : startLogcat,
                    ),
                    // Pause/Resume button (pause/play icons)
                    IconButton(
                      icon: Icon(
                        isPaused ? Icons.play_arrow : Icons.pause,
                        color: isRunning ? Colors.orange : Colors.grey,
                      ),
                      tooltip: isRunning
                          ? (isPaused ? 'Resume' : 'Pause')
                          : 'Not running',
                      onPressed: isRunning ? togglePauseResume : null,
                    ),
                    // Clear button
                    IconButton(
                      icon: const Icon(Icons.delete),
                      tooltip: logs.isNotEmpty
                          ? 'Clear Logs'
                          : 'No logs to clear',
                      onPressed: logs.isNotEmpty ? clearLogs : null,
                    ),
                    // Search toggle button
                    IconButton(
                      icon: Icon(
                        Icons.search,
                        color: _searchBarVisible
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                      tooltip: _searchBarVisible
                          ? 'Close search'
                          : 'Search in logs (Ctrl+F / Cmd+F)',
                      onPressed: _toggleSearchBar,
                    ),
                    Spacer(),
                    ActionToolbar(
                      onImport: importLogs,
                      onExport: exportLogs,
                      wrapText: wrapText,
                      onToggleWrap: () => setState(() {
                        wrapText = !wrapText;
                        PreferencesService.wrapText = wrapText;
                      }),
                      autoScroll: autoScroll,
                      onToggleAutoScroll: () => setState(() {
                        autoScroll = !autoScroll;
                        PreferencesService.autoScroll = autoScroll;
                      }),
                      viewMode: viewMode,
                      onCycleViewMode: () => setState(() {
                        // Cycle through view modes: text -> dataTable -> worksheet -> text
                        viewMode =
                            LogViewMode.values[(viewMode.index + 1) %
                                LogViewMode.values.length];
                        PreferencesService.viewMode = viewMode.index;
                      }),
                    ),
                  ],
                ),
                FilterBar(
                  filterQuery: searchQuery,
                  onFilterChanged: _onSearchChanged,
                  selectedLogLevel: selectedLogLevel,
                  onLogLevelChanged: (level) {
                    if (level != null) {
                      setState(() {
                        selectedLogLevel = level;
                        _cachedFilteredLogs = null; // Invalidate cache
                        PreferencesService.selectedLogLevel = level;
                      });
                    }
                  },
                ),
                Builder(
                  builder: (context) {
                    final filtered = filteredLogs;
                    final matches = _searchMatchIndices;
                    return Expanded(
                      child: Stack(
                        children: [
                          _buildLogViewer(filtered, matches),
                          if (logs.isNotEmpty && filtered.isEmpty)
                            Align(
                              alignment: Alignment.center,
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Material(
                                  color: Colors.yellow[100],
                                  borderRadius: BorderRadius.circular(8),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 8,
                                    ),
                                    child: Text(
                                      'No logs match your filter, but logs are being generated.',
                                      style: const TextStyle(
                                        color: Colors.black87,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          // Floating inline search bar — bottom-right corner
                          if (_searchBarVisible)
                            Positioned(
                              top: 24,
                              right: 12,
                              child: LogSearchBar(
                                controller: _searchController,
                                caseSensitive: _searchCaseSensitive,
                                onQueryChanged: _onInlineSearchChanged,
                                onCaseSensitiveChanged: (v) {
                                  _inlineSearchDebounce?.cancel();
                                  setState(() {
                                    _searchCaseSensitive = v;
                                    _appliedInlineSearchQuery =
                                        _inlineSearchQuery;
                                    _cachedSearchMatchIndices = null;
                                    _searchCurrentMatchIndex = 0;
                                  });
                                },
                                onNext: _onSearchNext,
                                onPrevious: _onSearchPrev,
                                onClose: _toggleSearchBar,
                                totalMatches: matches.length,
                                currentMatch: matches.isEmpty
                                    ? 0
                                    : _searchCurrentMatchIndex + 1,
                              ),
                            ),
                          // Floating scroll-to-end button
                          ListenableBuilder(
                            listenable: _scrollController,
                            builder: (context, child) {
                              return ScrollToEndButton(
                                visible:
                                    logs.isNotEmpty &&
                                    (_scrollController.hasClients &&
                                        _scrollController.offset <
                                            (_scrollController
                                                    .position
                                                    .maxScrollExtent -
                                                24)),
                                onPressed: scrollToEnd,
                              );
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
                // Status bar
                Container(
                  width: double.infinity,
                  color: Theme.of(context).colorScheme.surfaceVariant,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  child: Row(
                    children: [
                      Text(
                        'Logs: ${logs.length}',
                        style: const TextStyle(fontSize: 13),
                      ),
                      Gap(16),
                      Text(
                        'Filtered: ${_cachedFilteredLogs?.length ?? filteredLogs.length}',
                        style: const TextStyle(fontSize: 13),
                      ),
                      Gap(16),
                      Text(
                        'App mem: ${_formatBytes(_appMemoryBytes)}',
                        style: const TextStyle(fontSize: 13),
                      ),
                      Gap(16),
                      Text(
                        'Logs mem: ${_formatBytes(_totalLogsMemoryBytes)}',
                        style: const TextStyle(fontSize: 13),
                      ),
                      Gap(16),
                      Container(
                        width: _editingLogLinesLimit ? 200 : null,
                        height: 28,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: _editingLogLinesLimit
                            ? null
                            : BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(4),
                              ),
                        child: !_editingLogLinesLimit
                            ? InkWell(
                                mouseCursor: SystemMouseCursors.click,
                                onTap: () {
                                  setState(() {
                                    _editingLogLinesLimit = true;
                                    _logLinesController.text = logLinesLimit
                                        .toString();
                                  });
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4.0,
                                  ),
                                  child: Text(
                                    'Max lines: $logLinesLimit',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      decoration: TextDecoration.underline,
                                      decorationStyle:
                                          TextDecorationStyle.dotted,
                                      color: Colors.blue,
                                    ),
                                  ),
                                ),
                              )
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IntrinsicWidth(
                                    child: TextField(
                                      onTapOutside: (_) {
                                        setState(() {
                                          _editingLogLinesLimit = false;
                                        });
                                      },
                                      controller: _logLinesController,
                                      autofocus: true,
                                      keyboardType: TextInputType.number,
                                      style: const TextStyle(fontSize: 13),
                                      decoration: InputDecoration(
                                        isDense: true,
                                        contentPadding: EdgeInsets.symmetric(
                                          vertical: 4,
                                          horizontal: 4,
                                        ),
                                        prefixText: "Max lines: ",
                                        border: OutlineInputBorder(),
                                      ),
                                      onSubmitted: (value) {
                                        print('Submitted log lines limit:');
                                        final parsed = int.tryParse(value);
                                        if (parsed != null && parsed > 1000) {
                                          _onLogLinesLimitChanged(parsed);
                                        } else {
                                          setState(() {
                                            _editingLogLinesLimit = false;
                                          });
                                        }
                                      },
                                      onEditingComplete: () {
                                        setState(() {
                                          _editingLogLinesLimit = false;
                                        });
                                      },
                                    ),
                                  ),
                                  IconButton(
                                    visualDensity: VisualDensity.compact,
                                    padding: EdgeInsets.zero,
                                    onPressed: () {
                                      final parsed = int.tryParse(
                                        _logLinesController.text,
                                      );
                                      print(
                                        'Submitted log lines limit: ${_logLinesController.text}',
                                      );
                                      _onLogLinesLimitChanged(parsed!);

                                      if (parsed != null && parsed > 1000) {
                                      } else {
                                        setState(() {
                                          _editingLogLinesLimit = false;
                                        });
                                      }
                                    },
                                    icon: Icon(Icons.check, size: 14),
                                  ),
                                ],
                              ),
                      ),
                      const Spacer(),
                      if (isRunning)
                        Text(
                          'Live',
                          style: TextStyle(
                            color: Colors.green[700],
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      if (isPaused)
                        Text(
                          'Paused',
                          style: TextStyle(
                            color: Colors.orange[700],
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      if (!isRunning)
                        Text(
                          'Stopped',
                          style: TextStyle(
                            color: Colors.red[700],
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
