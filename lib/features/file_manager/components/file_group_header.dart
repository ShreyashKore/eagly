import 'package:flutter/material.dart';

import '../../../presentation/theme/app_theme.dart';
import '../data/file_view_options.dart';
import '../file_manager_controller.dart';

/// A group's title row in a grouped listing — label, item count and a
/// chevron. Clicking it folds the group away or back.
class const FileGroupHeader({
  super.key,
  required final FileManagerController controller,
  required final FileGroup group,
  final EdgeInsetsGeometry padding = const EdgeInsets.symmetric(horizontal: 12),
}) extends StatelessWidget {
  static double heightOf(BuildContext context) => context.scaled(30);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.eaglyTheme;
    final collapsed = controller.isGroupCollapsed(group);
    final count = group.entries.length;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        mouseCursor: SystemMouseCursors.click,
        onTap: () => controller.toggleGroupCollapsed(group),
        child: Container(
          height: heightOf(context),
          padding: padding,
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
          ),
          child: Row(
            children: [
              AnimatedRotation(
                turns: collapsed ? -0.25 : 0,
                duration: const Duration(milliseconds: 150),
                child: Icon(
                  Icons.expand_more,
                  size: 16,
                  color: tokens.secondaryTextColor,
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  group.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$count',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: tokens.tertiaryTextColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
