import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

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
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: '${log.timestamp} '),
          TextSpan(text: '${log.pid}/${log.tid} '.padLeft(12)),
          TextSpan(
            text: ' ${log.level} ',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              backgroundColor: LogUtils.colorForLevel(log.level),
              color: Colors.black,
            ),
          ),
          TextSpan(text: ' ${log.tag}'),
          TextSpan(text: ' ${log.message}'),
          TextSpan(text: '\n ', style: TextStyle(fontSize: 0, height: 0)),
        ],
      ),
      softWrap: wrapText,
      style: GoogleFonts.notoSansMono(
        color: LogUtils.colorForLevel(log.level),
        height: 1.2,
      ),
    );
  }
}
