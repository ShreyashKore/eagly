import 'package:flutter/material.dart';

import '../crash_report_controller.dart';

import '../utils.dart';

class CrashReportList extends StatelessWidget {
  const CrashReportList({super.key, required this.controller});

  final CrashReportController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reports = controller.reports;

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: reports.length,
      separatorBuilder: (_, _) => Divider(
        height: 1,
        thickness: 1,
        color: theme.colorScheme.outlineVariant,
      ),
      itemBuilder: (context, index) {
        final report = reports[index];
        return ListTile(
          dense: true,
          leading: Icon(
            Icons.bug_report_outlined,
            color: theme.colorScheme.error,
          ),
          title: Text(
            report.processName,
            style: theme.textTheme.bodyMedium,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            CrashReportUtils.formatTimestamp(report.timestamp),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          trailing: const Icon(Icons.chevron_right, size: 18),
          onTap: () => controller.select(report),
        );
      },
    );
  }
}
