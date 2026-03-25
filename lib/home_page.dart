import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

class Device {
  final String id;
  final String status;

  Device(this.id, this.status);
}

class LogEntry {
  final String timestamp;
  final String pid;
  final String tid;
  final String level;
  final String tag;
  final String message;

  LogEntry({
    required this.timestamp,
    required this.pid,
    required this.tid,
    required this.level,
    required this.tag,
    required this.message,
  });
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final String adbPath = 'adb'; // Replace with bundled path

  List<Device> devices = [];
  Device? selectedDevice;

  List<LogEntry> logs = [];
  final List<LogEntry> buffer = [];

  StreamSubscription? logSub;
  Timer? flushTimer;

  bool isPaused = false;
  String searchQuery = '';
  Set<String> levelFilter = {'E', 'W', 'I', 'D', 'V'};

  @override
  void dispose() {
    logSub?.cancel();
    flushTimer?.cancel();
    super.dispose();
  }

  Future<void> loadDevices() async {
    final result = await Process.run(adbPath, ['devices']);
    final lines = (result.stdout as String).split('\n');

    setState(() {
      devices = lines.skip(1).where((l) => l.trim().isNotEmpty).map((l) {
        final parts = l.split('\t');
        return Device(parts[0], parts.length > 1 ? parts[1] : 'unknown');
      }).toList();
    });
  }

  void startLogcat() async {
    if (selectedDevice == null) return;

    await logSub?.cancel();
    logs.clear();
    buffer.clear();

    final process = await Process.start(adbPath, [
      '-s',
      selectedDevice!.id,
      'logcat',
      '-v',
      'threadtime',
    ]);

    logSub = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          debugPrint('RRRR --> $line');
          if (isPaused) return;
          debugPrint('RRRR aaa --> $line');

          final parsed = parseLog(line);
          debugPrint('RRRR -- Buffer --> $isPaused $parsed');
          if (parsed != null) {
            buffer.add(parsed);
          }
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
    });
  }

  LogEntry? parseLog(String line) {
    final regex = RegExp(
        r'^(\d\d-\d\d\s+\d\d:\d\d:\d\d\.\d+)\s+(\d+)\s+(\d+)\s+([VDIWEF])\s+([^:]+):\s+(.*)'
    );

    final match = regex.firstMatch(line);
    debugPrint('MMMMMM $match');
    if (match == null) return null;

    return LogEntry(
      timestamp: match.group(1)!,
      pid: match.group(2)!,
      tid: match.group(3)!,
      level: match.group(4)!,
      tag: match.group(5)!,
      message: match.group(6)!,
    );
  }

  List<LogEntry> get filteredLogs {
    return logs.where((log) {
      if (!levelFilter.contains(log.level)) return false;

      if (searchQuery.isEmpty) return true;

      return (log.message + log.tag).toLowerCase().contains(
        searchQuery.toLowerCase(),
      );
    }).toList();
  }

  void toggleLevel(String level) {
    setState(() {
      if (levelFilter.contains(level)) {
        levelFilter.remove(level);
      } else {
        levelFilter.add(level);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('Builddd -> $filteredLogs');
    return Scaffold(
      appBar: AppBar(title: const Text('ADB Logcat Pro')),
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
            ],
          ),

          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search logs...',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => searchQuery = v),
            ),
          ),

          Wrap(
            children: ['E', 'W', 'I', 'D', 'V']
                .map(
                  (l) => FilterChip(
                    label: Text(l),
                    selected: levelFilter.contains(l),
                    onSelected: (_) => toggleLevel(l),
                  ),
                )
                .toList(),
          ),

          const Divider(),

          Expanded(
            child: ListView.builder(
              itemCount: filteredLogs.length,
              itemBuilder: (_, i) {
                final log = filteredLogs[i];

                return Text(
                  '${log.timestamp} ${log.pid}/${log.tid} ${log.level} ${log.tag}: ${log.message}',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    color: _colorForLevel(log.level),
                  ),
                );
              },
            ),
          ),
        ],
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
        return Colors.white;
    }
  }
}
