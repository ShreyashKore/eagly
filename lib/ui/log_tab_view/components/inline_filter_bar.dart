import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../constants/log_constants.dart';
import '../../../data/log_level.dart';
import '../../../theme/log_level_presentation.dart';
import 'filter_bar_shared.dart';

typedef InlineFilterSuggestionApplied =
    void Function(
      String text, {
      TextSelection selection,
      bool applyImmediately,
    });

class InlineFilterTextController extends TextEditingController {
  InlineFilterTextController({super.text});

  static const Set<String> _knownAliases = {
    'package',
    'pkg',
    'app',
    'process',
    'tag',
    'message',
    'msg',
    'text',
    'pid',
    'tid',
    'thread',
    'pidtid',
    'level',
    'lvl',
    'priority',
  };

  static bool isKnownKeyValueToken(String token) {
    final colonIndex = token.indexOf(':');
    if (colonIndex <= 0 || colonIndex == token.length - 1) return false;
    final key = token.substring(0, colonIndex).trim().toLowerCase();
    return _knownAliases.contains(key);
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final baseStyle = style ?? DefaultTextStyle.of(context).style;
    final theme = Theme.of(context);
    final textValue = text;
    final tokens = _InlineFilterContext.scanTokens(textValue);
    if (tokens.isEmpty) {
      return TextSpan(text: textValue, style: baseStyle);
    }

    final children = <InlineSpan>[];
    var cursor = 0;
    for (final token in tokens) {
      if (cursor < token.start) {
        children.add(
          TextSpan(
            text: textValue.substring(cursor, token.start),
            style: baseStyle,
          ),
        );
      }

      final tokenText = token.text;
      if (isKnownKeyValueToken(tokenText)) {
        final colonIndex = tokenText.indexOf(':');
        final keyText = tokenText.substring(0, colonIndex + 1);
        final valueText = tokenText.substring(colonIndex + 1);
        final backgroundColor = theme.colorScheme.primaryContainer.withValues(
          alpha: 0.9,
        );
        children.add(
          TextSpan(
            style: baseStyle.copyWith(backgroundColor: backgroundColor),
            children: [
              TextSpan(
                text: keyText,
                style: baseStyle.copyWith(
                  backgroundColor: backgroundColor,
                  color: theme.colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
              TextSpan(
                text: valueText,
                style: baseStyle.copyWith(
                  backgroundColor: backgroundColor,
                  color: theme.colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        );
      } else {
        children.add(TextSpan(text: tokenText, style: baseStyle));
      }
      cursor = token.end;
    }

    if (cursor < textValue.length) {
      children.add(
        TextSpan(text: textValue.substring(cursor), style: baseStyle),
      );
    }

    return TextSpan(style: baseStyle, children: children);
  }
}

class InlineFilterBar extends StatefulWidget {
  const InlineFilterBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onSubmitted,
    required this.onSuggestionApplied,
    required this.selectedLogLevel,
    required this.onLogLevelChanged,
    required this.recentMessageFilters,
    required this.recentPackageFilters,
    required this.knownPackageFilters,
    required this.recentPidTidFilters,
    required this.recentTagFilters,
    required this.isIos,
  });

  final InlineFilterTextController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmitted;
  final InlineFilterSuggestionApplied onSuggestionApplied;
  final LogLevel selectedLogLevel;
  final ValueChanged<LogLevel?> onLogLevelChanged;
  final List<String> recentMessageFilters;
  final List<String> recentPackageFilters;
  final List<String> knownPackageFilters;
  final List<String> recentPidTidFilters;
  final List<String> recentTagFilters;
  final bool isIos;

  static const List<_InlineFilterKeyDefinition> keyDefinitions = [
    _InlineFilterKeyDefinition(
      canonicalKey: 'package',
      aliases: {'package', 'pkg', 'app', 'process'},
      icon: Icons.apps_outlined,
      label: 'package:',
      description: 'Filter by package or process name',
    ),
    _InlineFilterKeyDefinition(
      canonicalKey: 'tag',
      aliases: {'tag'},
      icon: Icons.sell_outlined,
      label: 'tag:',
      description: 'Filter by tag',
    ),
    _InlineFilterKeyDefinition(
      canonicalKey: 'message',
      aliases: {'message', 'msg', 'text'},
      icon: Icons.message_outlined,
      label: 'message:',
      description: 'Filter the log message text only',
    ),
    _InlineFilterKeyDefinition(
      canonicalKey: 'pid',
      aliases: {'pid', 'tid', 'thread', 'pidtid'},
      icon: Icons.tag_outlined,
      label: 'pid:',
      description: 'Filter by PID, TID, or PID/TID pair',
    ),
    _InlineFilterKeyDefinition(
      canonicalKey: 'level',
      aliases: {'level', 'lvl', 'priority'},
      icon: Icons.flag_outlined,
      label: 'level:',
      description: 'Filter by log level',
    ),
  ];

  @override
  State<InlineFilterBar> createState() => _InlineFilterBarState();
}

class _InlineFilterBarState extends State<InlineFilterBar> {
  bool _helpVisible = false;

  // Notifier to force the autocomplete to rebuild/open on focus
  final _suggestionTrigger = ValueNotifier<int>(0);
  final ScrollController _suggestionsScrollController = ScrollController();
  final Map<String, GlobalKey> _suggestionItemKeys = <String, GlobalKey>{};
  TextEditingValue? _lastSuggestionEditingValue;
  List<_InlineFilterSuggestion> _currentSuggestions = const [];
  String _lastSuggestionQuerySignature = '';
  int _highlightedSuggestionIndex = 0;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChanged);
    _suggestionsScrollController.dispose();
    _suggestionTrigger.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (widget.focusNode.hasFocus) {
      // Trigger a rebuild so optionsBuilder is called and dropdown opens
      _suggestionTrigger.value++;
    }
  }

  void _reopenSuggestions() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _lastSuggestionEditingValue = widget.controller.value;
      _highlightedSuggestionIndex = 0;
      widget.focusNode.requestFocus();
      _suggestionTrigger.value++;
    });
  }

  String _suggestionIdentity(_InlineFilterSuggestion suggestion) {
    return [
      suggestion.label,
      suggestion.subtitle,
      suggestion.replacementText,
    ].join('\u0000');
  }

  GlobalKey _suggestionItemKey(_InlineFilterSuggestion suggestion) {
    final identity = _suggestionIdentity(suggestion);
    return _suggestionItemKeys.putIfAbsent(identity, GlobalKey.new);
  }

  void _ensureHighlightedSuggestionVisible() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _currentSuggestions.isEmpty) return;
      final suggestion = _currentSuggestions[_highlightedSuggestionIndex];
      final itemContext = _suggestionItemKey(suggestion).currentContext;
      if (itemContext == null) return;
      Scrollable.ensureVisible(
        itemContext,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
      );
    });
  }

  KeyEventResult _handleSuggestionKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent || _currentSuggestions.isEmpty) {
      return KeyEventResult.ignored;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() {
        _highlightedSuggestionIndex =
            (_highlightedSuggestionIndex + 1) % _currentSuggestions.length;
      });
      _ensureHighlightedSuggestionVisible();
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() {
        _highlightedSuggestionIndex =
            (_highlightedSuggestionIndex - 1 + _currentSuggestions.length) %
            _currentSuggestions.length;
      });
      _ensureHighlightedSuggestionVisible();
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      _applySuggestion(_currentSuggestions[_highlightedSuggestionIndex]);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  List<_InlineFilterSuggestion> _buildSuggestions(TextEditingValue value) {
    _lastSuggestionEditingValue = value;
    final querySignature = '${value.text}\u0000${value.selection.extentOffset}';
    final context = _InlineFilterContext.fromEditingValue(value);
    final activeToken = context.activeToken;
    final colonIndex = activeToken.text.indexOf(':');
    final suggestions =
        colonIndex > 0 && context.cursorOffset > activeToken.start + colonIndex
        ? () {
            final keyText = activeToken.text
                .substring(0, colonIndex)
                .trim()
                .toLowerCase();
            final valueText = activeToken.text.substring(colonIndex + 1);
            final keyDefinition = InlineFilterBar.keyDefinitions.firstWhere(
              (definition) => definition.aliases.contains(keyText),
              orElse: () => const _InlineFilterKeyDefinition.unknown(),
            );
            if (keyDefinition.canonicalKey == null) {
              return _matchingKeySuggestions(activeToken.text);
            }
            return _valueSuggestionsForKey(keyDefinition, valueText);
          }()
        : _matchingKeySuggestions(activeToken.text);

    _currentSuggestions = suggestions;
    if (_currentSuggestions.isEmpty) {
      _highlightedSuggestionIndex = 0;
    } else if (querySignature != _lastSuggestionQuerySignature ||
        _highlightedSuggestionIndex >= _currentSuggestions.length) {
      _highlightedSuggestionIndex = 0;
    }
    _lastSuggestionQuerySignature = querySignature;
    if (_currentSuggestions.isNotEmpty) {
      _ensureHighlightedSuggestionVisible();
    }
    return suggestions;
  }

  List<_InlineFilterSuggestion> _matchingKeySuggestions(String query) {
    final normalizedQuery = query.trim().toLowerCase();
    return InlineFilterBar.keyDefinitions
        .where((definition) {
          if (normalizedQuery.isEmpty) return true;
          return definition.aliases.any(
            (alias) => alias.startsWith(normalizedQuery),
          );
        })
        .map(
          (definition) => _InlineFilterSuggestion(
            label: definition.label,
            subtitle: definition.description,
            icon: definition.icon,
            replacementText: '${definition.canonicalKey}:',
            addTrailingSpace: false,
            applyImmediately: false,
            reopenSuggestions: true,
          ),
        )
        .toList(growable: false);
  }

  List<_InlineFilterValueCandidate> _packageValueCandidates() {
    return _mergeValueCandidates([
      for (final entry in widget.recentPackageFilters)
        _InlineFilterValueCandidate(
          value: entry,
          subtitle: 'Recent package filter',
        ),
      for (final entry in widget.knownPackageFilters)
        _InlineFilterValueCandidate(
          value: entry,
          subtitle: 'Known package from logs',
        ),
    ]);
  }

  List<_InlineFilterValueCandidate> _mergeValueCandidates(
    List<_InlineFilterValueCandidate> candidates,
  ) {
    final deduped = <_InlineFilterValueCandidate>[];
    final seen = <String>{};
    for (final c in candidates) {
      final trimmed = c.value.trim();
      if (trimmed.isEmpty) continue;
      if (!seen.add(trimmed.toLowerCase())) continue;
      deduped.add(_InlineFilterValueCandidate(value: trimmed, subtitle: c.subtitle));
    }
    return deduped;
  }

  bool _isBoundaryMatch(String candidate, String query) =>
      filterBoundaryMatch(candidate, query);

  Iterable<_InlineFilterValueCandidate> _matchingValueCandidates(
    List<_InlineFilterValueCandidate> candidates,
    String normalizedValue,
  ) sync* {
    if (normalizedValue.isEmpty) {
      yield* candidates;
      return;
    }

    final preferredMatches = <_InlineFilterValueCandidate>[];
    final secondaryMatches = <_InlineFilterValueCandidate>[];
    for (final candidate in candidates) {
      final normalizedCandidate = candidate.value.toLowerCase();
      if (!normalizedCandidate.contains(normalizedValue)) continue;
      final bucket = _isBoundaryMatch(normalizedCandidate, normalizedValue)
          ? preferredMatches
          : secondaryMatches;
      bucket.add(candidate);
    }

    yield* preferredMatches;
    yield* secondaryMatches;
  }

  List<_InlineFilterSuggestion> _valueSuggestionsForKey(
    _InlineFilterKeyDefinition keyDefinition,
    String rawValue,
  ) {
    final normalizedValue = _normalizeValue(rawValue).toLowerCase();
    if (keyDefinition.canonicalKey == 'level') {
      final supportedLevels = widget.isIos
          ? LogLevel.iosValues
          : LogLevel.androidValues;
      return supportedLevels
          .where((level) {
            if (normalizedValue.isEmpty) return true;
            return level.code.contains(normalizedValue) ||
                level
                    .displayLabel(isIos: widget.isIos)
                    .toLowerCase()
                    .contains(normalizedValue) ||
                level
                    .displayCode(isIos: widget.isIos)
                    .toLowerCase()
                    .contains(normalizedValue);
          })
          .map(
            (level) => _InlineFilterSuggestion(
              label: 'level:${level.code}',
              subtitle: level.labelWithDisplayCode(isIos: widget.isIos),
              icon: keyDefinition.icon,
              level: level,
              replacementText: 'level:${level.code}',
              addTrailingSpace: true,
              applyImmediately: true,
              reopenSuggestions: false,
            ),
          )
          .toList(growable: false);
    }

    final valueCandidates = switch (keyDefinition.canonicalKey) {
      'package' => _packageValueCandidates(),
      'tag' => _mergeValueCandidates([
        for (final entry in widget.recentTagFilters)
          _InlineFilterValueCandidate(
            value: entry,
            subtitle: 'Recent tag filter',
          ),
      ]),
      'message' => _mergeValueCandidates([
        for (final entry in widget.recentMessageFilters)
          _InlineFilterValueCandidate(
            value: entry,
            subtitle: 'Recent message filter',
          ),
      ]),
      'pid' => _mergeValueCandidates([
        for (final entry in widget.recentPidTidFilters)
          _InlineFilterValueCandidate(
            value: entry,
            subtitle: 'Recent pid/tid filter',
          ),
      ]),
      _ => const <_InlineFilterValueCandidate>[],
    };

    final normalizedLabel = keyDefinition.canonicalKey!;
    return _matchingValueCandidates(valueCandidates, normalizedValue)
        .map(
          (entry) => _InlineFilterSuggestion(
            label: '$normalizedLabel:${_formatInlineValue(entry.value)}',
            subtitle: entry.subtitle,
            icon: keyDefinition.icon,
            replacementText:
                '$normalizedLabel:${_formatInlineValue(entry.value)}',
            addTrailingSpace: true,
            applyImmediately: true,
            reopenSuggestions: false,
          ),
        )
        .toList(growable: false);
  }

  String _formatInlineValue(String value) {
    final trimmed = value.trim();
    final needsQuotes =
        trimmed.contains(RegExp(r'\s')) || trimmed.contains('"');
    if (!needsQuotes) return trimmed;
    return '"${trimmed.replaceAll('"', r'\"')}"';
  }

  String _normalizeValue(String rawValue) {
    var normalized = rawValue.trim();
    if (normalized.length >= 2 &&
        normalized.startsWith('"') &&
        normalized.endsWith('"')) {
      normalized = normalized.substring(1, normalized.length - 1);
    }
    return normalized.replaceAll(r'\"', '"');
  }

  void _applySuggestion(_InlineFilterSuggestion suggestion) {
    final value = _lastSuggestionEditingValue ?? widget.controller.value;
    final context = _InlineFilterContext.fromEditingValue(value);
    final activeToken = context.activeToken;
    final replacement = suggestion.addTrailingSpace
        ? '${suggestion.replacementText} '
        : suggestion.replacementText;
    final nextText =
        value.text.substring(0, activeToken.start) +
        replacement +
        value.text.substring(activeToken.end);
    final offset = activeToken.start + replacement.length;
    widget.onSuggestionApplied(
      nextText,
      selection: TextSelection.collapsed(offset: offset),
      applyImmediately: suggestion.applyImmediately,
    );
    if (suggestion.reopenSuggestions) {
      _reopenSuggestions();
    }
  }

  void _appendToken(String token, {required bool applyImmediately}) {
    final existingText = widget.controller.text;
    final prefix = existingText.trim().isEmpty
        ? ''
        : RegExp(r'\s$').hasMatch(existingText)
        ? ''
        : ' ';
    final suffix = applyImmediately ? ' ' : '';
    final nextText = '$existingText$prefix$token$suffix';
    widget.onSuggestionApplied(
      nextText,
      selection: TextSelection.collapsed(offset: nextText.length),
      applyImmediately: applyImmediately,
    );
  }

  Widget _buildHelpSection(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedCrossFade(
      duration: const Duration(milliseconds: 180),
      firstCurve: Curves.easeOut,
      secondCurve: Curves.easeIn,
      crossFadeState: _helpVisible
          ? CrossFadeState.showSecond
          : CrossFadeState.showFirst,
      firstChild: const SizedBox.shrink(),
      secondChild: Container(
        key: const ValueKey('inline-filter-help'),
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Icon(
              Icons.tips_and_updates_outlined,
              size: 16,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            Text(
              'Bare words search the whole log entry. Use key:value for package, tag, pid, message, or level. Quote values with spaces.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            ActionChip(
              label: const Text('package:'),
              onPressed: () =>
                  _appendToken('package:', applyImmediately: false),
            ),
            ActionChip(
              label: const Text('tag:'),
              onPressed: () => _appendToken('tag:', applyImmediately: false),
            ),
            ActionChip(
              label: const Text('message:'),
              onPressed: () =>
                  _appendToken('message:', applyImmediately: false),
            ),
            ActionChip(
              label: const Text('level:error'),
              onPressed: () =>
                  _appendToken('level:error', applyImmediately: true),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLevelDropdown(BuildContext context) {
    return LogLevelDropdown(
      selectedLogLevel: widget.selectedLogLevel,
      onLogLevelChanged: widget.onLogLevelChanged,
      isIos: widget.isIos,
      width: 176,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildLevelDropdown(context),
            const SizedBox(width: 8),
            Expanded(
              child: ValueListenableBuilder<int>(
                valueListenable: _suggestionTrigger,
                builder: (_, __, ___) => SizedBox(
                  height: kFilterFieldHeight,
                  child: RawAutocomplete<_InlineFilterSuggestion>(
                    textEditingController: widget.controller,
                    focusNode: widget.focusNode,
                    optionsBuilder: _buildSuggestions,
                    displayStringForOption: (option) => option.label,
                    onSelected: _applySuggestion,
                    fieldViewBuilder:
                        (
                          context,
                          fieldController,
                          fieldFocusNode,
                          onFieldSubmitted,
                        ) {
                          return Focus(
                            canRequestFocus: false,
                            onKeyEvent: (_, event) =>
                                _handleSuggestionKeyEvent(event),
                            child: TextField(
                              controller: fieldController,
                              focusNode: fieldFocusNode,
                              style: const TextStyle(fontSize: 12),
                              decoration: filterInputDecoration(
                                context,
                                hintText:
                                    'Try package:com.example.app tag:Auth level:error or just type text',
                                prefixIcon: Icons.message,
                              ),
                              onChanged: widget.onChanged,
                              onSubmitted: (_) {
                                widget.onSubmitted();
                                onFieldSubmitted();
                              },
                            ),
                          );
                        },
                    optionsViewBuilder: (context, onSelected, options) {
                      final materialOptions = options.toList(growable: false);
                      if (materialOptions.isEmpty) {
                        return const SizedBox.shrink();
                      }
                      return Align(
                        alignment: Alignment.topLeft,
                        child: Material(
                          elevation: 6,
                          borderRadius: BorderRadius.circular(8),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              maxHeight: 200,
                              maxWidth: 540,
                            ),
                            child: ListView.separated(
                              controller: _suggestionsScrollController,
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              shrinkWrap: true,
                              itemCount: materialOptions.length,
                              separatorBuilder: (_, _) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final option = materialOptions[index];
                                return Builder(
                                  builder: (context) {
                                    final isHighlighted =
                                        _highlightedSuggestionIndex == index;
                                    final backgroundColor = isHighlighted
                                        ? theme.colorScheme.secondaryContainer
                                        : null;
                                    return InkWell(
                                      key: _suggestionItemKey(option),
                                      onTap: () => _applySuggestion(option),
                                      child: ColoredBox(
                                        color:
                                            backgroundColor ??
                                            Colors.transparent,
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 5,
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.max,
                                            children: [
                                              Expanded(
                                                child: option.level != null
                                                    ? LogLevelLabel(
                                                        level: option.level!,
                                                        isIos: widget.isIos,
                                                        text: option.label,
                                                        compact: true,
                                                        textStyle: theme
                                                            .textTheme
                                                            .bodySmall,
                                                      )
                                                    : Row(
                                                        mainAxisSize:
                                                            MainAxisSize.max,
                                                        children: [
                                                          Icon(
                                                            option.icon,
                                                            size: 12,
                                                          ),
                                                          const SizedBox(
                                                            width: 6,
                                                          ),
                                                          Expanded(
                                                            child: Text(
                                                              option.label,
                                                              maxLines: 1,
                                                              overflow:
                                                                  TextOverflow
                                                                      .ellipsis,
                                                              style: theme
                                                                  .textTheme
                                                                  .bodySmall
                                                                  ?.copyWith(
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w600,
                                                                    color:
                                                                        isHighlighted
                                                                        ? theme
                                                                              .colorScheme
                                                                              .onSecondaryContainer
                                                                        : null,
                                                                  ),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                              ),
                                              if (option
                                                  .subtitle
                                                  .isNotEmpty) ...[
                                                const SizedBox(width: 8),
                                                Flexible(
                                                  child: Text(
                                                    option.subtitle,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    textAlign: TextAlign.end,
                                                    style: theme
                                                        .textTheme
                                                        .bodySmall
                                                        ?.copyWith(
                                                          fontSize: 10,
                                                          color: isHighlighted
                                                              ? theme
                                                                    .colorScheme
                                                                    .onSecondaryContainer
                                                              : theme
                                                                    .colorScheme
                                                                    .onSurfaceVariant,
                                                        ),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              tooltip: _helpVisible ? 'Hide filter help' : 'Show filter help',
              onPressed: () => setState(() => _helpVisible = !_helpVisible),
              icon: Icon(_helpVisible ? Icons.help : Icons.help_outline),
            ),
          ],
        ),
        _buildHelpSection(context),
      ],
    );
  }
}

class _InlineFilterSuggestion {
  const _InlineFilterSuggestion({
    required this.label,
    required this.subtitle,
    required this.icon,
    this.level,
    required this.replacementText,
    required this.addTrailingSpace,
    required this.applyImmediately,
    required this.reopenSuggestions,
  });

  final String label;
  final String subtitle;
  final IconData icon;
  final LogLevel? level;
  final String replacementText;
  final bool addTrailingSpace;
  final bool applyImmediately;
  final bool reopenSuggestions;
}

class _InlineFilterValueCandidate {
  const _InlineFilterValueCandidate({
    required this.value,
    required this.subtitle,
  });

  final String value;
  final String subtitle;
}

class _InlineFilterKeyDefinition {
  const _InlineFilterKeyDefinition({
    required this.canonicalKey,
    required this.aliases,
    required this.icon,
    required this.label,
    required this.description,
  });

  const _InlineFilterKeyDefinition.unknown()
    : canonicalKey = null,
      aliases = const <String>{},
      icon = Icons.help_outline,
      label = '',
      description = '';

  final String? canonicalKey;
  final Set<String> aliases;
  final IconData icon;
  final String label;
  final String description;
}

class _InlineFilterContext {
  const _InlineFilterContext({
    required this.activeToken,
    required this.cursorOffset,
  });

  final _InlineFilterToken activeToken;
  final int cursorOffset;

  static _InlineFilterContext fromEditingValue(TextEditingValue value) {
    final text = value.text;
    final cursor = value.selection.isValid
        ? value.selection.extentOffset.clamp(0, text.length)
        : text.length;
    final tokens = scanTokens(text);
    final activeToken = tokens.firstWhere(
      (token) => cursor >= token.start && cursor <= token.end,
      orElse: () => _InlineFilterToken(start: cursor, end: cursor, text: ''),
    );
    return _InlineFilterContext(activeToken: activeToken, cursorOffset: cursor);
  }

  static List<_InlineFilterToken> scanTokens(String text) {
    final tokens = <_InlineFilterToken>[];
    var start = -1;
    var inQuotes = false;
    for (var index = 0; index < text.length; index++) {
      final char = text[index];
      if (char == '"') {
        inQuotes = !inQuotes;
      }
      if (!inQuotes && char.trim().isEmpty) {
        if (start >= 0) {
          tokens.add(
            _InlineFilterToken(
              start: start,
              end: index,
              text: text.substring(start, index),
            ),
          );
          start = -1;
        }
        continue;
      }
      if (start < 0) {
        start = index;
      }
    }
    if (start >= 0) {
      tokens.add(
        _InlineFilterToken(
          start: start,
          end: text.length,
          text: text.substring(start),
        ),
      );
    }
    return tokens;
  }
}

class _InlineFilterToken {
  const _InlineFilterToken({
    required this.start,
    required this.end,
    required this.text,
  });

  final int start;
  final int end;
  final String text;
}
