import 'package:flutter/material.dart';

import '../../ui/components/centered_state_message.dart';
import 'components/crash_report_detail.dart';
import 'components/crash_report_list.dart';
import 'crash_report_controller.dart';

/// Crash-report feature pane (iOS). Lists crash reports pulled off the device
/// and shows the selected report's body. [onClose] hides the pane (handled by
/// the device screen).
class CrashReportFeatureView extends StatelessWidget {
  const CrashReportFeatureView({
    super.key,
    required this.controller,
    required this.onClose,
  });

  final CrashReportController controller;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return Container(
          color: theme.colorScheme.surfaceContainer,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(controller: controller, onClose: onClose),
              Expanded(child: _Body(controller: controller)),
            ],
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.controller, required this.onClose});

  final CrashReportController controller;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasSelection = controller.selectedReport != null;

    return Container(
      height: 48,
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          if (hasSelection)
            IconButton(
              tooltip: 'Back to list',
              onPressed: controller.clearSelection,
              icon: const Icon(Icons.arrow_back),
            ),
          Expanded(
            child: Text(
              hasSelection
                  ? controller.selectedReport!.processName
                  : 'Crash reports',
              style: theme.textTheme.titleSmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: controller.isLoading ? null : controller.refresh,
            icon: controller.isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Close crash reports pane',
            onPressed: onClose,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.controller});

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
