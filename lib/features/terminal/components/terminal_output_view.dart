import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

import '../../../presentation/components/search_highlight.dart';
import '../../logs/presentation/components/built_row_registry.dart';
import '../../../presentation/theme/app_theme.dart';
import '../../../utils/text_search_pattern.dart';
import '../data/terminal_line.dart';
import '../terminal_find.dart';

/// The scrollback: one styled, selectable line per [TerminalLine], with
/// [find]'s matches highlighted.
///
/// Sticks to the bottom while the user is at the bottom, and stops following
/// (offering a "jump to latest" pill instead) the moment they scroll up — so a
/// streaming command can't yank the view away from something being read.
/// Stepping through matches scrolls to the current one; output arriving
/// doesn't.
class const TerminalOutputView({
  super.key,
  required final List<TerminalLine> lines,
  required final TerminalFind find,
  required final double fontSize,
}) extends StatefulWidget {
  @override
  State<TerminalOutputView> createState() => _TerminalOutputViewState();
}

class _TerminalOutputViewState extends State<TerminalOutputView> {
  static const _stickThreshold = 24.0;

  final ScrollController _scroll = ScrollController();
  // Lines wrap, so only the list knows where line n is; this asks it.
  final ListController _list = ListController();
  bool _stickToBottom = true;
  late int _revealedMoves = widget.find.moves;

  /// The text selection over the scrollback; cleared before a rebuild drops
  /// lines it may be anchored in (see [BuiltRowRegistry]).
  final GlobalKey<SelectionAreaState> _selectionAreaKey =
      GlobalKey<SelectionAreaState>();

  /// Line numbers of the lines built right now, kept-alive ones too.
  final BuiltRowRegistry _builtLines = BuiltRowRegistry();

  /// The line number of `widget.lines[0]`: how many lines have scrolled off
  /// the front (or been cleared) since this view was built. A line's number
  /// stays put while the scrollback drops its head, so it keys the line's
  /// row and the row keeps its element — and the selection in it.
  int _firstLineNumber = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(TerminalOutputView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _firstLineNumber += _linesDropped(oldWidget.lines, widget.lines);
    // Before the rows rebuild: the scrollback cap or `clear` can take away a
    // line the selection is anchored in.
    final end = _firstLineNumber + widget.lines.length;
    if (_builtLines.anyRemoved((n) => n >= _firstLineNumber && n < end)) {
      _selectionAreaKey.currentState?.selectableRegion.clearSelection();
    }
    if (widget.find.moves != _revealedMoves) {
      _revealedMoves = widget.find.moves;
      _revealCurrentMatch();
    } else {
      _scrollToEndIfSticking();
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    _list.dispose();
    super.dispose();
  }

  /// How many of [old]'s lines are gone from the front of [next]. The
  /// scrollback only appends and drops its head (or empties), so that is
  /// where [next]'s first lines sit in [old]; all of them when they aren't
  /// there. A run is compared, not one line, because some lines are `const`
  /// and so the same object each time they are printed ("Stopped.").
  static int _linesDropped(List<TerminalLine> old, List<TerminalLine> next) {
    if (identical(old, next) || old.isEmpty) return 0;
    if (next.isEmpty) return old.length;
    bool startsAt(int k) {
      final run = math.min(8, math.min(old.length - k, next.length));
      for (var j = 0; j < run; j++) {
        if (!identical(old[k + j], next[j])) return false;
      }
      return true;
    }

    for (var k = 0; k < old.length; k++) {
      if (startsAt(k)) return k;
    }
    return old.length;
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    final atBottom =
        position.pixels >= position.maxScrollExtent - _stickThreshold;
    if (atBottom != _stickToBottom) setState(() => _stickToBottom = atBottom);
  }

  void _scrollToEndIfSticking() {
    if (!_stickToBottom) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _landOnTail());
  }

  void _jumpToEnd() {
    setState(() => _stickToBottom = true);
    _landOnTail();
  }

  // The list estimates the height of lines it hasn't laid out, so its
  // maxScrollExtent is partly a guess; jumping to the last item lands exactly.
  void _landOnTail() {
    if (!mounted || !_scroll.hasClients || !_list.isAttached) return;
    if (widget.lines.isEmpty) return;
    _list.jumpToItem(
      index: widget.lines.length - 1,
      scrollController: _scroll,
      alignment: 1.0,
    );
  }

