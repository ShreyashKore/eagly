import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../theme/app_theme.dart';

/// Low-key explanatory note for a user who looks stuck.
///
/// Pair it with `DelayedReveal` when the hint should only appear once an
/// operation has visibly taken longer than expected.
class const HintNote({
  super.key,
  required final String text,

  /// Optional emphasized first line.
  final String? title,
  final IconData icon = Icons.lightbulb_outline,

  /// Optional control under the text, such as a link to read more.
  final Widget? action,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final eagly = context.eaglyTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: eagly.inlineNoticeBackground,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: eagly.inlineNoticeForeground),
          const Gap(10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null) ...[
                  Text(
                    title!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: eagly.inlineNoticeForeground,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Gap(4),
                ],
                Text(
                  text,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: eagly.inlineNoticeForeground,
                  ),
                ),
                ?action,
              ],
            ),
          ),
        ],
      ),
    );
  }
}
