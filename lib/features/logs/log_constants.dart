import 'package:flutter/material.dart';

import 'data/models/log_level.dart';
import '../../presentation/theme/log_level_presentation.dart';

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
