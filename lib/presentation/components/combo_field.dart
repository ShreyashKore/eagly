import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../command_palette/fuzzy_match.dart';
import '../../utils/text_search_pattern.dart';
import 'app_icon_button.dart';
import 'search_highlight.dart';

/// One entry in a [ComboField]'s list.
@immutable
class ComboOption {
  const ComboOption({
    required this.value,
    required this.label,
    this.description,
  });

  /// What picking the entry writes into the field.
  final String value;

  /// What the list shows.
  final String label;

  /// Optional second line under [label].
  final String? description;
}

/// A text field with a searchable list of [options] attached — a combobox.
///
/// Typing filters and ranks the list (by [ComboOption.label],
/// [ComboOption.value] and [ComboOption.description], highlighting what
/// matched), and anything typed is kept as-is: the options are a shortcut,
/// never a whitelist. The list opens on a click in the field, on typing, on
/// ↓ and from the trailing arrow (which lists every option, whatever has been
/// typed) — not on bare focus, so an autofocused field doesn't cover the
/// form. Once open it is driven by the keyboard:
/// ↑ / ↓ move the highlight, Enter picks it, Esc closes the list (a second
/// Esc reaches the enclosing dialog). With the list closed, Enter calls
/// [onSubmitted].
class ComboField extends StatefulWidget {
  const ComboField({
    super.key,
    required this.controller,
    required this.options,
    this.decoration = const InputDecoration(),
    this.autofocus = false,
    this.onChanged,
    this.onSubmitted,
    this.maxListHeight = 280,
  });

  final TextEditingController controller;
  final List<ComboOption> options;
  final InputDecoration decoration;
  final bool autofocus;

  /// Called when the text changes, by typing or by picking an option.
  final ValueChanged<String>? onChanged;

  /// Enter with the list closed (or with nothing highlighted).
  final ValueChanged<String>? onSubmitted;

  final double maxListHeight;

  /// Ranks [options] against [query]: label prefix, then a word in the label
  /// or value starting with it, then a plain substring anywhere — and only
  /// when nothing contains the query, a fuzzy (subsequence) match on the
  /// label. Order within a tier is the options' own order.
  @visibleForTesting
  static List<ComboOption> filter(List<ComboOption> options, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return options;

    int? tier(ComboOption option) {
      final label = option.label.toLowerCase();
      final value = option.value.toLowerCase();
      final description = option.description?.toLowerCase() ?? '';
      if (label.startsWith(q) || value == q) return 0;
      if (_startsWord(label, q) || _startsWord(value, q)) return 1;
      if (label.contains(q) || value.contains(q) || description.contains(q)) {
        return 2;
      }
      return null;
    }

    final tiers = <int, List<ComboOption>>{};
    for (final option in options) {
      final t = tier(option);
      if (t != null) (tiers[t] ??= []).add(option);
    }
    if (tiers.isNotEmpty) {
      return [for (final t in tiers.keys.toList()..sort()) ...tiers[t]!];
    }

    final scored = [
      for (final option in options)
        if (fuzzyScore(q, option.label) case final score?) (option, score),
    ]..sort((a, b) => b.$2.compareTo(a.$2));
    return [for (final (option, _) in scored) option];
  }

  static bool _startsWord(String text, String q) {
    var from = 0;
    while (true) {
      final at = text.indexOf(q, from);
      if (at < 0) return false;
      if (at == 0 || !_isWordChar(text.codeUnitAt(at - 1))) return true;
      from = at + 1;
    }
  }

  static bool _isWordChar(int code) =>
      (code >= 0x30 && code <= 0x39) ||
      (code >= 0x41 && code <= 0x5a) ||
      (code >= 0x61 && code <= 0x7a);

  @override
  State<ComboField> createState() => _ComboFieldState();
}

class _ComboFieldState extends State<ComboField> {
  final _focusNode = FocusNode(debugLabel: 'ComboField');
  final _portal = OverlayPortalController();
  final _link = LayerLink();
  final _scroll = ScrollController();
  final _fieldKey = GlobalKey();

  /// What the open list is filtered by; empty lists every option.
  String _query = '';
  int _highlighted = -1;
  List<ComboOption> _matches = const [];

  bool get _isOpen => _portal.isShowing;

