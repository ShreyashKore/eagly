import 'package:flutter/material.dart';

import '../crash_report_controller.dart';

import '../../../utils/timestamp_utils.dart';

class const CrashReportList({
  super.key,
  required final CrashReportController controller,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reports = controller.filteredReports;

    // The pane behind is a coloured box, which would hide the tiles' hover and
    // splash; they paint on this Material instead.
    return Material(
      type: MaterialType.transparency,
      child: ListView.separated(
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
              formatDateTime(report.timestamp, precision: TimePrecision.second),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            trailing: const Icon(Icons.chevron_right, size: 18),
            onTap: () => controller.select(report),
          );
        },
      ),
    );
  }
}
