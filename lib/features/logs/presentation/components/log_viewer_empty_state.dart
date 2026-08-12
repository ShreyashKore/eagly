import 'package:flutter/material.dart';

import '../../../../presentation/components/centered_state_message.dart';
import '../../log_controller.dart';

/// Placeholder shown when the tab has no logs yet — waiting, ready, or an
/// empty imported file.
class LogViewerEmptyState extends StatelessWidget {
  const LogViewerEmptyState({
    super.key,
    required this.controller,
    required this.deviceDisplayName,
  });

  final LogController controller;
  final String deviceDisplayName;

  @override
  Widget build(BuildContext context) {
    return CenteredStateMessage(
      icon: controller.isImported
          ? Icons.description_outlined
          : controller.isRunning
          ? Icons.sync
          : Icons.play_circle_outline,
      title: controller.isImported
          ? 'Empty log file'
          : controller.isRunning
          ? 'Waiting for logs from $deviceDisplayName'
          : 'Ready to capture logs',
      description: controller.isImported
          ? 'The imported file contained no parseable log entries.'
          : controller.isRunning
          ? 'Keep this tab open while logs stream from the device.'
          : 'Press the play button to start streaming logs for this device.',
    );
  }
}
