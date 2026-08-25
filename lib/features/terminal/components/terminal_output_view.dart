import 'package:flutter/material.dart';

import '../../../presentation/theme/app_theme.dart';
import '../data/terminal_line.dart';

/// The scrollback: one styled, selectable line per [TerminalLine].
///
/// Sticks to the bottom while the user is at the bottom, and stops following
/// (offering a "jump to latest" pill instead) the moment they scroll up — so a
/// streaming command can't yank the view away from something being read.
class TerminalOutputView extends StatefulWidget {
  const TerminalOutputView({
    super.key,
    required this.lines,
    required this.fontSize,
  });

  final List<TerminalLine> lines;
  final double fontSize;

  @override
  State<TerminalOutputView> createState() => _TerminalOutputViewState();
}

class _TerminalOutputViewState extends State<TerminalOutputView> {
  static const _stickThreshold = 24.0;

  final ScrollController _scroll = ScrollController();
  bool _stickToBottom = true;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(TerminalOutputView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scrollToEndIfSticking();
  }

  @override
  void dispose() {
    _scroll.dispose();
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  void _jumpToEnd() {
    if (!_scroll.hasClients) return;
    setState(() => _stickToBottom = true);
    _scroll.jumpTo(_scroll.position.maxScrollExtent);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: SelectionArea(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              itemCount: widget.lines.length,
              itemBuilder: (context, index) => _TerminalLineView(
                line: widget.lines[index],
                fontSize: widget.fontSize,
              ),
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

class _TerminalLineView extends StatelessWidget {
  const _TerminalLineView({required this.line, required this.fontSize});

  final TerminalLine line;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final eaglyTheme = context.eaglyTheme;

    final color = switch (line.kind) {
      TerminalLineKind.command => theme.colorScheme.primary,
      TerminalLineKind.input => theme.colorScheme.tertiary,
      TerminalLineKind.stdout => theme.colorScheme.onSurface,
      TerminalLineKind.stderr => eaglyTheme.errorColor,
      TerminalLineKind.notice => theme.colorScheme.onSurfaceVariant,
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

    if (line.kind != TerminalLineKind.command &&
        line.kind != TerminalLineKind.input) {
      return Text(line.text, style: style);
    }

    // Prompt lines get the device label and a `$`, and — when a device
    // selector was injected — a tooltip with the command as actually run.
    final prefix = line.kind == TerminalLineKind.command
        ? '${line.prompt} \$ '
        : '> ';
    final body = Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: prefix,
            style: style.copyWith(
              color: color.withValues(alpha: 0.65),
              fontWeight: FontWeight.normal,
            ),
          ),
          TextSpan(text: line.text),
        ],
      ),
      style: style,
    );

    final resolved = line.resolved;
    if (resolved == null) return body;
    return Tooltip(message: resolved, child: body);
  }
}

class _JumpToLatestPill extends StatelessWidget {
  const _JumpToLatestPill({required this.onTap});

  final VoidCallback onTap;

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
