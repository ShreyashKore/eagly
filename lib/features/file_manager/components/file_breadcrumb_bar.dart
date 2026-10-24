import 'package:flutter/material.dart';

import '../file_manager_controller.dart';
import '../services/device_file_system.dart';
import '../../../presentation/theme/app_theme.dart';

/// Clickable path breadcrumb (`/ › sdcard › DCIM`). The leading crumb is the
/// file system root; each subsequent crumb jumps to that ancestor directory,
/// with a hover highlight and the pointing hand to say so. [trailing] (the
/// filter and view options) sits at the bar's right end; the crumbs scroll
/// in the space left, keeping the current folder in view.
class const FileBreadcrumbBar({
  super.key,
  required final FileManagerController controller,
  final List<Widget> trailing = const [],
}) extends StatelessWidget {
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
            color: context.eaglyTheme.tertiaryTextColor,
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
      height: context.scaled(36),
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      // The crumbs' hover ink paints on this, above the bar's colour.
      child: Material(
        type: MaterialType.transparency,
        child: Row(
          children: [
            Expanded(
              child: LayoutBuilder(
                // At least as wide as the space, so short paths start at the
                // left; longer ones scroll, ending at the current folder.
                builder: (context, constraints) => SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  reverse: true,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: constraints.maxWidth),
                    child: Row(children: crumbs),
                  ),
                ),
              ),
            ),
            ...trailing,
          ],
        ),
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

    final enabled = !isCurrent && !controller.isBusy;
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      mouseCursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onTap: enabled ? () => controller.navigateToBreadcrumb(path) : null,
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
