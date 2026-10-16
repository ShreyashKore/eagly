import 'package:flutter/material.dart';

import '../../../../presentation/theme/app_theme.dart';

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

/// Height of the filter row's rounded controls (search, filter, Level).
const double kFilterControlHeight = 38.0;

/// Line height of the filter inputs' 13px text, as a multiple of its size.
const double kFilterTextHeight = 1.25;

/// Corner radius of the filter row's controls; pills are fully rounded.
const double kFilterControlRadius = 8.0;

/// Height of a filter pill — a label line over a value line — which sits
/// inside the filter field.
const double kFilterPillHeight = 32.0;

/// The filter row's heights at the app zoom. The zoom scales text, so a
/// fixed height overflows once the text outgrows it — a pill's two lines
/// already do at 1.2×.
extension FilterRowMetrics on BuildContext {
  double get filterControlHeight => scaled(kFilterControlHeight);
  double get filterPillHeight => scaled(kFilterPillHeight);
}

/// Decoration for a text field that sits inside a filter row control, which
/// draws the border and fill itself: every border state, the theme's fill
/// and its padding are turned off, so the focused field shows no second box.
InputDecoration bareFilterInputDecoration({
  String? hintText,
  TextStyle? hintStyle,
}) => InputDecoration(
  hintText: hintText,
  hintStyle: hintStyle,
  hintMaxLines: 1,
  isDense: true,
  filled: false,
  contentPadding: EdgeInsets.zero,
  border: InputBorder.none,
  enabledBorder: InputBorder.none,
  focusedBorder: InputBorder.none,
  disabledBorder: InputBorder.none,
  errorBorder: InputBorder.none,
  focusedErrorBorder: InputBorder.none,
);

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
        style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
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
    fontSize: 13,
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
          height: context.filterControlHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(widget.icon, size: 16, color: style.icon),
                const SizedBox(width: 8),
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
