import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/re_highlight.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';
import 'package:re_highlight/styles/atom-one-light.dart';

import '../theme/app_theme.dart';
import 'app_icon_button.dart';
import 'feature_view.dart';
import 'find_bar.dart';

/// Read-only text in a code view: syntax highlighting from [language], fold
/// markers for nested `{}` / `[]`, line numbers, and a find bar (⌘F / Ctrl+F,
/// or the search button) with case and regex toggles.
///
/// A toolbar sits on top: [leading] on the left, then [actions], then wrap,
/// find and copy. The editor highlights and folds in an isolate, so a widget
/// test reads what is shown from `CodeEditor.controller.text`.
class const CodeView({
  super.key,
  required final String text,

  /// The re_highlight grammar, or null for plain text.
  final Mode? language,

  /// Whether lines wrap when [text] first shows, and again whenever it
  /// changes; the wrap button overrides it in between.
  final bool wordWrap = true,

  /// Left of the toolbar, given the room the buttons leave.
  final Widget? leading,

  /// Buttons placed before wrap, find and copy.
  final List<Widget> actions = const [],

  /// What "copy" copies, when it isn't [text] as shown.
  final String? copyText,

  /// Names what is shown, as in "Find in body" and "Copy body".
  final String noun = 'text',

  /// When non-empty, the find bar opens already searching for it.
  final String? initialFind,
}) extends StatefulWidget {
  @override
  State<CodeView> createState() => _CodeViewState();
}

class _CodeViewState extends State<CodeView> {
  final CodeLineEditingController _editing = CodeLineEditingController();
  late final CodeFindController _find = CodeFindController(_editing);
  late final CodeScrollController _scroll = CodeScrollController(
    verticalScroller: ScrollController(),
    horizontalScroller: ScrollController(),
  );
  final FocusNode _editorFocus = FocusNode(debugLabel: 'Code view');
  late bool _wrap = widget.wordWrap;

  // re_editor paints every match in one colour, and marks the current one
  // only by selecting it — under that colour. So matches are painted
  // translucent, and while the selection *is* the current match it takes the
  // current-match colour, which then shows through as the stronger of the two.
  bool _selectionIsMatch = false;

  @override
  void initState() {
    super.initState();
    _editing.text = widget.text;
    final initialFind = widget.initialFind;
    if (initialFind != null && initialFind.isNotEmpty) {
      _find.findInputController.text = initialFind;
      _find.findMode();
    }
    _editing.addListener(_onEditingChanged);
    _find.addListener(_onFindChanged);
  }

  @override
  void didUpdateWidget(CodeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.text != oldWidget.text) {
      _editing.text = widget.text;
      _wrap = widget.wordWrap;
    }
  }

  @override
  void dispose() {
    _find.removeListener(_onFindChanged);
    _find.dispose();
    _editing.removeListener(_onEditingChanged);
    _editing.dispose();
    _scroll.verticalScroller.dispose();
    _scroll.horizontalScroller.dispose();
    _editorFocus.dispose();
    super.dispose();
  }

  void _onFindChanged() {
    if (mounted) setState(() {});
  }

  void _onEditingChanged() {
    final current = _find.currentMatchSelection;
    final isMatch = current != null && _editing.selection == current;
    if (isMatch != _selectionIsMatch && mounted) {
      setState(() => _selectionIsMatch = isMatch);
    }
  }

  void _toggleFind() {
    if (_find.value == null) {
      _find.findMode();
    } else {
      _find.close();
      _editorFocus.requestFocus();
    }
  }

  Future<void> _copyAll() async {
    await Clipboard.setData(
      ClipboardData(text: widget.copyText ?? widget.text),
    );
    if (mounted) FeatureView.showSnackBar(context, 'Copied ${widget.noun}.');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          constraints: BoxConstraints(minHeight: context.scaled(32)),
          padding: const EdgeInsets.only(left: 10, right: 4),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
          ),
          child: Row(
            spacing: 2,
            children: [
              Expanded(child: widget.leading ?? const SizedBox.shrink()),
              ...widget.actions,
              AppIconButton(
                tooltip: _wrap ? 'Don\'t wrap lines' : 'Wrap lines',
                icon: Icons.wrap_text,
                iconSize: 16,
                padding: 4,
                isActive: _wrap,
                onPressed: () => setState(() => _wrap = !_wrap),
              ),
              AppIconButton(
                tooltip: _find.value == null
                    ? 'Find in ${widget.noun} (${shortcutLabel('F')})'
                    : 'Close find (Esc)',
                icon: Icons.search,
                iconSize: 16,
                padding: 4,
                isActive: _find.value != null,
                onPressed: _toggleFind,
              ),
              AppIconButton(
                tooltip: 'Copy ${widget.noun}',
                icon: Icons.copy,
                iconSize: 16,
                padding: 4,
                onPressed: _copyAll,
              ),
            ],
          ),
        ),
        Expanded(child: _buildEditor(context)),
      ],
    );
  }

  Widget _buildEditor(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tokens = context.eaglyTheme;
    final isDark = theme.brightness == Brightness.dark;
    final fontSize = MediaQuery.textScalerOf(context).scale(12);
    final language = widget.language;
    final lineNumberStyle = tokens.monoStyle.copyWith(
      fontSize: fontSize,
      color: tokens.tertiaryTextColor,
    );

    return CodeEditor(
      controller: _editing,
      findController: _find,
      scrollController: _scroll,
      focusNode: _editorFocus,
      readOnly: true,
      autofocus: false,
      showCursorWhenReadOnly: false,
      wordWrap: _wrap,
      padding: const EdgeInsets.fromLTRB(4, 6, 12, 12),
      style: CodeEditorStyle(
        fontSize: fontSize,
        fontFamily: tokens.monoStyle.fontFamily,
        fontHeight: 1.45,
        textColor: cs.onSurface,
        backgroundColor: Colors.transparent,
        selectionColor: _selectionIsMatch
            ? tokens.searchCurrentMatchColor.withValues(
                alpha: isDark ? 0.7 : 0.9,
              )
            : cs.primary.withValues(alpha: 0.28),
        highlightColor: tokens.searchMatchColor.withValues(
          alpha: isDark ? 0.3 : 0.5,
        ),
        cursorLineColor: Colors.transparent,
        chunkIndicatorColor: tokens.tertiaryTextColor,
        codeTheme: language == null
            ? null
            : CodeHighlightTheme(
                languages: {'code': CodeHighlightThemeMode(mode: language)},
                theme: codeHighlightTheme(isDark, cs.onSurface),
              ),
      ),
      indicatorBuilder: (context, editing, chunks, notifier) => Row(
        children: [
          DefaultCodeLineNumber(
            controller: editing,
            notifier: notifier,
            textStyle: lineNumberStyle,
            focusedTextStyle: lineNumberStyle.copyWith(
              color: tokens.secondaryTextColor,
            ),
          ),
          DefaultCodeChunkIndicator(
            width: 18,
            controller: chunks,
            notifier: notifier,
            painter: DefaultCodeChunkIndicatorPainter(
              color: tokens.secondaryTextColor,
            ),
          ),
        ],
      ),
      findBuilder: (context, controller, readOnly) => _FindBar(
        controller: controller,
        editorFocus: _editorFocus,
        hint: 'Find in ${widget.noun}',
      ),
      toolbarController: _CodeContextMenu(
        onFind: () => _find.findMode(),
        onCopyAll: _copyAll,
        copyAllLabel: 'Copy whole ${widget.noun}',
      ),
    );
  }
}

