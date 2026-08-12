import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../../../../presentation/theme/app_theme.dart';
import '../../log_controller.dart';

/// Full-width warning shown when live logging dropped and could not be
/// resumed automatically. Offers manual recovery and a fresh tab.
class LiveLoggingInterruptionBanner extends StatelessWidget {
  const LiveLoggingInterruptionBanner({
    super.key,
    required this.controller,
    required this.connected,
    required this.onNewTab,
  });

  final LogController controller;
  final bool connected;
  final VoidCallback onNewTab;

  @override
  Widget build(BuildContext context) {
    final warning = context.eaglyTheme.warningColor;
    final message =
        controller.liveLoggingInterruptionMessage ??
        'Live logging has stopped.';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: warning.withValues(alpha: 0.14),
        border: Border(
          top: BorderSide(color: warning.withValues(alpha: 0.4)),
          bottom: BorderSide(color: warning.withValues(alpha: 0.4)),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, size: 18, color: warning),
          const Gap(10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: warning,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
          const Gap(8),
          TextButton.icon(
            onPressed: connected
                ? () => unawaited(controller.resumeLiveLogging())
                : null,
            icon: const Icon(Icons.restart_alt_rounded, size: 16),
            label: const Text('Restart logging'),
            style: TextButton.styleFrom(foregroundColor: warning),
          ),
          const Gap(4),
          TextButton.icon(
            onPressed: onNewTab,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('New tab'),
            style: TextButton.styleFrom(
              foregroundColor: context.eaglyTheme.inlineNoticeForeground,
            ),
          ),
        ],
      ),
    );
  }
}
