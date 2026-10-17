import 'package:flutter/material.dart';

import '../../../../presentation/components/app_icon_button.dart';
import '../../../../presentation/components/package_icon.dart';
import '../../../../presentation/theme/app_theme.dart';
import '../../data/models/filter_condition.dart';
import 'filter_bar_shared.dart';
import 'log_filter_controller.dart';

/// The icon a [field] wears in menus, editors and suggestion rows.
IconData filterFieldIcon(FilterConditionField field) => switch (field) {
  FilterConditionField.packageName => Icons.apps_outlined,
  FilterConditionField.tag => Icons.sell_outlined,
  FilterConditionField.pidTid => Icons.numbers,
  FilterConditionField.message => Icons.notes_rounded,
  FilterConditionField.anyField => Icons.manage_search,
};

/// Recent and known values for [field] that contain [query] (all of them when
/// it is blank), word-boundary matches first.
List<String> suggestedFilterValues(
  LogFilterController controller,
  FilterConditionField field,
  String query, {
  int limit = 6,
}) {
  final sources = controller.suggestions;
  final values = deduplicateFilterValues(switch (field) {
    FilterConditionField.packageName => [
      ...sources.recentPackageFilters(),
      ...sources.knownPackageFilters(),
    ],
    FilterConditionField.tag => sources.recentTagFilters(),
    FilterConditionField.pidTid => sources.recentPidTidFilters(),
    FilterConditionField.message ||
    FilterConditionField.anyField => sources.recentMessageFilters(),
  });
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return values.take(limit).toList();
  final preferred = <String>[];
  final secondary = <String>[];
  for (final value in values) {
    final normalized = value.toLowerCase();
    if (normalized == q || !normalized.contains(q)) continue;
    (filterBoundaryMatch(normalized, q) ? preferred : secondary).add(value);
  }
  return [...preferred, ...secondary].take(limit).toList();
}

/// Whether [field]'s suggestions lead with the app's launcher icon: Android
/// packages only, read from the cache the Apps pane fills ([PackageIcon]).
bool showsFilterAppIcons(
  LogFilterController controller,
  FilterConditionField field,
) => field == FilterConditionField.packageName && !controller.isIos;

/// Icon, field name, operator and a delete button — the top line of every
/// pill editor.
class const FilterEditorHeader({
  super.key,
  required this.icon,
  required this.label,
  required this.operator,
  required this.onRemove,
}) extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget operator;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 16, color: colors.onSurfaceVariant),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        const SizedBox(width: 4),
        Expanded(child: operator),
        AppIconButton(
          tooltip: 'Delete filter',
          onPressed: onRemove,
          icon: Icons.delete_outline,
          iconSize: 16,
        ),
      ],
    );
  }
}

/// A small heading over a group of [FilterMenuRow]s.
class const FilterMenuSectionLabel(this.text, {super.key})
    extends StatelessWidget {
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
          color: context.eaglyTheme.secondaryTextColor,
        ),
      ),
    );
  }
}

/// A rounded, hover-highlighted row in a popover list.
class const FilterMenuRow({
  super.key,
  required this.child,
  required this.onTap,
  this.icon,
  this.packageName,
  this.trailing,
  this.highlighted = false,
  this.onHover,
}) extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final IconData? icon;

  /// A package whose cached app icon replaces [icon], which stays the
  /// fallback until the Apps pane has fetched one.
  final String? packageName;
  final Widget? trailing;
  final bool highlighted;
  final VoidCallback? onHover;

  @override
  State<FilterMenuRow> createState() => _FilterMenuRowState();
}

class _FilterMenuRowState extends State<FilterMenuRow> {
  bool _hovered = false;

  Widget _buildIcon(ColorScheme colors) {
    final glyph = Icon(widget.icon, size: 16, color: colors.onSurfaceVariant);
    final packageName = widget.packageName;
    if (packageName == null) return glyph;
    return PackageIcon(packageName: packageName, size: 16, fallback: glyph);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final lit = widget.highlighted || _hovered;
    return MouseRegion(
      onEnter: (_) {
        setState(() => _hovered = true);
        widget.onHover?.call();
      },
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: lit ? colors.onSurface.withValues(alpha: 0.07) : null,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              if (widget.icon != null) ...[
                _buildIcon(colors),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: DefaultTextStyle.merge(
                  style: TextStyle(fontSize: 13, color: colors.onSurface),
                  child: widget.child,
                ),
              ),
              if (widget.trailing != null) widget.trailing!,
            ],
          ),
        ),
      ),
    );
  }
}

/// The ↵ glyph at the end of the highlighted row: what Enter will pick.
class const FilterEnterHint({super.key}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Icon(
      Icons.keyboard_return,
      size: 14,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
  }
}

/// A rounded, filled text field for popover cards.
InputDecoration filterCardInputDecoration(
  BuildContext context, {
  String? hintText,
  String? errorText,
  IconData? prefixIcon,
}) {
  final colors = Theme.of(context).colorScheme;
  OutlineInputBorder border(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(kFilterControlRadius),
        borderSide: BorderSide(color: color, width: width),
      );
  return InputDecoration(
    isDense: true,
    filled: true,
    fillColor: colors.surfaceContainerHigh,
    hintText: hintText,
    hintStyle: TextStyle(
      fontSize: 13,
      color: context.eaglyTheme.tertiaryTextColor,
    ),
    errorText: errorText,
    errorStyle: const TextStyle(fontSize: 11),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
    prefixIcon: prefixIcon == null
        ? null
        : Icon(prefixIcon, size: 16, color: colors.onSurfaceVariant),
    prefixIconConstraints: const BoxConstraints(minWidth: 32, minHeight: 20),
    border: border(colors.outlineVariant.withValues(alpha: 0.6)),
    enabledBorder: border(colors.outlineVariant.withValues(alpha: 0.6)),
    focusedBorder: border(colors.primary, 1.5),
    errorBorder: border(colors.error),
    focusedErrorBorder: border(colors.error, 1.5),
  );
}
