import 'package:flutter/material.dart';

import '../data/log_level.dart';

List<LogLevel> _logLevelsForPlatform({required bool isIos}) =>
    isIos ? LogLevel.iosValues : LogLevel.androidValues;

List<DropdownMenuItem<LogLevel>> buildLogLevelDropdownItems({
  bool includeValueInLabel = false,
  bool isIos = false,
}) {
  return _logLevelsForPlatform(isIos: isIos)
      .map(
        (level) => DropdownMenuItem<LogLevel>(
          value: level,
          child: Text(
            includeValueInLabel
                ? level.labelWithDisplayCode(isIos: isIos)
                : level.displayLabel(isIos: isIos),
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
