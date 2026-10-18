import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../../../presentation/theme/app_theme.dart';
import '../apps_controller.dart';
import '../data/app_info.dart';
import 'app_tile.dart';

/// One app in the Apps list view: icon, name and badges, the package name,
/// and a details line (version, install and update times) — everything the
/// grid only shows on hover. Tap launches (when supported); secondary-tap
/// opens the context menu.
///
/// The lines step down in emphasis so a scan reads names first: the name at
/// full strength, the package as secondary text, the details and badges as
/// tertiary.
class const AppListRow({
  super.key,
  required final AppsController controller,
  required final AppInfo app,
  required final double iconSize,
  required final VoidCallback? onTap,
  required final void Function(Offset position) onSecondaryTap,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final eaglyTheme = context.eaglyTheme;
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
                          color: eaglyTheme.secondaryTextColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    if (details.isNotEmpty)
                      Text(
                        details,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: eaglyTheme.tertiaryTextColor,
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

/// A quiet tag after the name. Most rows on a device are system apps, so a
/// bordered chip on each one turned the list into a column of boxes; a faint
/// fill is enough to set the word apart from the name.
class const _Badge(final String label) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: theme.colorScheme.onSurface.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: context.eaglyTheme.tertiaryTextColor,
        ),
      ),
    );
  }
}
