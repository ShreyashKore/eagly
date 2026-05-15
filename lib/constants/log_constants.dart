import 'package:flutter/material.dart';

import '../data/log_level.dart';
import '../theme/log_level_presentation.dart';

List<LogLevel> _logLevelsForPlatform({required bool isIos}) =>
    isIos ? LogLevel.iosValues : LogLevel.androidValues;

List<DropdownMenuItem<LogLevel>> buildLogLevelDropdownItems({
  required BuildContext context,
  bool includeValueInLabel = false,
  bool isIos = false,
}) {
  return _logLevelsForPlatform(isIos: isIos)
      .map(
        (level) => DropdownMenuItem<LogLevel>(
          value: level,
          child: LogLevelLabel(
            level: level,
            isIos: isIos,
            includeValueInLabel: includeValueInLabel,
            compact: true,
            textStyle: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      )
      .toList(growable: false);
}

List<PlatformMenuItem> buildLogLevelMenuItems({
  required ValueChanged<LogLevel> onSelected,
  bool isIos = false,
}) {
  return _logLevelsForPlatform(isIos: isIos)
      .map(
        (level) => PlatformMenuItem(
          label: level.labelWithDisplayCode(isIos: isIos),
          onSelected: () => onSelected(level),
        ),
      )
      .toList(growable: false);
}
