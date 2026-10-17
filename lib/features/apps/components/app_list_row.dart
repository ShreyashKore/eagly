import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../apps_controller.dart';
import '../data/app_info.dart';
import 'app_tile.dart';

/// One app in the Apps list view: icon, name and badges, the package name,
/// and a details line (version, install and update times) — everything the
/// grid only shows on hover. Tap launches (when supported); secondary-tap
/// opens the context menu.
class AppListRow extends StatelessWidget {
  const AppListRow({
    super.key,
    required this.controller,
    required this.app,
    required this.iconSize,
    required this.onTap,
    required this.onSecondaryTap,
  });

  final AppsController controller;
  final AppInfo app;
  final double iconSize;
  final VoidCallback? onTap;
  final void Function(Offset position) onSecondaryTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final busy = controller.isBusyWith(app.packageName);
    final details = appDetailsLine(app);
    final hasName = app.appName != null && app.appName != app.packageName;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: busy ? null : onTap,
        onSecondaryTapUp: (details) => onSecondaryTap(details.globalPosition),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              AppIconView(controller: controller, app: app, size: iconSize),
              const Gap(12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            app.displayName,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (app.isSystemApp) ...[
                          const Gap(6),
                          const _Badge('System'),
                        ],
                        if (!app.isEnabled) ...[
                          const Gap(6),
                          const _Badge('Disabled'),
                        ],
                      ],
                    ),
                    if (hasName)
                      Text(
                        app.packageName,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: muted,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    if (details.isNotEmpty)
                      Text(
                        details,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: muted,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "v1.2.0 (45) · Installed 12 Mar 2026 · Updated 3h ago", leaving out
/// whatever the platform didn't report.
String appDetailsLine(AppInfo app, {DateTime? now}) {
  final parts = <String>[];
  final version = app.versionName;
  final code = app.versionCode;
  if (version != null && code != null && code != version) {
    parts.add('v$version ($code)');
  } else if (version != null || code != null) {
    parts.add('v${version ?? code}');
  }
  final install = app.installTime;
  final update = app.updateTime;
  if (install != null) parts.add('Installed ${formatAppTime(install, now)}');
  // A never-updated app reports its install time as the update time too.
  if (update != null && update != install) {
    parts.add('Updated ${formatAppTime(update, now)}');
  }
  return parts.join(' · ');
}

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// Relative for the last week ("just now", "5m ago", "3h ago", "2d ago"),
/// a date after that ("12 Mar 2026").
String formatAppTime(DateTime time, [DateTime? now]) {
  final elapsed = (now ?? DateTime.now()).difference(time);
  if (elapsed.isNegative || elapsed.inMinutes < 1) return 'just now';
  if (elapsed.inHours < 1) return '${elapsed.inMinutes}m ago';
  if (elapsed.inDays < 1) return '${elapsed.inHours}h ago';
  if (elapsed.inDays < 7) return '${elapsed.inDays}d ago';
  return '${time.day} ${_months[time.month - 1]} ${time.year}';
}

class _Badge extends StatelessWidget {
  const _Badge(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
