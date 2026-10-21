import 'package:flutter/material.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

import '../../../presentation/components/search_highlight.dart';
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

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(TerminalOutputView oldWidget) {
    super.didUpdateWidget(oldWidget);
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
            child: SuperListView.builder(
              controller: _scroll,
              listController: _list,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              itemCount: widget.lines.length,
              itemBuilder: (context, index) {
                final line = widget.lines[index];
                final matches = find.matchesIn(line);
                return _TerminalLineView(
                  line: line,
                  fontSize: widget.fontSize,
                  matches: matches,
                  currentMatch: current != null && identical(current.line, line)
                      ? matches.indexWhere(
                          (m) => m.start == current.range.start,
                        )
                      : null,
                );
              },
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
