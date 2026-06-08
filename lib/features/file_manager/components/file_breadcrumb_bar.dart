import 'package:flutter/material.dart';

import '../file_manager_controller.dart';
import '../services/device_file_system.dart';

/// Clickable path breadcrumb (`/ › sdcard › DCIM`). The leading crumb is the
/// file system root; each subsequent crumb jumps to that ancestor directory.
class FileBreadcrumbBar extends StatelessWidget {
  const FileBreadcrumbBar({super.key, required this.controller});

  final FileManagerController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final segments = posixSegments(controller.currentPath);

    final crumbs = <Widget>[
      _crumb(
        context,
        label: controller.storageLabel,
        icon: Icons.smartphone_outlined,
        path: '/',
        isCurrent: segments.isEmpty,
      ),
    ];

    var accumulated = '';
    for (var i = 0; i < segments.length; i++) {
      accumulated = '$accumulated/${segments[i]}';
      crumbs
        ..add(
          Icon(
            Icons.chevron_right,
            size: 16,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        )
        ..add(
          _crumb(
            context,
            label: segments[i],
            path: accumulated,
            isCurrent: i == segments.length - 1,
          ),
        );
    }

    return Container(
      height: 36,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        reverse: true,
        child: Row(children: crumbs),
      ),
    );
  }

  Widget _crumb(
    BuildContext context, {
    required String label,
    required String path,
    required bool isCurrent,
    IconData? icon,
  }) {
    final theme = Theme.of(context);
    final color = isCurrent
        ? theme.colorScheme.onSurface
        : theme.colorScheme.primary;

    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: isCurrent || controller.isBusy
          ? null
          : () => controller.navigateToBreadcrumb(path),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: color,
                fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
