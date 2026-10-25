import 'package:flutter/material.dart';

import '../../../presentation/components/centered_state_message.dart';
import '../crash_report_controller.dart';
import 'crash_report_detail.dart';
import 'crash_report_list.dart';
import 'crash_report_search_field.dart';

class const Body({super.key, required final CrashReportController controller})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    if (controller.selectedReport != null) {
      return CrashReportDetail(controller: controller);
    }

    switch (controller.loadState) {
      case CrashReportLoadState.idle:
      case CrashReportLoadState.loading:
        return const Center(child: CircularProgressIndicator());
      case CrashReportLoadState.unsupported:
        return CenteredStateMessage(
          icon: Icons.phonelink_off_rounded,
          title: 'Unsupported device',
          description:
              controller.error ??
              'Crash report reading is available for iOS devices.',
        );
      case CrashReportLoadState.error:
        return CenteredStateMessage(
          icon: Icons.error_outline_rounded,
          title: 'Could not read crash reports',
          description: controller.error ?? 'Something went wrong.',
          footer: RetryButton(onPressed: controller.refresh),
        );
      case CrashReportLoadState.ready:
        if (controller.reports.isEmpty) {
          return const CenteredStateMessage(
            icon: Icons.check_circle_outline_rounded,
            title: 'No crash reports',
            description: 'This device has no crash reports to show.',
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CrashReportSearchField(controller: controller),
            Expanded(child: _buildList()),
          ],
        );
    }
  }

  Widget _buildList() {
    if (controller.filteredReports.isNotEmpty) {
      return CrashReportList(controller: controller);
    }
    if (controller.isSearchingContent) {
      return const Center(child: CircularProgressIndicator());
    }
    return const CenteredStateMessage(
      icon: Icons.search_off,
      title: 'No matching crash reports',
      description: 'No report names or contents match. Try a different search.',
    );
  }
}
