import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../theme/app_theme.dart';

/// A compact notice — an icon badge, a bold [title], an optional [message]
/// and a few [actions] — shared by the panes that report a dropped device or
/// stream (the logs pane, the device dashboard).
///
/// Its actions sit beside the text only when the text fits on its own line
/// next to them; otherwise they wrap *under* the text, which keeps the whole
/// row. The decision measures the real text and buttons, so it holds at any
/// zoom and message length. Making room for buttons by squeezing the text
/// into a tall, thin column is what made the old banners take so much
/// height.
class const NoticeBanner({
  super.key,
  required final IconData icon,
  required final String title,
  final String? message,

  /// Usually [NoticeButton]s; any widget fits (e.g. a shortcut key cap).
  final List<Widget> actions = const [],

  /// Accent for the badge, tint and border. Defaults to the theme's warning
  /// colour.
  final Color? color,

  /// A full-width strip with top and bottom rules, for the top of a pane,
  /// instead of a rounded card.
  final bool edgeToEdge = false,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = color ?? context.eaglyTheme.warningColor;
    final message = this.message;
    final rule = BorderSide(color: accent.withValues(alpha: 0.35));

    final badge = Container(
      width: context.scaled(26),
      height: context.scaled(26),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, size: 15, color: accent),
    );

    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            height: 1.25,
          ),
        ),
        if (message != null) ...[
          const Gap(1),
          Text(
            message,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.3,
            ),
          ),
        ],
      ],
    );

    final actionBar = Wrap(
      spacing: 6,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: actions,
    );

    return Container(
      width: double.infinity,
      padding: edgeToEdge
          ? const EdgeInsets.fromLTRB(12, 7, 10, 7)
          : const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.1),
        borderRadius: edgeToEdge ? null : BorderRadius.circular(12),
        border: edgeToEdge
            ? Border(top: rule, bottom: rule)
            : Border.fromBorderSide(rule),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          badge,
          const Gap(10),
          Expanded(
            // Lays its children in a row when they fit side by side, and
            // stacks them otherwise.
            child: OverflowBar(
              spacing: 12,
              overflowSpacing: 6,
              alignment: MainAxisAlignment.spaceBetween,
              children: [text, if (actions.isNotEmpty) actionBar],
            ),
          ),
        ],
      ),
    );
  }
}

/// A small button for a [NoticeBanner]: tonal when [primary], plain text
/// otherwise.
class const NoticeButton({
  super.key,
  required final IconData icon,
  required final String label,
  required final VoidCallback? onPressed,
  final bool primary = false,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    const padding = EdgeInsets.symmetric(horizontal: 10);
    final textStyle = Theme.of(context).textTheme.labelMedium;
    final iconWidget = Icon(icon, size: 15);
    final labelWidget = Text(label);

    if (primary) {
      return FilledButton.tonalIcon(
        onPressed: onPressed,
        icon: iconWidget,
        label: labelWidget,
        style: FilledButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: padding,
          textStyle: textStyle,
        ),
      );
    }
    return TextButton.icon(
      onPressed: onPressed,
      icon: iconWidget,
      label: labelWidget,
      style: TextButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: padding,
        textStyle: textStyle,
      ),
    );
  }
}
