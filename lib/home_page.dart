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

  final _dropdownButtonKey = GlobalKey(debugLabel: 'DeviceDropdown');

  @override
  void initState() {
    super.initState();
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
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> loadDevices() async {
    final fetchedDevices = await adbService.getDevices();

    if (fetchedDevices.isEmpty) {
      setState(() {
        devices = [];
      });
      return;
    }

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

  void _selectFirstDevice(List<Device> fetchedDevices) {
    // 1. If logging is already in progress and device is already selected, do nothing
    if (isRunning && selectedDevice != null) return;
    setState(() {
      selectedDevice = fetchedDevices.first;
    });
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

        if (logs.length > 10000) {
          logs = logs.sublist(logs.length - 8000);
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
      appBar: AppBar(title: const Text('ADB Logcat')),
      body: Column(
        children: [
          Row(
            children: [
              Gap(8),
              FilledButton(
                onPressed: loadDevices,
                child: const Text('Load Devices'),
              ),
              const SizedBox(width: 10),
              DropdownButton<Device>(
                key: _dropdownButtonKey,
                hint: const Text('Select Device'),
                value: devices.firstWhereOrNull((d) => d.id == selectedDevice?.id),
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
          const Divider(),
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
                const SizedBox(width: 16),
                Text(
                  'Filtered: ${filteredLogs.length}',
                  style: const TextStyle(fontSize: 13),
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
