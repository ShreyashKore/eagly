import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../presentation/components/anchored_popover.dart';
import '../../data/models/filter_condition.dart';
import '../../data/models/log_filters.dart';
import 'log_filter_controller.dart';
import 'log_filter_parts.dart';

/// Edits one [FilterCondition]: "Package  contains ▾  🗑" over the value
/// field. The operator opens as a list inside the card (popovers don't nest);
/// otherwise the card lists recent and known values for the field.
class const FilterConditionEditor({
  super.key,
  required final LogFilterController controller,
  required final int conditionId,
  required final VoidCallback onDone,
  required final VoidCallback onRemove,
}) extends StatefulWidget {
  @override
  State<FilterConditionEditor> createState() => _FilterConditionEditorState();
}

class _FilterConditionEditorState extends State<FilterConditionEditor> {
  late final TextEditingController _text = TextEditingController(
    text: _condition?.value ?? '',
  );
  final FocusNode _textFocus = FocusNode();
  bool _choosingOperator = false;

  /// The suggestion ↓ / ↑ have moved to, which ↵ picks; -1 while ↵
  /// still takes the typed value. The caret stays in the field either way,
  /// so typing narrows the list (and starts over from the field).
  int _highlighted = -1;

  FilterCondition? get _condition => widget.controller.conditions
      .where((condition) => condition.id == widget.conditionId)
      .firstOrNull;

  List<String> _suggestions(FilterCondition condition) => _choosingOperator
      ? const <String>[]
      : suggestedFilterValues(widget.controller, condition.field, _text.text);

  void _pick(FilterCondition condition, String suggestion) {
    _text.text = suggestion;
    widget.controller.updateCondition(condition.id, value: suggestion);
    widget.onDone();
  }

  KeyEventResult _onKey(KeyEvent event) {
    final condition = _condition;
    if (condition == null ||
        (event is! KeyDownEvent && event is! KeyRepeatEvent)) {
      return KeyEventResult.ignored;
    }
    // Built from the live text, not the last frame's list.
    final suggestions = _suggestions(condition);
    if (suggestions.isEmpty) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed ||
        keyboard.isMetaPressed ||
        keyboard.isAltPressed) {
      return KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.tab) {
      // Tab moves the focus on, as everywhere else; the highlight goes too.
      if (_highlighted >= 0) setState(() => _highlighted = -1);
      return KeyEventResult.ignored;
    }

    final int? step = switch (key) {
      LogicalKeyboardKey.arrowDown when !keyboard.isShiftPressed => 1,
      LogicalKeyboardKey.arrowUp when !keyboard.isShiftPressed => -1,
      _ => null,
    };
    if (step != null) {
      // The field is the stop before the first suggestion and after the
      // last, so the list cycles through it.
      final stops = suggestions.length + 1;
      setState(() => _highlighted = (_highlighted + 1 + step) % stops - 1);
      return KeyEventResult.handled;
    }
    if (_highlighted < 0 || _highlighted >= suggestions.length) {
      return KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      _pick(condition, suggestions[_highlighted]);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      setState(() => _highlighted = -1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    _text.dispose();
    _textFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final condition = _condition;
        if (condition == null) return const SizedBox.shrink();
        return _buildEditor(context, condition);
      },
    );
  }

  Widget _buildEditor(BuildContext context, FilterCondition condition) {
    final field = condition.field;
    final operator = condition.operator;
    final canChooseOperator = field.operators.length > 1;
    final invalidRegex = condition.toTerm()?.hasInvalidRegex ?? false;
    final suggestions = _suggestions(condition);
    final appIcons = showsFilterAppIcons(widget.controller, field);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilterEditorHeader(
          icon: filterFieldIcon(field),
          label: field.label(isIos: widget.controller.isIos),
          onRemove: widget.onRemove,
          operator: _OperatorButton(
            label: operator.label,
            negated: operator.negate,
            open: _choosingOperator,
            onPressed: canChooseOperator
                ? () => setState(() {
                    _choosingOperator = !_choosingOperator;
                    _highlighted = -1;
                  })
                : null,
          ),
        ),
        const SizedBox(height: 10),
        if (_choosingOperator)
          for (final option in field.operators)
            FilterMenuRow(
              highlighted: option == operator,
              trailing: option == operator
                  ? Icon(
                      Icons.check,
                      size: 15,
                      color: Theme.of(context).colorScheme.primary,
                    )
                  : null,
              onTap: () {
                widget.controller.updateCondition(
                  condition.id,
                  operator: option,
                );
                setState(() => _choosingOperator = false);
                _textFocus.requestFocus();
              },
              child: Text(
                option.label,
                style: TextStyle(
                  color: option.negate
                      ? Theme.of(context).colorScheme.error
                      : null,
                ),
              ),
            )
        else ...[
          Focus(
            onKeyEvent: (node, event) => _onKey(event),
            skipTraversal: true,
            child: TextField(
              controller: _text,
              focusNode: _textFocus,
              autofocus: true,
              contextMenuBuilder: AnchoredPopover.textContextMenuBuilder,
              style: const TextStyle(fontSize: 13),
              decoration: filterCardInputDecoration(
                context,
                hintText: switch (operator.mode) {
                  FilterMatchMode.contains => 'Type a value…',
                  FilterMatchMode.exact => 'The whole value…',
                  FilterMatchMode.regex => 'A regular expression…',
                },
                errorText: invalidRegex ? 'Invalid regular expression' : null,
              ),
              onChanged: (value) {
                setState(() => _highlighted = -1);
                widget.controller.updateCondition(condition.id, value: value);
              },
              onSubmitted: (_) => widget.onDone(),
            ),
          ),
          if (!canChooseOperator) ...[
            const SizedBox(height: 8),
            Text(
              'Matches text anywhere in the line.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (suggestions.isNotEmpty) ...[
            const SizedBox(height: 8),
            const FilterMenuSectionLabel('Suggestions'),
            for (final (i, suggestion) in suggestions.indexed)
              FilterMenuRow(
                icon: appIcons ? filterFieldIcon(field) : null,
                packageName: appIcons ? suggestion : null,
                highlighted: i == _highlighted,
                trailing: i == _highlighted ? const FilterEnterHint() : null,
                onTap: () => _pick(condition, suggestion),
                child: Text(
                  suggestion,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ],
      ],
    );
  }
}

/// The "contains ▾" control in an editor header.
class const _OperatorButton({
  required final String label,
  required final bool negated,
  required final bool open,
  required final VoidCallback? onPressed,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = negated ? colors.error : colors.onSurfaceVariant;
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: open ? colors.surfaceContainerHighest : null,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  color: color,
                  fontWeight: negated ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
            if (onPressed != null)
              Icon(
                open ? Icons.expand_less : Icons.expand_more,
                size: 16,
                color: color,
              ),
          ],
        ),
      ),
    );
  }
}
