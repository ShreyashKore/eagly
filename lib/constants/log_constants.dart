import 'package:flutter/material.dart';

import '../data/log_level.dart';

// ════════════════════════════════════════════════════════════════════════════
// Android (logcat) UI helpers
// ════════════════════════════════════════════════════════════════════════════

List<DropdownMenuItem<LogLevel>> buildLogLevelDropdownItems({
  bool includeValueInLabel = false,
}) {
  return LogLevel.androidValues
      .map(
        (level) => DropdownMenuItem<LogLevel>(
          value: level,
          child: Text(
            includeValueInLabel
                ? level.labelWithDisplayCode(isIos: false)
                : level.label,
          ),
        ),
      )
      .toList(growable: false);
}

List<PlatformMenuItem> buildLogLevelMenuItems({
  required ValueChanged<LogLevel> onSelected,
}) {
  return LogLevel.androidValues
      .map(
        (level) => PlatformMenuItem(
          label: level.labelWithDisplayCode(isIos: false),
          onSelected: () => onSelected(level),
        ),
      )
      .toList(growable: false);
}

// ════════════════════════════════════════════════════════════════════════════
// iOS (os_log / syslog) UI helpers
// ════════════════════════════════════════════════════════════════════════════

List<DropdownMenuItem<LogLevel>> buildIosLogLevelDropdownItems({
  bool includeValueInLabel = false,
}) {
  return LogLevel.iosValues
      .map(
        (level) => DropdownMenuItem<LogLevel>(
          value: level,
          child: Text(
            includeValueInLabel
                ? level.labelWithDisplayCode(isIos: true)
                : level.label,
          ),
        ),
      )
      .toList(growable: false);
}

List<PlatformMenuItem> buildIosLogLevelMenuItems({
  required ValueChanged<LogLevel> onSelected,
}) {
  return LogLevel.iosValues
      .map(
        (level) => PlatformMenuItem(
          label: level.labelWithDisplayCode(isIos: true),
          onSelected: () => onSelected(level),
        ),
      )
      .toList(growable: false);
}
