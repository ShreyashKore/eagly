import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'data/device.dart';
import 'data/log_entry.dart';
import 'services/adb_service.dart';

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
    // Define log level hierarchy: E > W > I > D > V
    const levelHierarchy = {'E': 0, 'W': 1, 'I': 2, 'D': 3, 'V': 4};
    final selectedLevelValue = levelHierarchy[selectedLogLevel] ?? 4;

    return logs.where((log) {
      // Include logs at the selected level or higher priority
      final logLevelValue = levelHierarchy[log.level] ?? 4;
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
    if (logs.isEmpty) return;

    final result = await FilePicker.platform.saveFile(
      dialogTitle: 'Export Logs',
      fileName: 'logcat_export_${DateTime.now().millisecondsSinceEpoch}.json',
      allowedExtensions: ['json'],
      type: FileType.custom,
    );

    if (result == null) return;

    final exportData = {
      'metadata': {
        'device': selectedDevice != null
            ? {
                'serialNumber': selectedDevice!.id,
                'status': selectedDevice!.status,
              }
            : null,
        'exportedAt': DateTime.now().toIso8601String(),
        'totalLogs': logs.length,
      },
      'logcatMessages': logs.map((log) {
        // Parse timestamp string to convert back to seconds/nanos if needed
        final timestampObj = _parseTimestampToSecondsNanos(log.timestamp);

        return {
          'header': {
            'logLevel': _logLevelName(log.level),
            'pid': int.tryParse(log.pid) ?? 0,
            'tid': int.tryParse(log.tid) ?? 0,
            'tag': log.tag,
            'timestamp': timestampObj,
          },
          'message': log.message,
        };
      }).toList(),
    };

    final file = File(result);
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(exportData));
  }

  Map<String, int> _parseTimestampToSecondsNanos(String timestamp) {
    if (timestamp.isEmpty) {
      return {'seconds': 0, 'nanos': 0};
    }

    try {
      // Try to parse format: 2026-03-26 09:59:17.496
      final parts = timestamp.split(' ');
      if (parts.length != 2) {
        return {'seconds': 0, 'nanos': 0};
      }

      final dateParts = parts[0].split('-');
      final timeParts = parts[1].split(':');

      if (dateParts.length != 3 || timeParts.length != 3) {
        return {'seconds': 0, 'nanos': 0};
      }

      final year = int.parse(dateParts[0]);
      final month = int.parse(dateParts[1]);
      final day = int.parse(dateParts[2]);
      final hour = int.parse(timeParts[0]);
      final minute = int.parse(timeParts[1]);

      final secondParts = timeParts[2].split('.');
      final second = int.parse(secondParts[0]);
      final millisecond = secondParts.length > 1 ? int.parse(secondParts[1]) : 0;

      final dateTime = DateTime(year, month, day, hour, minute, second, millisecond);
      final millisecondsSinceEpoch = dateTime.millisecondsSinceEpoch;

      final seconds = millisecondsSinceEpoch ~/ 1000;
      final nanos = (millisecondsSinceEpoch % 1000) * 1000000;

      return {'seconds': seconds, 'nanos': nanos};
    } catch (e) {
      debugPrint('Error parsing timestamp: $e');
      return {'seconds': 0, 'nanos': 0};
    }
  }

  String _logLevelName(String level) {
    switch (level) {
      case 'E':
        return 'ERROR';
      case 'W':
        return 'WARN';
      case 'I':
        return 'INFO';
      case 'D':
        return 'DEBUG';
      case 'V':
        return 'VERBOSE';
      default:
        return 'UNKNOWN';
    }
  }

  String _logLevelFromName(String name) {
    switch (name.toUpperCase()) {
      case 'ERROR':
        return 'E';
      case 'WARN':
        return 'W';
      case 'INFO':
        return 'I';
      case 'DEBUG':
        return 'D';
      case 'VERBOSE':
        return 'V';
      default:
        return 'V';
    }
  }

  Future<void> importLogs() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Import Logcat File',
      type: FileType.any,
    );

    if (result == null || result.files.isEmpty) return;

    final filePath = result.files.first.path;
    if (filePath == null) return;

    try {
      final file = File(filePath);
      final content = await file.readAsString();
      final data = jsonDecode(content) as Map<String, dynamic>;

      final logcatMessages = data['logcatMessages'] as List<dynamic>?;
      if (logcatMessages == null) return;

      final importedLogs = <LogEntry>[];
      for (final msg in logcatMessages) {
        final header = msg['header'] as Map<String, dynamic>?;
        if (header == null) continue;

        final level = _logLevelFromName(header['logLevel']?.toString() ?? 'V');
        final pid = header['pid']?.toString() ?? '0';
        final tid = header['tid']?.toString() ?? '0';
        final tag = header['tag']?.toString() ?? '';

        // Convert timestamp from JSON format
        String timestamp = '';
        final timestampData = header['timestamp'];
        if (timestampData is Map) {
          // Format: {seconds: 1774431614, nanos: 314000000}
          final seconds = timestampData['seconds'] as int? ?? 0;
          final nanos = timestampData['nanos'] as int? ?? 0;
          timestamp = _formatTimestamp(seconds, nanos);
        } else if (timestampData is String) {
          // Already a string, use as-is
          timestamp = timestampData;
        }

        final message = msg['message']?.toString() ?? '';

        importedLogs.add(LogEntry(
          timestamp: timestamp,
          pid: pid,
          tid: tid,
          level: level,
          tag: tag,
          message: message,
        ));
      }

      setState(() {
        logs = importedLogs;
      });
    } catch (e) {
      debugPrint('Error importing logs: $e');
    }
  }

  String _formatTimestamp(int seconds, int nanos) {
    if (seconds == 0) return '';

    final dateTime = DateTime.fromMillisecondsSinceEpoch(
      seconds * 1000 + (nanos ~/ 1000000),
      isUtc: false,
    );

    // Format: 2026-03-26 09:59:17.496
    final year = dateTime.year;
    final month = dateTime.month.toString().padLeft(2, '0');
    final day = dateTime.day.toString().padLeft(2, '0');
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final second = dateTime.second.toString().padLeft(2, '0');
    final millisecond = dateTime.millisecond.toString().padLeft(3, '0');

    return '$year-$month-$day $hour:$minute:$second.$millisecond';
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
    final list = ListView.builder(
      controller: _scrollController,
      itemCount: filteredLogs.length,
      itemBuilder: (_, i) => _buildLogLine(filteredLogs[i]),
    );
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
                    .map(
                      (d) => DropdownMenuItem(
                        value: d,
                        child: Text('${d.id} (${d.status})'),
                      ),
                    )
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
              const Spacer(),
              IconButton(
                onPressed: importLogs,
                icon: const Icon(Icons.file_open),
                tooltip: 'Import Logcat File',
              ),
              IconButton(
                onPressed: exportLogs,
                icon: const Icon(Icons.save),
                tooltip: 'Export Logs',
              ),
              IconButton(
                onPressed: () => setState(() => wrapText = !wrapText),
                icon: Icon(wrapText ? Icons.wrap_text : Icons.notes),
                tooltip: wrapText ? 'Disable Wrap' : 'Enable Wrap',
              ),
              IconButton(
                onPressed: () => setState(() => autoScroll = !autoScroll),
                icon: Icon(autoScroll ? Icons.vertical_align_bottom : Icons.vertical_align_center),
                tooltip: autoScroll ? 'Auto-scroll ON' : 'Auto-scroll OFF',
                color: autoScroll ? Colors.blue : null,
              ),
              IconButton(
                onPressed: scrollToEnd,
                icon: const Icon(Icons.arrow_downward),
                tooltip: 'Scroll to End',
              ),
            ],
          ),

          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: 'Search logs...',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) => setState(() => searchQuery = v),
                  ),
                ),
                const SizedBox(width: 10),
                DropdownButton<String>(
                  value: selectedLogLevel,
                  items: const [
                    DropdownMenuItem(value: 'E', child: Text('Error (E)')),
                    DropdownMenuItem(value: 'W', child: Text('Warning (W)')),
                    DropdownMenuItem(value: 'I', child: Text('Info (I)')),
                    DropdownMenuItem(value: 'D', child: Text('Debug (D)')),
                    DropdownMenuItem(value: 'V', child: Text('Verbose (V)')),
                  ],
                  onChanged: (level) {
                    if (level != null) {
                      setState(() => selectedLogLevel = level);
                    }
                  },
                ),
              ],
            ),
          ),

          const Divider(),


          Expanded(
            child: SelectionArea(
              child: Scrollbar(
                controller: _scrollController,
                child: wrapText
                    ? list
                    : SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                          width: 3000, // Wide enough for long log lines
                          child: list,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogLine(LogEntry log) {
    return Text(
      '${log.timestamp} ${log.pid}/${log.tid} ${log.level} ${log.tag}: ${log.message}',
      softWrap: wrapText,
      style: TextStyle(
        fontFamily: 'monospace',
        fontFamilyFallback: const <String>["Courier"],
        color: _colorForLevel(log.level),
        height: 1.2,
      ),
    );
  }

  Color _colorForLevel(String level) {
    switch (level) {
      case 'E':
        return Colors.red;
      case 'W':
        return Colors.orange;
      case 'I':
        return Colors.green;
      case 'D':
        return Colors.blue;
      default:
        return Colors.grey[400]!;
    }
  }
}
