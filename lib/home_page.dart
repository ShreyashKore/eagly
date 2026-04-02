import 'dart:async';

import 'package:flutter/material.dart';
import 'dart:io' show Platform;
import 'package:flutter/cupertino.dart';
import 'package:gap/gap.dart';

import 'data/device.dart';
import 'data/log_entry.dart';
import 'services/adb_service.dart';
import 'services/log_file_service.dart';
import 'services/preferences_service.dart';
import 'utils/log_utils.dart';
import 'widgets/action_toolbar.dart';
import 'widgets/filter_bar.dart';
import 'widgets/log_viewer.dart';
import 'widgets/log_viewer_table.dart';
import 'widgets/log_viewer_worksheet.dart';
import 'package:collection/collection.dart';

enum LogcatState { stopped, running, paused }

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
  String _lastSearchQuery = '';
  String _lastLogLevel = 'V';

  int logLinesLimit = PreferencesService.logLinesLimit;
  bool _editingLogLinesLimit = false;
  final TextEditingController _logLinesController = TextEditingController();

  final _dropdownButtonKey = GlobalKey(debugLabel: 'DeviceDropdown');

  @override
  void initState() {
    super.initState();
    init();
  }

  void init() async {
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
    _scrollController.dispose();
    super.dispose();
  }

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
    logs.clear();
    buffer.clear();

    setState(() {
      logcatState = LogcatState.running;
    });

    logSub = adbService.startLogcat(selectedDevice!.id).listen((logEntry) {
      if (logcatState == LogcatState.paused) return;
      buffer.add(logEntry);
    });

    flushTimer?.cancel();
    flushTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (buffer.isEmpty) return;

      setState(() {
        logs.addAll(buffer);
        buffer.clear();

        if (logs.length > logLinesLimit * 1.2) {
          // Delete logs when reach over 120% of the limit to avoid trimming every flush
          final keep = (logLinesLimit).floor();
          logs = logs.sublist(logs.length - keep);
        }
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
        _lastSearchQuery == _appliedSearchQuery &&
        _lastLogLevel == selectedLogLevel) {
      return _cachedFilteredLogs!;
    }

    // Update cache tracking
    _lastLogsLength = logs.length;
    _lastSearchQuery = _appliedSearchQuery;
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

  void clearLogs() {
    setState(() {
      logs.clear();
      buffer.clear();
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
  Widget _buildLogViewer() {
    switch (viewMode) {
      case LogViewMode.text:
        return LogViewer(
          logs: filteredLogs,
          scrollController: _scrollController,
          wrapText: wrapText,
          onLogRowTap: _disableAutoScroll,
        );
      case LogViewMode.dataTable:
        return LogViewerTable(
          logs: filteredLogs,
          scrollController: _scrollController,
          onLogRowTap: _disableAutoScroll,
        );
      case LogViewMode.worksheet:
        return LogViewerWorksheet(
          logs: filteredLogs,
          scrollController: _scrollController,
          onLogRowTap: _disableAutoScroll,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                IconButton(onPressed: loadDevices, icon: Icon(Icons.refresh))
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
                  color: selectedDevice != null ? Colors.green : Colors.grey,
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
                tooltip: logs.isNotEmpty ? 'Clear Logs' : 'No logs to clear',
                onPressed: logs.isNotEmpty ? clearLogs : null,
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
                onScrollToEnd: scrollToEnd,
                viewMode: viewMode,
                onCycleViewMode: () => setState(() {
                  // Cycle through view modes: text -> dataTable -> worksheet -> text
                  viewMode = LogViewMode
                      .values[(viewMode.index + 1) % LogViewMode.values.length];
                  PreferencesService.viewMode = viewMode.index;
                }),
              ),
            ],
          ),
          FilterBar(
            searchQuery: searchQuery,
            onSearchChanged: _onSearchChanged,
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
          Expanded(
            child: Stack(
              children: [
                _buildLogViewer(),
                if (logs.isNotEmpty && filteredLogs.isEmpty)
                  Align(
                    alignment: Alignment.topCenter,
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
                            'No logs match your filter/search, but logs are being generated.',
                            style: const TextStyle(
                              color: Colors.black87,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // Status bar
          Container(
            width: double.infinity,
            color: Theme.of(context).colorScheme.surfaceVariant,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Text(
                  'Logs: ${logs.length}',
                  style: const TextStyle(fontSize: 13),
                ),
                Gap(16),
                Text(
                  'Filtered: ${filteredLogs.length}',
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
                                decorationStyle: TextDecorationStyle.dotted,
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
                                print('submitted');
                                print(
                                  'Submitted log lines limit: ${_logLinesController.text}',
                                );
                                final parsed = int.tryParse(
                                  _logLinesController.text,
                                );
                                if (parsed != null && parsed > 1000) {
                                  _onLogLinesLimitChanged(parsed);
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
    );
  }
}
