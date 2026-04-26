import 'package:flutter/material.dart';

class LogLevelOption {
  const LogLevelOption({required this.value, required this.label});

  final String value;
  final String label;

  String get labelWithValue => '$label ($value)';
}

const logLevelOptions = <LogLevelOption>[
  LogLevelOption(value: 'E', label: 'Error'),
  LogLevelOption(value: 'W', label: 'Warning'),
  LogLevelOption(value: 'I', label: 'Info'),
  LogLevelOption(value: 'D', label: 'Debug'),
  LogLevelOption(value: 'V', label: 'Verbose'),
];

List<DropdownMenuItem<String>> buildLogLevelDropdownItems({
  bool includeValueInLabel = false,
}) {
  return logLevelOptions
      .map(
        (option) => DropdownMenuItem<String>(
          value: option.value,
          child: Text(
            includeValueInLabel ? option.labelWithValue : option.label,
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
