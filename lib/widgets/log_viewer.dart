import 'package:flutter/material.dart';

import '../data/log_entry.dart';
import '../utils/log_utils.dart';

class LogViewer extends StatelessWidget {
  final List<LogEntry> logs;
  final ScrollController scrollController;
  final bool wrapText;

  const LogViewer({
    super.key,
    required this.logs,
    required this.scrollController,
    required this.wrapText,
  });

  @override
  Widget build(BuildContext context) {
    final list = ListView.builder(
      controller: scrollController,
      itemCount: logs.length,
      itemBuilder: (_, i) => _buildLogLine(logs[i]),
    );

    return SelectionArea(
      child: Scrollbar(
        controller: scrollController,
        child: wrapText
            ? list
            : SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(width: 3000, child: list),
              ),
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
        color: LogUtils.colorForLevel(log.level),
        height: 1.2,
      ),
    );
  }
}
