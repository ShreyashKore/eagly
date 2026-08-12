import 'package:flutter/material.dart';

import '../../presentation/components/centered_state_message.dart';
import '../../presentation/components/feature_view.dart';
import 'components/crash_report_detail.dart';
import 'components/crash_report_list.dart';
import 'crash_report_controller.dart';

/// Crash-report feature pane (iOS). Lists crash reports pulled off the device
/// and shows the selected report's body. [onClose] hides the pane (handled by
/// the device screen).
class CrashReportFeatureView extends FeatureView {
  const CrashReportFeatureView({
    super.key,
    required this.controller,
    required VoidCallback onClose,
  }) : super(onClose: onClose);

  final CrashReportController controller;

  @override
  State<CrashReportFeatureView> createState() => _CrashReportFeatureViewState();
}

class _CrashReportFeatureViewState
    extends FeatureViewState<CrashReportFeatureView> {
  CrashReportController get controller => widget.controller;

  @override
  Listenable get listenable => controller;

  @override
  Widget buildContent(BuildContext context) {
    final selected = controller.selectedReport;

    return FeaturePane(
      header: FeatureViewHeader(
        title: selected?.processName ?? 'Crash reports',
        closeTooltip: 'Close crash reports pane',
        onClose: widget.onClose,
        leading: selected == null
            ? null
            : IconButton(
                tooltip: 'Back to list',
                onPressed: controller.clearSelection,
                icon: const Icon(Icons.arrow_back),
              ),
        actions: [
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
        ],
      ),
      body: _Body(controller: controller),
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
