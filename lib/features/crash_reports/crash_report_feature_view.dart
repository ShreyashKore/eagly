import 'package:flutter/material.dart';

import '../../presentation/components/app_icon_button.dart';
import '../../presentation/components/feature_view.dart';
import '../../presentation/components/overflow_toolbar.dart';
import 'components/body.dart';
import 'crash_report_controller.dart';

/// Crash-report feature pane (iOS). Lists crash reports pulled off the device
/// and shows the selected report's body. [onClose] hides the pane (handled by
/// the device screen).
class const CrashReportFeatureView({
  super.key,
  required final CrashReportController controller,
  required VoidCallback onClose,
}) extends FeatureView {
  this : super(onClose: onClose);

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
            : AppIconButton(
                tooltip: 'Back to list',
                onPressed: controller.clearSelection,
                icon: Icons.arrow_back,
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
