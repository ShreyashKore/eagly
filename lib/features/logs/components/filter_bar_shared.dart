import 'package:flutter/material.dart';

import '../../../constants/log_constants.dart';
import '../../../data/log_level.dart';

// Consistent height for all filter bar input fields.
const double kFilterFieldHeight = 36.0;

/// Standard [InputDecoration] used across all filter bar fields.
InputDecoration filterInputDecoration(
  BuildContext context, {
  String? labelText,
  String? hintText,
  IconData? prefixIcon,
}) {
  final colorScheme = Theme.of(context).colorScheme;
  InputBorder inputBorder(Color color) =>
      OutlineInputBorder(borderSide: BorderSide(color: color, width: 1.5));
  return InputDecoration(
    labelText: labelText,
    labelStyle: const TextStyle(fontSize: 12),
    hintText: hintText,
    hintStyle: const TextStyle(fontSize: 12),
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    border: inputBorder(Colors.transparent),
    enabledBorder: inputBorder(Colors.transparent),
    focusedBorder: inputBorder(colorScheme.primary),
    filled: true,
    fillColor: colorScheme.surfaceContainerHighest,
    prefixIconConstraints: prefixIcon != null
        ? const BoxConstraints(minHeight: 28, minWidth: 28)
        : null,
    prefixIcon: prefixIcon != null ? Icon(prefixIcon, size: 14) : null,
  );
}

/// A level picker [DropdownButtonFormField] used in both filter bars.
class LogLevelDropdown extends StatelessWidget {
  const LogLevelDropdown({
    super.key,
    required this.selectedLogLevel,
    required this.onLogLevelChanged,
    required this.isIos,
    this.width,
    this.height = kFilterFieldHeight,
  });

  final LogLevel selectedLogLevel;
  final ValueChanged<LogLevel?> onLogLevelChanged;
  final bool isIos;

  /// Fixed width. When `null` the widget expands to fill available space.
  final double? width;
  final double height;

  @override
  Widget build(BuildContext context) {
    Widget dropdown = SizedBox(
      height: height,
      child: DropdownButtonFormField<LogLevel>(
        initialValue: selectedLogLevel.normalizeSelectionForPlatform(
          isIos: isIos,
        ),
        isExpanded: true,
        isDense: true,
        decoration: filterInputDecoration(context, labelText: 'Level'),
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).colorScheme.onSurface,
        ),
        items: buildLogLevelDropdownItems(
          context: context,
          includeValueInLabel: true,
          isIos: isIos,
        ),
        onChanged: onLogLevelChanged,
      ),
    );

    if (width != null) {
      dropdown = SizedBox(width: width, child: dropdown);
    }
    return dropdown;
  }
}

/// Returns `true` when [query] matches [candidate] at a word/segment boundary.
bool filterBoundaryMatch(String candidate, String query) {
  if (candidate.startsWith(query)) return true;
  for (final separator in const ['.', '/', '_', '-', ':']) {
    if (candidate.contains('$separator$query')) return true;
  }
  return false;
}

/// Deduplicates a list of string values (case-insensitive, trims whitespace).
/// Blank entries are dropped.
List<String> deduplicateFilterValues(Iterable<String> values) {
  final result = <String>[];
  final seen = <String>{};
  for (final value in values) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) continue;
    if (!seen.add(trimmed.toLowerCase())) continue;
    result.add(trimmed);
  }
  return result;
}

