import 'package:flutter/material.dart';

import '../data/log_entry.dart';
import '../theme/app_theme.dart';

class LogViewerWorksheet extends StatelessWidget {
  const LogViewerWorksheet({
    super.key,
    required this.logs,
    required this.scrollController,
    this.onLogRowTap,
  });

  final List<LogEntry> logs;
  final ScrollController scrollController;
  final VoidCallback? onLogRowTap;

  @override
  Widget build(BuildContext context) {
    final logTheme = context.logViewTheme;
    final headerStyle = logTheme.logHeaderStyle;
    final rowStyle = logTheme.logCompactStyle;

    return SelectionArea(
      child: Column(
        children: [
          Container(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                SizedBox(width: 150, child: Text('Timestamp', style: headerStyle)),
                SizedBox(width: 140, child: Text('PID/Package', style: headerStyle)),
                SizedBox(width: 80, child: Text('TID', style: headerStyle)),
                SizedBox(width: 70, child: Text('Level', style: headerStyle)),
                SizedBox(width: 180, child: Text('Tag', style: headerStyle)),
                Expanded(child: Text('Message', style: headerStyle)),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1),
          Expanded(
            child: ListView.separated(
              controller: scrollController,
              itemCount: logs.length,
              separatorBuilder: (_, _) => Divider(
                height: 1,
                thickness: 1,
                color: Theme.of(context).dividerColor.withValues(alpha: 0.08),
              ),
              itemBuilder: (context, index) {
                final log = logs[index];
                final levelColor = logTheme.logLevelColor(log.level);
                final displayId = log.packageName ?? log.pid;

                return InkWell(
                  onTap: onLogRowTap,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 150,
                          child: Text(log.timestamp, style: rowStyle.copyWith(color: levelColor)),
                        ),
                        SizedBox(
                          width: 140,
                          child: Text(displayId, style: rowStyle.copyWith(color: levelColor)),
                        ),
                        SizedBox(
                          width: 80,
                          child: Text(log.tid, style: rowStyle.copyWith(color: levelColor)),
                        ),
                        SizedBox(
                          width: 70,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: levelColor,
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text(
                                log.level,
                                style: rowStyle.copyWith(
                                  color: logTheme.logBadgeForeground,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 180,
                          child: Text(log.tag, style: rowStyle.copyWith(color: levelColor)),
                        ),
                        Expanded(
                          child: Text(log.message, style: rowStyle.copyWith(color: levelColor)),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
