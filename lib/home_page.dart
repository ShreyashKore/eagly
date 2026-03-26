import 'dart:async';

import 'package:flutter/material.dart';

import 'data/device.dart';
import 'data/log_entry.dart';
import 'services/adb_service.dart';
import 'services/log_file_service.dart';
import 'utils/log_utils.dart';
import 'widgets/action_toolbar.dart';
import 'widgets/filter_bar.dart';
import 'widgets/log_viewer.dart';

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

  bool isPaused = false;
  String searchQuery = '';
  String selectedLogLevel = 'V'; // V shows everything, E shows only errors
  bool wrapText = false;
  bool autoScroll = true;

  @override
  void dispose() {
    logSub?.cancel();
    flushTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> loadDevices() async {
    final fetchedDevices = await adbService.getDevices();

    setState(() {
      devices = fetchedDevices;
    });
  }

  void startLogcat() async {
    if (selectedDevice == null) return;

    await logSub?.cancel();
    logs.clear();
    buffer.clear();

    logSub = adbService.startLogcat(selectedDevice!.id).listen((logEntry) {
      if (isPaused) return;
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

  List<LogEntry> get filteredLogs {
    final selectedLevelValue = LogUtils.levelHierarchy[selectedLogLevel] ?? 4;

    return logs.where((log) {
      final logLevelValue = LogUtils.levelHierarchy[log.level] ?? 4;
      if (logLevelValue > selectedLevelValue) return false;

      if (searchQuery.isEmpty) return true;

      return (log.message + log.tag).toLowerCase().contains(
        searchQuery.toLowerCase(),
      );
    }).toList();
  }

  void clearLogs() {
    setState(() {
      logs.clear();
      buffer.clear();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ADB Logcat')),
      body: Column(
        children: [
          Row(
            children: [
              ElevatedButton(
                onPressed: loadDevices,
                child: const Text('Load Devices'),
              ),
              const SizedBox(width: 10),
              DropdownButton<Device>(
                hint: const Text('Select Device'),
                value: selectedDevice,
                items: devices
                    .map((d) => DropdownMenuItem(
                          value: d,
                          child: Text('${d.id} (${d.status})'),
                        ))
                    .toList(),
                onChanged: (d) => setState(() => selectedDevice = d),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                onPressed: startLogcat,
                child: const Text('Start'),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                onPressed: () => setState(() => isPaused = !isPaused),
                child: Text(isPaused ? 'Resume' : 'Pause'),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                onPressed: clearLogs,
                child: const Text('Clear'),
              ),
              Spacer(),
              ActionToolbar(
                onImport: importLogs,
                onExport: exportLogs,
                wrapText: wrapText,
                onToggleWrap: () => setState(() => wrapText = !wrapText),
                autoScroll: autoScroll,
                onToggleAutoScroll: () => setState(() => autoScroll = !autoScroll),
                onScrollToEnd: scrollToEnd,
              ),
            ],
          ),
          FilterBar(
            searchQuery: searchQuery,
            onSearchChanged: (v) => setState(() => searchQuery = v),
            selectedLogLevel: selectedLogLevel,
            onLogLevelChanged: (level) {
              if (level != null) setState(() => selectedLogLevel = level);
            },
          ),
          const Divider(),
          Expanded(
            child: LogViewer(
              logs: filteredLogs,
              scrollController: _scrollController,
              wrapText: wrapText,
            ),
          ),
        ],
      ),
    );
  }
}
