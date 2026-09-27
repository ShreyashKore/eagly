import 'package:flutter/material.dart';

import '../../log_constants.dart';
import '../../data/models/log_level.dart';

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

// ── Filter row controls ──────────────────────────────────────────────────────

/// Height of the filter row's rounded controls (search, Filter, Level).
const double kFilterControlHeight = 30.0;

/// Corner radius of the filter row's controls; pills are fully rounded.
const double kFilterControlRadius = 8.0;

/// Height of a filter pill, which sits inside the filter field.
const double kFilterPillHeight = 24.0;

/// A small outlined keyboard shortcut, e.g. `⌘F`, shown in an idle control.
class FilterKeyHint extends StatelessWidget {
  const FilterKeyHint({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10.5, color: colors.onSurfaceVariant),
      ),
    );
  }
}

/// The fill, border and label style every filter row control shares, so the
/// search field and the Filter / Level buttons read as one family.
class FilterControlStyle {
  FilterControlStyle.of(BuildContext context) : _theme = Theme.of(context);

  final ThemeData _theme;

  ColorScheme get _colors => _theme.colorScheme;

  Color fill({bool hovered = false}) =>
      hovered ? _colors.surfaceContainerHighest : _colors.surfaceContainerHigh;

  Color border({bool focused = false, bool active = false}) => focused
      ? _colors.primary
      : active
      ? _colors.primary.withValues(alpha: 0.45)
      : _colors.outlineVariant.withValues(alpha: 0.55);

  TextStyle? get label => _theme.textTheme.labelLarge?.copyWith(
    fontSize: 12.5,
    fontWeight: FontWeight.w500,
    color: _colors.onSurface,
  );

  TextStyle? get hint => label?.copyWith(
    color: _colors.onSurfaceVariant,
    fontWeight: FontWeight.w400,
  );

  Color get icon => _colors.onSurfaceVariant;
}

/// A rounded, filled, icon-and-label button in the filter row.
class FilterControlButton extends StatefulWidget {
  const FilterControlButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.trailing,
    this.active = false,
    this.focusNode,
    this.tooltip,
  });

  final IconData icon;
  final Widget label;
  final Widget? trailing;
  final VoidCallback onPressed;

  /// Tints the border — the control currently has something applied.
  final bool active;
  final FocusNode? focusNode;
  final String? tooltip;

  @override
  State<FilterControlButton> createState() => _FilterControlButtonState();
}

class _FilterControlButtonState extends State<FilterControlButton> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final style = FilterControlStyle.of(context);
    Widget button = Material(
      color: style.fill(hovered: _hovered),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kFilterControlRadius),
        side: BorderSide(
          color: style.border(focused: _focused, active: widget.active),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        focusNode: widget.focusNode,
        onTap: widget.onPressed,
        onHover: (value) => setState(() => _hovered = value),
        onFocusChange: (value) => setState(() => _focused = value),
        child: SizedBox(
          height: kFilterControlHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(widget.icon, size: 15, color: style.icon),
                const SizedBox(width: 6),
                DefaultTextStyle.merge(style: style.label, child: widget.label),
                if (widget.trailing != null) ...[
                  const SizedBox(width: 6),
                  widget.trailing!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
    final tooltip = widget.tooltip;
    if (tooltip != null) button = Tooltip(message: tooltip, child: button);
    return button;
  }
}
