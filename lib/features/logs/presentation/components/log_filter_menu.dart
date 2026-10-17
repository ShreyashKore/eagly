import 'package:flutter/material.dart';

import '../../../../presentation/theme/app_theme.dart';
import '../../data/models/filter_condition.dart';
import '../../data/models/log_filters.dart';
import '../../data/models/log_level.dart';
import 'log_filter_controller.dart';
import 'log_filter_parts.dart';

/// The fields in the order the menu offers them — most-used first, so a bare
/// ↵ after typing filters the message.
const List<FilterConditionField> _menuFieldOrder = [
  FilterConditionField.message,
  FilterConditionField.packageName,
  FilterConditionField.tag,
  FilterConditionField.pidTid,
  FilterConditionField.anyField,
];

/// The pill field a typed `key:` fills in; level and age have no pill field.
FilterConditionField? _fieldForKey(FilterKey key) => switch (key) {
  FilterKey.message => FilterConditionField.message,
  FilterKey.packageName => FilterConditionField.packageName,
  FilterKey.pidTid => FilterConditionField.pidTid,
  FilterKey.tag => FilterConditionField.tag,
  FilterKey.level || FilterKey.age => null,
};

/// One selectable row in the menu: it either runs [onSelected] (adding or
/// applying something) or, with [insertText], completes the typed text.
class FilterMenuOption {
  const FilterMenuOption({
    required this.icon,
    required this.label,
    this.packageName,
    this.onSelected,
    this.insertText,
  });

  final IconData icon;
  final InlineSpan label;

  /// Set on an Android package value, whose row then shows the app's icon
  /// (when the Apps pane has cached one) in place of [icon].
  final String? packageName;
  final VoidCallback? onSelected;
  final String? insertText;
}