  @override
  void initState() {
    super.initState();
    _matches = widget.options;
    _focusNode.addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(ComboField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.options != widget.options) _refresh();
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    _focusNode.dispose();
    _scroll.dispose();
    super.dispose();
  }

  List<ComboOption> _computeMatches() =>
      ComboField.filter(widget.options, _query);

  void _refresh() {
    setState(() {
      _matches = _computeMatches();
      _highlighted = _matches.isEmpty
          ? -1
          : _highlighted.clamp(0, _matches.length - 1);
    });
    if (_matches.isEmpty) _close();
  }

  void _handleFocusChange() {
    if (!_focusNode.hasFocus) _close();
  }

  void _open({bool showAll = false}) {
    if (widget.options.isEmpty) return;
    // A field holding exactly one of the values is a selection, not a
    // search: reopening lists everything with that value highlighted.
    final text = widget.controller.text.trim();
    _query = showAll || widget.options.any((o) => o.value == text) ? '' : text;
    final matches = _computeMatches();
    if (matches.isEmpty) return;
    setState(() {
      _matches = matches;
      // Land on the option the field already holds, if it is in the list.
      final current = matches.indexWhere(
        (o) => o.value == widget.controller.text.trim(),
      );
      _highlighted = current >= 0 ? current : 0;
    });
    _portal.show();
    _scrollToHighlighted();
  }

  void _close() {
    if (!_isOpen) return;
    _portal.hide();
    setState(() => _highlighted = -1);
  }

  void _toggleAll() {
    if (_isOpen) {
      _close();
      return;
    }
    _focusNode.requestFocus();
    _open(showAll: true);
  }

  void _handleChanged(String text) {
    _query = text.trim();
    _matches = _computeMatches();
    if (_matches.isEmpty) {
      _close();
    } else {
      setState(() => _highlighted = 0);
      if (!_isOpen) _portal.show();
      _scrollToHighlighted();
    }
    widget.onChanged?.call(text);
  }

  void _pick(ComboOption option) {
    widget.controller.value = TextEditingValue(
      text: option.value,
      selection: TextSelection.collapsed(offset: option.value.length),
    );
    _close();
    widget.onChanged?.call(option.value);
  }

  void _move(int delta) {
    if (!_isOpen) {
      _open();
      return;
    }
    if (_matches.isEmpty) return;
    setState(() {
      _highlighted = (_highlighted + delta) % _matches.length;
      if (_highlighted < 0) _highlighted += _matches.length;
    });
    _scrollToHighlighted();
  }

  void _handleSubmitted(String text) {
    if (_isOpen && _highlighted >= 0 && _highlighted < _matches.length) {
      _pick(_matches[_highlighted]);
      // Enter left the field; keep typing where the user was.
      _focusNode.requestFocus();
      return;
    }
    widget.onSubmitted?.call(text);
  }

  // ── List geometry ─────────────────────────────────────────────────────────

  bool get _hasDescriptions => widget.options.any((o) => o.description != null);

  double get _itemExtent => _hasDescriptions ? 48 : 36;

