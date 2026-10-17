import 'package:flutter/material.dart';

import '../../presentation/components/feature_view.dart';
import '../../presentation/components/overflow_toolbar.dart';
import 'components/body.dart';
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
          ToolbarAction(
            icon: Icons.refresh,
            label: 'Refresh',
            onPressed: controller.isLoading ? null : controller.refresh,
            iconOverride: controller.isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : null,
          ),
        ],
      ),
      body: Body(controller: controller),
    );
  }
}