/// The menu's sections for [rawQuery], the field's current text; flattened,
/// their options are the keyboard order.
List<(String, List<FilterMenuOption>)> filterMenuSections(
  BuildContext context,
  LogFilterController controller,
  String rawQuery,
) {
  final isIos = controller.isIos;
  final colors = Theme.of(context).colorScheme;
  final valueStyle = TextStyle(
    fontWeight: FontWeight.w600,
    color: colors.onSurface,
  );
  final mutedStyle = TextStyle(color: context.eaglyTheme.tertiaryTextColor);
  final negatedStyle = TextStyle(
    color: colors.error,
    fontWeight: FontWeight.w600,
  );
  InlineSpan phrase(String field, String operator, String value, bool neg) =>
      TextSpan(
        children: [
          TextSpan(text: field),
          TextSpan(text: ' $operator ', style: neg ? negatedStyle : mutedStyle),
          TextSpan(text: value, style: valueStyle),
        ],
      );
  InlineSpan condition(
    FilterConditionField field,
    FilterOperator operator,
    String value,
  ) =>
      phrase(field.label(isIos: isIos), operator.label, value, operator.negate);
  String? packageOf(FilterConditionField field, String value) =>
      showsFilterAppIcons(controller, field) ? value : null;

  final query = rawQuery.trim();
  if (query.isEmpty) {
    return [
      (
        'Filter by',
        [
          for (final field in _menuFieldOrder)
            FilterMenuOption(
              icon: filterFieldIcon(field),
              label: TextSpan(text: field.label(isIos: isIos)),
              onSelected: () => controller.addCondition(field),
            ),
          if (!controller.showsAgePill)
            FilterMenuOption(
              icon: Icons.schedule,
              label: const TextSpan(text: 'Age'),
              onSelected: controller.addAgeCondition,
            ),
        ],
      ),
    ];
  }

  final tokens = tokenizeFilterText(query);

  // One `key:value` being typed: offer exactly that filter, and values for it.
  if (tokens.length == 1) {
    final token = parseKeyedFilterToken(tokens.single, allowEmptyValue: true);
    if (token != null) {
      final value = token.value;
      switch (token.key) {
        case FilterKey.level:
          final q = value.toLowerCase();
          final levels = isIos ? LogLevel.iosValues : LogLevel.androidValues;
          return [
            (
              'Level',
              [
                for (final level in levels)
                  if (q.isEmpty ||
                      level.label.toLowerCase().startsWith(q) ||
                      level.code.toLowerCase().startsWith(q) ||
                      level.androidCode.toLowerCase() == q)
                    FilterMenuOption(
                      icon: Icons.signal_cellular_alt_rounded,
                      label: phrase(
                        'Level',
                        'is',
                        '${level.label} and above',
                        false,
                      ),
                      onSelected: () => controller.setLevel(level),
                    ),
              ],
            ),
          ];
        case FilterKey.age:
          final age = parseMaxAge(value);
          final presets = age == null
              ? const [
                  Duration(minutes: 1),
                  Duration(minutes: 5),
                  Duration(minutes: 15),
                  Duration(hours: 1),
                ]
              : [age];
          return [
            (
              'Age',
              [
                for (final preset in presets)
                  FilterMenuOption(
                    icon: Icons.schedule,
                    label: phrase(
                      'Age',
                      'within last',
                      formatMaxAge(preset),
                      false,
                    ),
                    onSelected: () => controller.setMaxAge(preset),
                  ),
              ],
            ),
          ];
        case FilterKey.message:
        case FilterKey.packageName:
        case FilterKey.pidTid:
        case FilterKey.tag:
          final field = _fieldForKey(token.key)!;
          final operator = FilterOperator.of(token.mode, negate: token.negate);
          final suggestions = suggestedFilterValues(controller, field, value);
          return [
            if (value.isNotEmpty)
              (
                'Add filter',
                [
                  FilterMenuOption(
                    icon: filterFieldIcon(field),
                    label: condition(field, operator, value),
                    onSelected: () => controller.addConditionWithValue(
                      field,
                      value,
                      operator: operator,
                    ),
                  ),
                ],
              ),
            if (suggestions.isNotEmpty)
              (
                'Suggestions',
                [
                  for (final suggestion in suggestions)
                    FilterMenuOption(
                      icon: filterFieldIcon(field),
                      label: condition(field, operator, suggestion),
                      packageName: packageOf(field, suggestion),
                      onSelected: () => controller.addConditionWithValue(
                        field,
                        suggestion,
                        operator: operator,
                      ),
                    ),
                ],
              ),
          ];
      }
    }
  }

  // Several tokens, some keyed: one row applies them all.
  if (tokens.any((token) => parseKeyedFilterToken(token) != null)) {
    return [
      (
        'Add filters',
        [
          FilterMenuOption(
            icon: Icons.filter_list_rounded,
            label: TextSpan(
              children: [
                TextSpan(text: 'Add ${tokens.length} filters  '),
                TextSpan(text: query, style: mutedStyle),
              ],
            ),
            onSelected: () => controller.applyTyped(query),
          ),
        ],
      ),
    ];
  }

  // Plain text: "<field> contains <text>" for every field, a leading `-`
  // making it "does not contain".
  final negate =
      tokens.length == 1 && query.length > 1 && query.startsWith('-');
  final text = negate ? query.substring(1) : query;
  final contains = FilterOperator.of(FilterMatchMode.contains, negate: negate);
  final age = parseMaxAge(query);

  final suggestions = <FilterMenuOption>[];
  for (final field in const [
    FilterConditionField.packageName,
    FilterConditionField.tag,
    FilterConditionField.message,
  ]) {
    for (final value in suggestedFilterValues(controller, field, text)) {
      suggestions.add(
        FilterMenuOption(
          icon: filterFieldIcon(field),
          label: condition(field, contains, value),
          packageName: packageOf(field, value),
          onSelected: () => controller.addConditionWithValue(
            field,
            value,
            operator: contains,
          ),
        ),
      );
    }
  }

  // `ta` → `tag:` — the keys, for anyone learning the syntax.
  final keyPrefix = (negate ? text : query).toLowerCase();
  final keys = tokens.length == 1 && !query.contains(':')
      ? [
          for (final (key, label) in [
            ('message', 'Message'),
            ('package', 'Package'),
            (isIos ? 'category' : 'tag', isIos ? 'Category' : 'Tag'),
            ('pid', 'PID / TID'),
            ('level', 'Level'),
            ('age', 'Age'),
          ])
            if (key.startsWith(keyPrefix) && key != keyPrefix)
              FilterMenuOption(
                icon: Icons.keyboard_outlined,
                label: TextSpan(
                  children: [
                    TextSpan(
                      text: '${negate ? '-' : ''}$key:',
                      style: valueStyle,
                    ),
                    TextSpan(text: '  filter by $label', style: mutedStyle),
                  ],
                ),
                insertText: '${negate ? '-' : ''}$key:',
              ),
        ]
      : const <FilterMenuOption>[];

  return [
    (
      'Add filter',
      [
        for (final field in _menuFieldOrder)
          if (!negate || field.operators.contains(contains))
            FilterMenuOption(
              icon: filterFieldIcon(field),
              label: condition(field, contains, text),
              onSelected: () => controller.addConditionWithValue(
                field,
                text,
                operator: contains,
              ),
            ),
        if (age != null && !controller.showsAgePill)
          FilterMenuOption(
            icon: Icons.schedule,
            label: phrase('Age', 'within last', formatMaxAge(age), false),
            onSelected: () => controller.setMaxAge(age),
          ),
      ],
    ),
    if (suggestions.isNotEmpty) ('Suggestions', suggestions.take(6).toList()),
    if (keys.isNotEmpty) ('Keys', keys),
  ];
}