/// The highlight.js palette for the current brightness, on the view's own
/// background rather than the theme's.
Map<String, TextStyle> codeHighlightTheme(bool dark, Color text) {
  final base = dark ? atomOneDarkTheme : atomOneLightTheme;
  return {...base, 'root': TextStyle(color: text)};
}

/// [FindBar] fed from re_editor's find controller, sized the way its
/// `findBuilder` asks.
class const _FindBar({
  required final CodeFindController controller,
  required final FocusNode editorFocus,
  required final String hint,
}) extends StatelessWidget implements PreferredSizeWidget {
  @override
  Size get preferredSize =>
      Size(double.infinity, controller.value == null ? 0 : FindBar.height);

  @override
  Widget build(BuildContext context) {
    final value = controller.value;
    if (value == null) return const SizedBox.shrink();
    final result = value.result;

    return FindBar(
      query: controller.findInputController,
      focusNode: controller.findInputFocusNode,
      hint: hint,
      caseSensitive: value.option.caseSensitive,
      regex: value.option.regex,
      onToggleCaseSensitive: controller.toggleCaseSensitive,
      onToggleRegex: controller.toggleRegex,
      matchCount: result?.matches.length ?? (value.searching ? null : 0),
      currentIndex: result?.index ?? 0,
      invalid: value.option.regex && value.option.regExp == null,
      onPrevious: controller.previousMatch,
      onNext: controller.nextMatch,
      onClose: () {
        controller.close();
        editorFocus.requestFocus();
      },
    );
  }
}

/// The right-click menu.
class const _CodeContextMenu({
  required final VoidCallback onFind,
  required final VoidCallback onCopyAll,
  required final String copyAllLabel,
}) implements SelectionToolbarController {
  @override
  void hide(BuildContext context) {}

  @override
  void show({
    required BuildContext context,
    required CodeLineEditingController controller,
    required TextSelectionToolbarAnchors anchors,
    Rect? renderRect,
    required LayerLink layerLink,
    required ValueNotifier<bool> visibility,
  }) {
    final hasSelection = !controller.selection.isCollapsed;
    final at = anchors.primaryAnchor;
    showMenu<void>(
      context: context,
      position: RelativeRect.fromLTRB(at.dx, at.dy, at.dx, at.dy),
      items: [
        PopupMenuItem(
          enabled: hasSelection,
          onTap: controller.copy,
          child: _MenuRow(
            Icons.content_copy,
            'Copy',
            shortcut: shortcutLabel('C'),
          ),
        ),
        PopupMenuItem(
          onTap: controller.selectAll,
          child: _MenuRow(
            Icons.select_all,
            'Select all',
            shortcut: shortcutLabel('A'),
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          onTap: onFind,
          child: _MenuRow(Icons.search, 'Find…', shortcut: shortcutLabel('F')),
        ),
        PopupMenuItem(
          onTap: onCopyAll,
          child: _MenuRow(Icons.copy_all, copyAllLabel),
        ),
      ],
    );
  }
}

class const _MenuRow(
  final IconData icon,
  final String label, {
  final String? shortcut,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16),
        const SizedBox(width: 10),
        Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
        if (shortcut != null) ...[
          const SizedBox(width: 24),
          Text(
            shortcut!,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: context.eaglyTheme.tertiaryTextColor),
          ),
        ],
      ],
    );
  }
}

/// A short, selectable snippet highlighted for [language] — for code shown
/// whole inline, where [CodeView]'s scrolling, line numbers and find would be
/// in the way.
class const HighlightedCodeText({
  super.key,
  required final String code,
  required final Mode language,
  required final TextStyle style,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final highlight = Highlight()..registerLanguage('code', language);
    final renderer = TextSpanRenderer(
      style,
      codeHighlightTheme(dark, style.color ?? Colors.black),
    );
    highlight.highlight(code: code, language: 'code').render(renderer);
    return SelectableText.rich(renderer.span ?? TextSpan(text: code));
  }
}