  void _revealCurrentMatch() {
    final match = widget.find.current;
    if (match == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients || !_list.isAttached) return;
      final index = widget.lines.indexOf(match.line);
      if (index < 0) return;
      // Leave the view alone when the line is already in full view.
      final visible = _list.visibleRange;
      if (visible != null && index > visible.$1 && index < visible.$2) return;
      _list.jumpToItem(index: index, scrollController: _scroll, alignment: 0.5);
    });
  }

  @override
  Widget build(BuildContext context) {
    final find = widget.find;
    final current = find.current;

    return Stack(
      children: [
        Positioned.fill(
          child: SelectionArea(
            key: _selectionAreaKey,
            // A CustomScrollView rather than SuperListView, which can't pass
            // layoutKeptAliveChildren: a line holding part of the selection
            // is kept alive offscreen, and must keep being laid out or the
            // selection loses that edge (see LogViewer's list).
            child: CustomScrollView(
              controller: _scroll,
              semanticChildCount: widget.lines.length,
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  sliver: SuperSliverList.builder(
                    listController: _list,
                    layoutKeptAliveChildren: true,
                    delayPopulatingCacheArea: false,
                    itemCount: widget.lines.length,
                    findChildIndexCallback: (key) {
                      if (key is! ValueKey<int>) return null;
                      final index = key.value - _firstLineNumber;
                      return index >= 0 && index < widget.lines.length
                          ? index
                          : null;
                    },
                    itemBuilder: (context, index) {
                      final line = widget.lines[index];
                      final matches = find.matchesIn(line);
                      final number = _firstLineNumber + index;
                      return BuiltRowMarker(
                        key: ValueKey<int>(number),
                        id: number,
                        registry: _builtLines,
                        child: _TerminalLineView(
                          line: line,
                          fontSize: widget.fontSize,
                          matches: matches,
                          currentMatch:
                              current != null && identical(current.line, line)
                              ? matches.indexWhere(
                                  (m) => m.start == current.range.start,
                                )
                              : null,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        if (!_stickToBottom)
          Positioned(
            right: 16,
            bottom: 12,
            child: _JumpToLatestPill(onTap: _jumpToEnd),
          ),
      ],
    );
  }
}

class const _TerminalLineView({
  required final TerminalLine line,
  required final double fontSize,
  required final List<TextSearchMatch> matches,

  /// Index into [matches] of the find bar's current match, if it's here.
  required final int? currentMatch,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final eaglyTheme = context.eaglyTheme;

    final color = switch (line.kind) {
      TerminalLineKind.command => theme.colorScheme.primary,
      TerminalLineKind.input => theme.colorScheme.tertiary,
      TerminalLineKind.stdout => theme.colorScheme.onSurface,
      TerminalLineKind.stderr => eaglyTheme.errorColor,
      // The terminal's own voice (exit codes, built-ins) sits a step below
      // what the device printed.
      TerminalLineKind.notice => eaglyTheme.secondaryTextColor,
      TerminalLineKind.error => eaglyTheme.errorColor,
    };
    final isEmphasised =
        line.kind == TerminalLineKind.command ||
        line.kind == TerminalLineKind.error;

    final style = eaglyTheme.monoStyle.copyWith(
      fontSize: fontSize,
      height: 1.45,
      color: color,
      fontWeight: isEmphasised ? FontWeight.w600 : FontWeight.normal,
    );

    // Matches cover the line's own text, never the prompt prefix.
    final text = matches.isEmpty
        ? TextSpan(text: line.text)
        : TextSpan(
            children: buildSearchHighlightSpans(
              context: context,
              text: line.text,
              style: style,
              matches: matches,
              currentMatchIndex: currentMatch,
            ),
          );

    if (line.kind != TerminalLineKind.command &&
        line.kind != TerminalLineKind.input) {
      return Text.rich(text, style: style);
    }

    // Prompt lines get the device label and a `$`, and — when a device
    // selector was injected — a tooltip with the command as actually run.
    // The prefix is neutral tertiary so the command itself is what reads.
    final prefix = line.kind == TerminalLineKind.command
        ? '${line.prompt} \$ '
        : '> ';
    final body = Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: prefix,
            style: style.copyWith(
              color: eaglyTheme.tertiaryTextColor,
              fontWeight: FontWeight.normal,
            ),
          ),
          text,
        ],
      ),
      style: style,
    );

    final resolved = line.resolved;
    if (resolved == null) return body;
    return Tooltip(message: resolved, child: body);
  }
}

class const _JumpToLatestPill({required final VoidCallback onTap})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.secondaryContainer,
      borderRadius: BorderRadius.circular(20),
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        mouseCursor: SystemMouseCursors.click,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.vertical_align_bottom,
                size: 14,
                color: theme.colorScheme.onSecondaryContainer,
              ),
              const SizedBox(width: 6),
              Text(
                'Jump to latest',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSecondaryContainer,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
