import 'dart:async';

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
    });
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
            child: SelectionArea(
              child: ListView.builder(
                itemCount: filteredLogs.length,
                itemBuilder: (_, i) {
                  final log = filteredLogs[i];

                  return Text(
                    '${log.timestamp} ${log.pid}/${log.tid} ${log.level} ${log.tag}: ${log.message}',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontFamilyFallback: <String>["Courier"],
                      color: _colorForLevel(log.level),
                    ),
                  );
                },
              ),
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
