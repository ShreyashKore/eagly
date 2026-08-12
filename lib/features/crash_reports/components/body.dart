import 'package:flutter/material.dart';

import '../../../presentation/components/centered_state_message.dart';
import '../crash_report_controller.dart';
import 'crash_report_detail.dart';
import 'crash_report_list.dart';

class Body extends StatelessWidget {
  const Body({super.key, required this.controller});

  final CrashReportController controller;

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
          footer: FilledButton.icon(
            onPressed: controller.refresh,
            icon: const Icon(Icons.refresh),
            label: const Text('Try again'),
          ),
        );
      case CrashReportLoadState.ready:
        if (controller.reports.isEmpty) {
          return const CenteredStateMessage(
            icon: Icons.check_circle_outline_rounded,
            title: 'No crash reports',
            description: 'This device has no crash reports to show.',
          );
        }
        return CrashReportList(controller: controller);
    }
  }
}
