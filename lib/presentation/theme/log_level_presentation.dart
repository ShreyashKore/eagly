import 'package:eagly/presentation/theme/app_theme.dart';
import 'package:flutter/material.dart';

import '../../features/logs/data/models/log_level.dart';

@immutable
class const LogLevelVisualStyle({
  required final IconData icon,
  required final Color color,
}) {
  Color backgroundColor(BuildContext context) {
    return color.withValues(
      alpha: Theme.of(context).brightness == Brightness.dark ? 0.22 : 0.12,
    );
  }
}

LogLevelVisualStyle resolveLogLevelVisualStyle(
  BuildContext context,
  LogLevel level,
) {
  final accentColor = context.eaglyTheme.logLevelColor(level.code);
  final icon = switch (level.code) {
    'fault' => Icons.dangerous_outlined,
    'error' => Icons.error_outline_rounded,
    'warning' => Icons.warning_amber_rounded,
    'default' || 'info' => Icons.info_outline_rounded,
    'debug' => Icons.bug_report_outlined,
    'verbose' => Icons.notes_rounded,
    _ => Icons.help_outline_rounded,
  };
  return LogLevelVisualStyle(icon: icon, color: accentColor);
}

class const LogLevelLabel({
  super.key,
  required final LogLevel level,
  required final bool isIos,
  final String? text,
  final bool includeValueInLabel = false,
  final bool compact = false,
  final bool colorizeText = true,
  final TextStyle? textStyle,
  final MainAxisSize mainAxisSize = MainAxisSize.min,
}) extends StatelessWidget {
  String get _labelText {
    return text ??
        (includeValueInLabel
            ? level.labelWithDisplayCode(isIos: isIos)
            : level.displayLabel(isIos: isIos));
  }

  @override
  Widget build(BuildContext context) {
    final visualStyle = resolveLogLevelVisualStyle(context, level);
    final theme = Theme.of(context);
    final effectiveTextStyle =
        textStyle ?? theme.textTheme.bodyMedium ?? const TextStyle();
    return Row(
      mainAxisSize: mainAxisSize,
      children: [
        Container(
          padding: EdgeInsets.all(compact ? 3 : 4),
          decoration: BoxDecoration(
            color: visualStyle.backgroundColor(context),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Icon(
            visualStyle.icon,
            size: compact ? 12 : 14,
            color: visualStyle.color,
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            _labelText,
            overflow: TextOverflow.ellipsis,
            style: effectiveTextStyle.copyWith(
              color: colorizeText
                  ? visualStyle.color
                  : effectiveTextStyle.color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
