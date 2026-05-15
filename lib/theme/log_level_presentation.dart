import 'package:flutter/material.dart';

import '../data/log_level.dart';
import 'app_theme.dart';

@immutable
class LogLevelVisualStyle {
  const LogLevelVisualStyle({required this.icon, required this.color});

  final IconData icon;
  final Color color;

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
  final accentColor = context.logViewTheme.logLevelColor(level.code);
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

class LogLevelLabel extends StatelessWidget {
  const LogLevelLabel({
    super.key,
    required this.level,
    required this.isIos,
    this.text,
    this.includeValueInLabel = false,
    this.compact = false,
    this.colorizeText = true,
    this.textStyle,
    this.mainAxisSize = MainAxisSize.min,
  });

  final LogLevel level;
  final bool isIos;
  final String? text;
  final bool includeValueInLabel;
  final bool compact;
  final bool colorizeText;
  final TextStyle? textStyle;
  final MainAxisSize mainAxisSize;

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

