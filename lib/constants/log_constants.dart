import 'package:flutter/material.dart';

class LogLevelOption {
  const LogLevelOption({
    required this.value,
    required this.label,
    required this.iosLabel,
  });

  final String value;
  final String label;
  final String iosLabel;

  String get labelWithValue => '$label ($value)';

  String get androidLabelWithValue => labelWithValue;

  String get iosLabelWithValue => '$iosLabel ($value)';
}

const logLevelOptions = <LogLevelOption>[
  LogLevelOption(
    value: 'E',
    label: 'Error',
    iosLabel: 'fault, error, critical',
  ),
  LogLevelOption(value: 'W', label: 'Warning', iosLabel: 'warning, warn'),
  LogLevelOption(value: 'I', label: 'Info', iosLabel: 'notice, info, default'),
  LogLevelOption(value: 'D', label: 'Debug', iosLabel: 'debug'),
  LogLevelOption(value: 'V', label: 'Verbose', iosLabel: 'Verbose'),
];

List<DropdownMenuItem<String>> buildLogLevelDropdownItems({
  bool includeValueInLabel = false,
  bool isIos = false,
}) {
  return logLevelOptions
      .map(
        (option) => DropdownMenuItem<String>(
          value: option.value,
          child: Text(
            includeValueInLabel
                ? (isIos
                      ? option.iosLabelWithValue
                      : option.androidLabelWithValue)
                : option.label,
          ),
        ),
      )
      .toList(growable: false);
}

List<PlatformMenuItem> buildLogLevelMenuItems({
  required ValueChanged<String> onSelected,
}) {
  return logLevelOptions
      .map(
        (option) => PlatformMenuItem(
          label: option.labelWithValue,
          onSelected: () => onSelected(option.value),
        ),
      )
      .toList(growable: false);
}