/// The "Filter by…" menu under the filter field, drawing the sections
/// [filterMenuSections] builds, with the typed syntax as its footer.
class FilterMenu extends StatelessWidget {
  const FilterMenu({
    super.key,
    required this.sections,
    required this.highlighted,
    required this.isIos,
    required this.hasQuery,
    required this.onHover,
    required this.onSelect,
  });

  final List<(String, List<FilterMenuOption>)> sections;
  final int highlighted;
  final bool isIos;
  final bool hasQuery;
  final ValueChanged<int> onHover;
  final ValueChanged<FilterMenuOption> onSelect;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    var index = 0;
    for (final (title, items) in sections) {
      rows.add(FilterMenuSectionLabel(title));
      for (final option in items) {
        final i = index++;
        rows.add(
          FilterMenuRow(
            icon: option.icon,
            packageName: option.packageName,
            highlighted: i == highlighted,
            trailing: i == highlighted ? const FilterEnterHint() : null,
            onHover: () => onHover(i),
            onTap: () => onSelect(option),
            child: Text.rich(
              option.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        );
      }
    }
    if (rows.isEmpty) {
      rows.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
          child: Text(
            'Type a value, then press ↵',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(6, 2, 6, 6),
            children: rows,
          ),
        ),
        Divider(
          height: 1,
          color: Theme.of(
            context,
          ).colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
        _SyntaxHint(isIos: isIos),
      ],
    );
  }
}

/// The menu's footer: the typed syntax, so the shortcut is one glance away.
class _SyntaxHint extends StatelessWidget {
  const _SyntaxHint({required this.isIos});

  final bool isIos;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final tag = isIos ? 'category' : 'tag';
    final muted = TextStyle(
      fontSize: 11,
      color: context.eaglyTheme.tertiaryTextColor,
    );
    Widget code(String text) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: context.eaglyTheme.monoStyle.copyWith(
          fontSize: 11,
          color: colors.onSurface,
        ),
      ),
    );
    Widget item(String syntax, String meaning) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        code(syntax),
        const SizedBox(width: 4),
        Text(meaning, style: muted),
      ],
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: Wrap(
        spacing: 10,
        runSpacing: 6,
        children: [
          item('$tag:Auth', 'contains'),
          item('-$tag:', 'not'),
          item('$tag=:', 'is'),
          item('$tag~:', 'regex'),
          item('level:e', 'level'),
          item('age:5m', 'age'),
        ],
      ),
    );
  }
}
