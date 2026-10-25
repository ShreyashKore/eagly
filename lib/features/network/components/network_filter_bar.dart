import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../presentation/components/app_icon_button.dart';
import '../../../presentation/theme/app_theme.dart';
import '../data/network_filter.dart';
import '../network_controller.dart';
import 'network_presentation.dart';
import '../../../utils/timestamp_utils.dart';
import '../../../presentation/components/hover_builder.dart';

/// The Network pane's filter: a DevTools-style query field that suggests keys
/// and the values seen so far, and a row of status and type toggles. Edits
/// [NetworkController.filter]; the list re-filters as you type.
class const NetworkFilterBar({
  super.key,
  required final NetworkController controller,
  required final FocusNode focusNode,
}) extends StatefulWidget {
  @override
  State<NetworkFilterBar> createState() => _NetworkFilterBarState();
}

class _NetworkFilterBarState extends State<NetworkFilterBar> {
  late final TextEditingController _text = TextEditingController(
    text: widget.controller.filter.query,
  );

  NetworkController get controller => widget.controller;

  @override
  void didUpdateWidget(NetworkFilterBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncText();
  }

  /// Takes in a query changed from elsewhere (a context-menu "Show only…").
  void _syncText() {
    final query = controller.filter.query;
    if (_text.text == query) return;
    _text.value = TextEditingValue(
      text: query,
      selection: TextSelection.collapsed(offset: query.length),
    );
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _onChanged(String query) =>
      controller.setFilter(controller.filter.copyWith(query: query));

  void _toggleStatus(NetworkStatusClass status) {
    final next = {...controller.filter.statusClasses};
    if (!next.remove(status)) next.add(status);
    controller.setFilter(controller.filter.copyWith(statusClasses: next));
  }

  void _toggleType(NetworkResourceType type) {
    final next = {...controller.filter.types};
    if (!next.remove(type)) next.add(type);
    controller.setFilter(controller.filter.copyWith(types: next));
  }

  void _clearToggles() => controller.setFilter(
    controller.filter.copyWith(statusClasses: const {}, types: const {}),
  );

  @override
  Widget build(BuildContext context) {
    _syncText();
    final theme = Theme.of(context);
    final filter = controller.filter;
    final window = filter.timeWindow;
    final anyToggle =
        filter.statusClasses.isNotEmpty || filter.types.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 6,
        children: [
          _QueryField(
            controller: controller,
            text: _text,
            focusNode: widget.focusNode,
            error: filter.error,
            onChanged: _onChanged,
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              spacing: 4,
              children: [
                _ToggleChip(
                  label: 'All',
                  tooltip: 'Show every status and type',
                  selected: !anyToggle,
                  onTap: _clearToggles,
                ),
                const _ChipDivider(),
                for (final status in NetworkStatusClass.values)
                  _ToggleChip(
                    label: status.label,
                    tooltip: status.description,
                    selected: filter.statusClasses.contains(status),
                    onTap: () => _toggleStatus(status),
                  ),
                const _ChipDivider(),
                for (final type in NetworkResourceType.values)
                  _ToggleChip(
                    label: type.label,
                    tooltip: type.description,
                    selected: filter.types.contains(type),
                    onTap: () => _toggleType(type),
                  ),
                if (window != null) ...[
                  const _ChipDivider(),
                  _TimeWindowChip(controller: controller, window: window),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The query text field, with suggestions for the term under the cursor.
class const _QueryField({
  required final NetworkController controller,
  required final TextEditingController text,
  required final FocusNode focusNode,
  required final String? error,
  required final ValueChanged<String> onChanged,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.eaglyTheme;
    final style = theme.textTheme.bodySmall;

    return RawAutocomplete<_Suggestion>(
      textEditingController: text,
      focusNode: focusNode,
      displayStringForOption: (suggestion) => suggestion.apply(text.value).text,
      optionsBuilder: (value) => _suggest(controller, value),
      onSelected: (suggestion) {
        text.value = suggestion.apply(text.value);
        onChanged(text.text);
      },
      fieldViewBuilder: (context, textController, focusNode, onSubmitted) {
        return CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): () {
              if (textController.text.isEmpty) {
                focusNode.unfocus();
              } else {
                textController.clear();
                onChanged('');
              }
            },
          },
          child: ListenableBuilder(
            listenable: textController,
            builder: (context, _) => TextField(
              controller: textController,
              focusNode: focusNode,
              onChanged: onChanged,
              onSubmitted: (_) => onSubmitted(),
              style: style,
              decoration: InputDecoration(
                isDense: true,
                hintText:
                    'Filter: text in the URL, domain:, method:, '
                    'status-code:, -negate, /regex/',
                hintStyle: style?.copyWith(color: tokens.tertiaryTextColor),
                prefixIcon: Icon(
                  Icons.filter_list,
                  size: context.scaled(16),
                  color: textController.text.isEmpty
                      ? tokens.tertiaryTextColor
                      : theme.colorScheme.primary,
                ),
                prefixIconConstraints: BoxConstraints(
                  minWidth: context.scaled(32),
                ),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (textController.text.isNotEmpty)
                      AppIconButton(
                        tooltip: 'Clear filter (Esc)',
                        icon: Icons.close,
                        iconSize: 14,
                        padding: 4,
                        onPressed: () {
                          textController.clear();
                          onChanged('');
                        },
                      ),
                    const _SyntaxHelp(),
                    const SizedBox(width: 4),
                  ],
                ),
                suffixIconConstraints: const BoxConstraints(),
                errorText: error == null ? null : 'Ignored: $error',
                errorStyle: style?.copyWith(color: tokens.errorColor),
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
          ),
        );
      },
      optionsViewBuilder: (context, onSelected, options) =>
          _SuggestionList(options: options.toList(), onSelected: onSelected),
    );
  }
}

class const _SuggestionList({
  required final List<_Suggestion> options,
  required final AutocompleteOnSelected<_Suggestion> onSelected,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.eaglyTheme;
    final highlighted = AutocompleteHighlightedOption.of(context);
    return Align(
      alignment: Alignment.topLeft,
      child: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(8),
        color: theme.colorScheme.surfaceContainerHighest,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 260, maxWidth: 420),
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 4),
            shrinkWrap: true,
            itemCount: options.length,
            itemBuilder: (context, index) {
              final option = options[index];
              final active = index == highlighted;
              if (active) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (context.mounted) {
                    Scrollable.ensureVisible(context, alignment: 0.5);
                  }
                });
              }
              return InkWell(
                onTap: () => onSelected(option),
                child: Container(
                  color: active ? theme.colorScheme.secondaryContainer : null,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  child: Row(
                    children: [
                      Text(
                        option.label,
                        style: tokens.monoStyle.copyWith(
                          fontSize: theme.textTheme.bodySmall?.fontSize,
                        ),
                      ),
                      if (option.detail case final detail?) ...[
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            detail,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.end,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: tokens.tertiaryTextColor,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// One suggestion: replaces the term under the cursor with [replacement].
class const _Suggestion({
  required final String label,
  required final String replacement,
  required final int termStart,
  required final int termEnd,
  final String? detail,
}) {
  /// [value] with the term replaced. A finished `key:value` gets a trailing
  /// space so the next term can be typed straight away; a bare `key:` keeps
  /// the cursor after the colon.
  TextEditingValue apply(TextEditingValue value) {
    final text = value.text;
    final tail = text.substring(termEnd);
    final spacer = replacement.endsWith(':') || tail.startsWith(' ') ? '' : ' ';
    final inserted = '$replacement$spacer';
    final next = '${text.substring(0, termStart)}$inserted$tail';
    return TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: termStart + inserted.length),
    );
  }
}

/// Suggestions for the term under [value]'s cursor: filter keys while a key
/// is being typed, then the values the capture has for that key. Exposed for
/// tests.
@visibleForTesting
Iterable<({String label, String replacement})> filterSuggestionsFor(
  NetworkController controller,
  TextEditingValue value,
) => _suggest(
  controller,
  value,
).map((s) => (label: s.label, replacement: s.replacement));

List<_Suggestion> _suggest(
  NetworkController controller,
  TextEditingValue value,
) {
  final text = value.text;
  final cursor = value.selection.isValid
      ? value.selection.baseOffset.clamp(0, text.length)
      : text.length;
  var start = cursor;
  while (start > 0 && text[start - 1] != ' ') {
    start--;
  }
  var end = cursor;
  while (end < text.length && text[end] != ' ') {
    end++;
  }
  final term = text.substring(start, cursor);
  if (term.isEmpty) return const [];
  final negation = term.startsWith('-') ? '-' : '';
  final body = term.substring(negation.length);
  final colon = body.indexOf(':');

  if (colon < 0) {
    final lower = body.toLowerCase();
    return [
      for (final key in networkFilterKeys)
        for (final name in [key.name, ...key.aliases])
          if (name.startsWith(lower) && name != lower)
            _Suggestion(
              label: '$negation$name:',
              replacement: '$negation$name:',
              detail: key.description,
              termStart: start,
              termEnd: end,
            ),
    ];
  }

  final key = body.substring(0, colon).toLowerCase();
  final partial = body.substring(colon + 1).toLowerCase();
  final values = _valuesFor(controller, key);
  return [
    for (final (candidate, count) in values)
      if (candidate.toLowerCase().contains(partial) &&
          candidate.toLowerCase() != partial)
        _Suggestion(
          label: '$negation$key:$candidate',
          replacement: '$negation$key:${_quoteValue(candidate)}',
          detail: count == null ? null : '$count',
          termStart: start,
          termEnd: end,
        ),
  ].take(50).toList();
}

String _quoteValue(String value) => value.contains(' ') ? '"$value"' : value;

/// The values seen for [key], most frequent first, with how many exchanges
/// have each.
List<(String, int?)> _valuesFor(NetworkController controller, String key) {
  if (key == 'is') {
    return [for (final value in networkFilterIsValues) (value, null)];
  }
  final counts = <String, int>{};
  void count(String? value) {
    if (value == null || value.isEmpty) return;
    counts[value] = (counts[value] ?? 0) + 1;
  }

  for (final entry in controller.entries) {
    final t = entry.transaction;
    switch (key) {
      case 'domain' || 'host':
        count(t.request.uri?.host);
      case 'path':
        count(t.request.uri?.path);
      case 'method':
        count(t.request.method);
      case 'status-code' || 'status':
        count(t.response?.code.toString());
      case 'mime-type' || 'type':
        count(t.response?.contentType?.split(';').first.trim());
      case 'scheme':
        count(t.request.uri?.scheme);
      case 'has-request-header':
        t.request.headers
            .map((h) => h.name.toLowerCase())
            .toSet()
            .forEach(count);
      case 'has-response-header':
        t.response?.headers
            .map((h) => h.name.toLowerCase())
            .toSet()
            .forEach(count);
      case 'source':
        count(controller.sourceOf(entry.key)?.label);
    }
  }
  return [for (final MapEntry(:key, :value) in counts.entries) (key, value)]
    ..sort((a, b) => b.$2!.compareTo(a.$2!));
}

class const _SyntaxHelp() extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.eaglyTheme;
    final mono = tokens.monoStyle.copyWith(
      fontSize: theme.textTheme.bodySmall?.fontSize,
      color: theme.colorScheme.onInverseSurface,
    );
    final plain = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onInverseSurface,
    );
    return Tooltip(
      richMessage: TextSpan(
        style: plain,
        children: [
          const TextSpan(
            text:
                'Every term must match. Bare text matches the URL.\n'
                'Prefix a term with - to exclude it; wrap regexes in /…/; '
                'quote values with spaces.\n\n',
          ),
          for (final key in networkFilterKeys) ...[
            TextSpan(text: key.example.padRight(36), style: mono),
            TextSpan(text: '${key.description}\n'),
          ],
        ],
      ),
      preferBelow: true,
      waitDuration: const Duration(milliseconds: 200),
      child: MouseRegion(
        cursor: SystemMouseCursors.help,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(
            Icons.help_outline,
            size: context.scaled(15),
            color: tokens.tertiaryTextColor,
          ),
        ),
      ),
    );
  }
}

/// A compact on/off chip with a hover state.
class const _ToggleChip({
  required final String label,
  required final String tooltip,
  required final bool selected,
  required final VoidCallback onTap,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: Semantics(
        button: true,
        selected: selected,
        child: HoverBuilder(
          cursor: SystemMouseCursors.click,
          builder: (context, hovered) => GestureDetector(
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: selected
                    ? cs.secondaryContainer
                    : hovered
                    ? cs.onSurface.withValues(alpha: 0.08)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: selected ? cs.secondary : cs.outlineVariant,
                ),
              ),
              child: Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: selected
                      ? cs.onSecondaryContainer
                      : cs.onSurfaceVariant,
                  fontWeight: selected ? FontWeight.w600 : null,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class const _ChipDivider() extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: context.scaled(16),
    margin: const EdgeInsets.symmetric(horizontal: 4),
    color: Theme.of(context).colorScheme.outlineVariant,
  );
}

/// The overview's selected stretch of time, relative to the first request,
/// with a button to drop it.
class const _TimeWindowChip({
  required final NetworkController controller,
  required final NetworkTimeWindow window,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final origin = controller.entries
        .map((e) => e.transaction.startedAt)
        .nonNulls
        .fold<DateTime?>(
          null,
          (first, t) => first == null || t.isBefore(first) ? t : first,
        );
    String at(DateTime t) => origin == null
        ? formatTimeOfDay(t)
        : formatElapsed(t.difference(origin));

    return Tooltip(
      message:
          'Only requests active between ${formatTimeOfDay(window.start)} '
          'and ${formatTimeOfDay(window.end)}',
      child: Container(
        padding: const EdgeInsets.only(left: 8),
        decoration: BoxDecoration(
          color: cs.tertiaryContainer,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.timelapse,
              size: context.scaled(13),
              color: cs.onTertiaryContainer,
            ),
            const SizedBox(width: 4),
            Text(
              '${at(window.start)} – ${at(window.end)}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: cs.onTertiaryContainer,
              ),
            ),
            AppIconButton(
              tooltip: 'Show the whole timeline',
              icon: Icons.close,
              iconSize: 12,
              padding: 3,
              color: cs.onTertiaryContainer,
              onPressed: () => controller.setFilter(
                controller.filter.copyWith(timeWindow: () => null),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