  void _scrollToHighlighted() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients || _highlighted < 0) return;
      final position = _scroll.position;
      final top = _highlighted * _itemExtent;
      final bottom = top + _itemExtent;
      if (top < position.pixels) {
        _scroll.jumpTo(top);
      } else if (bottom > position.pixels + position.viewportDimension) {
        _scroll.jumpTo(bottom - position.viewportDimension);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasOptions = widget.options.isNotEmpty;

    final field = TextField(
      key: _fieldKey,
      controller: widget.controller,
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      decoration: widget.decoration.copyWith(
        suffixIcon: AppIconButton(
          tooltip: _isOpen ? 'Hide suggestions' : 'Show all suggestions',
          iconSize: 20,
          onPressed: hasOptions ? _toggleAll : null,
          icon: _isOpen ? Icons.arrow_drop_up : Icons.arrow_drop_down,
        ),
      ),
      onTap: () {
        if (!_isOpen) _open();
      },
      // Desktop text fields keep focus on a click elsewhere, so close the
      // list explicitly. Clicks in the list are inside this tap region.
      onTapOutside: (_) => _close(),
      onChanged: _handleChanged,
      onSubmitted: _handleSubmitted,
    );

    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.arrowDown): _MoveIntent(1),
        SingleActivator(LogicalKeyboardKey.arrowUp): _MoveIntent(-1),
        SingleActivator(LogicalKeyboardKey.pageDown): _MoveIntent(6),
        SingleActivator(LogicalKeyboardKey.pageUp): _MoveIntent(-6),
        SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
      },
      child: Actions(
        actions: {
          _MoveIntent: CallbackAction<_MoveIntent>(
            onInvoke: (intent) => _move(intent.delta),
          ),
          // Enabled only while the list is open, so a second Esc falls
          // through to the dialog and closes it.
          DismissIntent: _CloseListAction(isOpen: () => _isOpen, close: _close),
        },
        child: CompositedTransformTarget(
          link: _link,
          child: OverlayPortal(
            controller: _portal,
            overlayChildBuilder: _buildList,
            child: field,
          ),
        ),
      ),
    );
  }

  Widget _buildList(BuildContext context) {
    final theme = Theme.of(context);
    final box = _fieldKey.currentContext?.findRenderObject() as RenderBox?;
    final width = box?.size.width ?? 320;

    return CompositedTransformFollower(
      link: _link,
      showWhenUnlinked: false,
      targetAnchor: Alignment.bottomLeft,
      offset: const Offset(0, 4),
      child: Align(
        alignment: Alignment.topLeft,
        // Same group as the field: a click in the list doesn't count as a
        // click outside it, so the field keeps focus.
        child: TextFieldTapRegion(
          child: SizedBox(
            width: width,
            child: Material(
              elevation: 8,
              color: theme.colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(8),
              clipBehavior: Clip.antiAlias,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: widget.maxListHeight),
                child: ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  shrinkWrap: true,
                  itemExtent: _itemExtent,
                  itemCount: _matches.length,
                  itemBuilder: (context, index) => _ComboRow(
                    option: _matches[index],
                    query: _query,
                    highlighted: index == _highlighted,
                    onTap: () => _pick(_matches[index]),
                    onHover: () => setState(() => _highlighted = index),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MoveIntent extends Intent {
  const _MoveIntent(this.delta);

  final int delta;
}

class _CloseListAction extends Action<DismissIntent> {
  _CloseListAction({required this.isOpen, required this.close});

  final bool Function() isOpen;
  final VoidCallback close;

  @override
  bool isEnabled(DismissIntent intent) => isOpen();

  @override
  Object? invoke(DismissIntent intent) {
    close();
    return null;
  }
}

class _ComboRow extends StatelessWidget {
  const _ComboRow({
    required this.option,
    required this.query,
    required this.highlighted,
    required this.onTap,
    required this.onHover,
  });

  final ComboOption option;
  final String query;
  final bool highlighted;
  final VoidCallback onTap;
  final VoidCallback onHover;

  List<InlineSpan> _spans(BuildContext context, String text, TextStyle style) {
    final matches = <TextSearchMatch>[];
    if (query.isNotEmpty) {
      final lower = text.toLowerCase();
      final q = query.toLowerCase();
      var from = 0;
      while (true) {
        final at = lower.indexOf(q, from);
        if (at < 0) break;
        matches.add(TextSearchMatch(start: at, end: at + q.length));
        from = at + q.length;
      }
    }
    return buildSearchHighlightSpans(
      context: context,
      text: text,
      style: style,
      matches: matches,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final description = option.description;
    final labelStyle = theme.textTheme.bodyMedium!.copyWith(
      color: cs.onSurface,
    );
    final descriptionStyle = theme.textTheme.bodySmall!.copyWith(
      color: cs.onSurfaceVariant,
      fontFamily: 'monospace',
      fontSize: 11,
    );

    return MouseRegion(
      onEnter: (_) => onHover(),
      child: InkWell(
        onTap: onTap,
        canRequestFocus: false,
        mouseCursor: SystemMouseCursors.click,
        child: Container(
          color: highlighted
              ? cs.primaryContainer.withValues(alpha: 0.6)
              : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.centerLeft,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                TextSpan(children: _spans(context, option.label, labelStyle)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (description != null)
                Text.rich(
                  TextSpan(
                    children: _spans(context, description, descriptionStyle),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
