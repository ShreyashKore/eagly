import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/css.dart';
import 'package:re_highlight/languages/graphql.dart';
import 'package:re_highlight/languages/javascript.dart';
import 'package:re_highlight/languages/json.dart';
import 'package:re_highlight/languages/xml.dart';
import 'package:re_highlight/languages/yaml.dart';
import 'package:re_highlight/re_highlight.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';
import 'package:re_highlight/styles/atom-one-light.dart';

import '../../../presentation/components/app_icon_button.dart';
import '../../../presentation/theme/app_theme.dart';
import '../../../utils/utils.dart';
import '../data/network_transaction.dart';
import '../data/network_transaction_store.dart';
import '../network_controller.dart';
import 'network_presentation.dart';

/// One request or response body, fetched from its source the first time it
/// is shown, in a read-only code view: syntax highlighting picked from the
/// content type (or sniffed), fold markers for nested `{}` / `[]`, line
/// numbers, and a find bar (⌘F / Ctrl+F, or the search button) with case and
/// regex toggles. JSON and form bodies can be shown pretty-printed or raw;
/// images are previewed, and other binary bodies are shown as a hex dump.
class const NetworkBodyView({
  super.key,
  required final NetworkController controller,
  required final NetworkTransactionKey entryKey,
  required final NetworkBodyPart part,
  required final NetworkBodyState state,
  final String? contentType,
}) extends StatefulWidget {
  @override
  State<NetworkBodyView> createState() => _NetworkBodyViewState();
}

class _NetworkBodyViewState extends State<NetworkBodyView> {
  @override
  void initState() {
    super.initState();
    _ensureLoading();
  }

  @override
  void didUpdateWidget(NetworkBodyView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _ensureLoading();
  }

  /// Starts the fetch if nothing has asked for this body yet. Failures show
  /// through the controller's [NetworkBodyFailed], so the future's own error
  /// is dropped here.
  void _ensureLoading() {
    if (!widget.state.isFetchable) return;
    if (widget.controller.bodyLoad(widget.entryKey, widget.part) != null) {
      return;
    }
    widget.controller
        .loadBody(widget.entryKey, widget.part)
        .then<void>((_) {}, onError: (_) {});
  }

  @override
  Widget build(BuildContext context) {
    switch (widget.state) {
      case NetworkBodyState.empty:
        return const NetworkPlaceholder('No body');
      case NetworkBodyState.notCaptured:
        return const NetworkPlaceholder(
          'Not captured. The app\'s capture level, a streamed body or a '
          'filter left it out.',
        );
      case NetworkBodyState.available || NetworkBodyState.truncated:
        break;
    }

    final load = widget.controller.bodyLoad(widget.entryKey, widget.part);
    switch (load) {
      case null || NetworkBodyLoading():
        return const Center(
          child: SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      case NetworkBodyFailed(:final message):
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              NetworkPlaceholder('Could not load the body: $message'),
              TextButton(
                onPressed: () {
                  widget.controller.retryBody(widget.entryKey, widget.part);
                  _ensureLoading();
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        );
      case NetworkBodyLoaded(:final body):
        return _LoadedBody(
          body: body,
          contentType: widget.contentType,
          truncated:
              body.truncated || widget.state == NetworkBodyState.truncated,
        );
    }
  }
}

/// Grey explanatory text in place of content.
class const NetworkPlaceholder(final String text, {super.key})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: context.eaglyTheme.tertiaryTextColor),
      ),
    );
  }
}

/// How a body is shown, and with which highlighting.
enum BodyLanguage(final String label) {
  json('JSON'),
  xml('XML'),
  html('HTML'),
  javascript('JavaScript'),
  css('CSS'),
  yaml('YAML'),
  graphql('GraphQL'),
  form('Form data'),
  text('Text'),
  hex('Hex'),
  image('Image');

  /// The re_highlight grammar, or null for no highlighting.
  Mode? get grammar => switch (this) {
    json => langJson,
    xml || html => langXml,
    javascript => langJavascript,
    css => langCss,
    yaml => langYaml,
    graphql => langGraphql,
    form || text || hex || image => null,
  };

  /// The language for [contentType], or for [text] when the content type is
  /// missing or says nothing more specific than text.
  static BodyLanguage detect(String? contentType, String? text) {
    final type = contentType?.split(';').first.trim().toLowerCase() ?? '';
    if (type.startsWith('image/') && !type.contains('svg')) return image;
    if (text == null) return hex;
    if (type.endsWith('json')) return json;
    if (type.contains('html')) return html;
    if (type.endsWith('xml')) return xml;
    if (type.contains('javascript') || type.contains('ecmascript')) {
      return javascript;
    }
    if (type.endsWith('css')) return css;
    if (type.contains('yaml')) return yaml;
    if (type.contains('graphql')) return graphql;
    if (type == 'application/x-www-form-urlencoded') return form;
    final trimmed = text.trimLeft();
    if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
      if (_tryPrettyJson(trimmed) != null) return json;
    }
    if (trimmed.startsWith('<')) {
      return trimmed.toLowerCase().startsWith('<!doctype html') ||
              trimmed.toLowerCase().startsWith('<html')
          ? html
          : xml;
    }
    return BodyLanguage.text;
  }
}

/// A body made ready for the code view: its text as sent, and a
/// pretty-printed form where one exists.
class const _Document({
  required final String raw,
  required final BodyLanguage language,
  final String? pretty,
});

/// Bodies above this size are prepared off the UI thread.
const _backgroundThreshold = 256 * 1024;

/// The most bytes shown as a hex dump; the rest is summarised.
const _hexLimit = 64 * 1024;

_Document _prepare((Uint8List, String?) input) {
  final (bytes, contentType) = input;
  final text = NetworkBody(bytes: bytes).text;
  final language = BodyLanguage.detect(contentType, text);
  if (language == BodyLanguage.image) {
    return const _Document(raw: '', language: BodyLanguage.image);
  }
  if (text == null) {
    return _Document(raw: hexDump(bytes), language: BodyLanguage.hex);
  }
  final pretty = switch (language) {
    BodyLanguage.json => _tryPrettyJson(text.trimLeft()),
    BodyLanguage.form => _prettyForm(text),
    _ => null,
  };
  return _Document(
    raw: text,
    language: language,
    pretty: pretty == text ? null : pretty,
  );
}

String? _tryPrettyJson(String text) {
  try {
    return const JsonEncoder.withIndent('  ').convert(jsonDecode(text));
  } on FormatException {
    return null;
  }
}

String? _prettyForm(String text) {
  try {
    return Uri.splitQueryString(text.trim()).entries
        .map((e) => '${e.key}: ${e.value}')
        .join('\n');
  } on FormatException {
    return null;
  }
}

/// [bytes] as `offset  hex bytes  ascii` rows of 16, up to [_hexLimit].
@visibleForTesting
String hexDump(Uint8List bytes) {
  final buffer = StringBuffer();
  final shown = bytes.length > _hexLimit ? _hexLimit : bytes.length;
  for (var offset = 0; offset < shown; offset += 16) {
    final end = offset + 16 > shown ? shown : offset + 16;
    buffer.write(offset.toRadixString(16).padLeft(8, '0'));
    buffer.write('  ');
    for (var i = offset; i < offset + 16; i++) {
      buffer.write(
        i < end ? '${bytes[i].toRadixString(16).padLeft(2, '0')} ' : '   ',
      );
      if (i == offset + 7) buffer.write(' ');
    }
    buffer.write(' ');
    for (var i = offset; i < end; i++) {
      final byte = bytes[i];
      buffer.writeCharCode(byte >= 0x20 && byte < 0x7f ? byte : 0x2e);
    }
    if (end < shown) buffer.write('\n');
  }
  if (bytes.length > shown) {
    buffer.write('\n… ${formatBytes(bytes.length - shown)} more not shown');
  }
  return buffer.toString();
}

class const _LoadedBody({
  required final NetworkBody body,
  required final String? contentType,
  required final bool truncated,
}) extends StatefulWidget {
  @override
  State<_LoadedBody> createState() => _LoadedBodyState();
}

class _LoadedBodyState extends State<_LoadedBody> {
  final CodeLineEditingController _editing = CodeLineEditingController();
  late final CodeFindController _find = CodeFindController(_editing);
  late final CodeScrollController _scroll = CodeScrollController(
    verticalScroller: ScrollController(),
    horizontalScroller: ScrollController(),
  );
  final FocusNode _editorFocus = FocusNode(debugLabel: 'Network body');

  NetworkBody? _preparedFor;
  _Document? _document;
  bool _pretty = true;
  bool _wrap = true;

  @override
  void initState() {
    super.initState();
    _find.addListener(_onFindChanged);
    _prepareDocument();
  }

  @override
  void didUpdateWidget(_LoadedBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.body, _preparedFor)) _prepareDocument();
  }

  @override
  void dispose() {
    _find.removeListener(_onFindChanged);
    _find.dispose();
    _editing.dispose();
    _scroll.verticalScroller.dispose();
    _scroll.horizontalScroller.dispose();
    _editorFocus.dispose();
    super.dispose();
  }

  void _onFindChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _prepareDocument() async {
    final body = widget.body;
    _preparedFor = body;
    final input = (body.bytes, widget.contentType);
    final document = body.bytes.length > _backgroundThreshold
        ? await Isolate.run(() => _prepare(input))
        : _prepare(input);
    if (!mounted || !identical(body, _preparedFor)) return;
    setState(() {
      _document = document;
      // A long single-line body wraps into a wall; a pretty one reads
      // better unwrapped, like an editor.
      _wrap = document.pretty == null;
      _editing.text = _shownText(document);
    });
  }

  String _shownText(_Document document) =>
      _pretty ? document.pretty ?? document.raw : document.raw;

  void _togglePretty() {
    final document = _document;
    if (document == null) return;
    setState(() {
      _pretty = !_pretty;
      _wrap = !_pretty;
      _editing.text = _shownText(document);
    });
  }

  void _toggleFind() {
    if (_find.value == null) {
      _find.findMode();
    } else {
      _find.close();
      _editorFocus.requestFocus();
    }
  }

  Future<void> _copyAll() => copyWithToast(
    context,
    _document?.language == BodyLanguage.hex
        ? _document!.raw
        : (NetworkBody(bytes: widget.body.bytes).text ?? ''),
    'Copied body.',
  );

  @override
  Widget build(BuildContext context) {
    final document = _document;
    if (document == null) {
      return const Center(
        child: SizedBox.square(
          dimension: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    final theme = Theme.of(context);
    final tokens = context.eaglyTheme;
    final isImage = document.language == BodyLanguage.image;
    final size = widget.body.bytes.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: context.scaled(32),
          padding: const EdgeInsets.only(left: 10, right: 4),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
          ),
          child: Row(
            spacing: 2,
            children: [
              _Badge(document.language.label),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  [
                    formatBytes(size),
                    if (widget.truncated)
                      'cut by the app\'s capture limit'
                          '${widget.body.originalSize == null ? '' : ' (${formatBytes(widget.body.originalSize!)} in all)'}',
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: widget.truncated
                        ? tokens.warningColor
                        : tokens.tertiaryTextColor,
                  ),
                ),
              ),
              const Spacer(),
              if (document.pretty != null)
                AppIconButton(
                  tooltip: _pretty ? 'Show as sent' : 'Pretty-print',
                  icon: Icons.data_object,
                  iconSize: 16,
                  padding: 4,
                  isActive: _pretty,
                  onPressed: _togglePretty,
                ),
              if (!isImage) ...[
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
                      ? 'Find in body (${_shortcutLabel('F')})'
                      : 'Close find (Esc)',
                  icon: Icons.search,
                  iconSize: 16,
                  padding: 4,
                  isActive: _find.value != null,
                  onPressed: _toggleFind,
                ),
              ],
              AppIconButton(
                tooltip: 'Copy body',
                icon: Icons.copy,
                iconSize: 16,
                padding: 4,
                onPressed: isImage ? null : _copyAll,
              ),
            ],
          ),
        ),
        Expanded(
          child: isImage
              ? _ImagePreview(bytes: widget.body.bytes)
              : _buildEditor(context, document),
        ),
      ],
    );
  }

  Widget _buildEditor(BuildContext context, _Document document) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tokens = context.eaglyTheme;
    final isDark = theme.brightness == Brightness.dark;
    final fontSize = MediaQuery.textScalerOf(context).scale(12);
    final grammar = document.language.grammar;
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
        selectionColor: cs.primary.withValues(alpha: 0.28),
        highlightColor: tokens.searchMatchColor,
        cursorLineColor: Colors.transparent,
        chunkIndicatorColor: tokens.tertiaryTextColor,
        codeTheme: grammar == null
            ? null
            : CodeHighlightTheme(
                languages: {
                  document.language.name: CodeHighlightThemeMode(mode: grammar),
                },
                theme: _highlightTheme(isDark, cs.onSurface),
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
      findBuilder: (context, controller, readOnly) =>
          _FindBar(controller: controller, editorFocus: _editorFocus),
      toolbarController: _BodyContextMenu(
        onFind: () => _find.findMode(),
        onCopyAll: _copyAll,
      ),
    );
  }
}

/// The highlight.js palette for the current brightness, on the pane's own
/// background rather than the theme's.
Map<String, TextStyle> _highlightTheme(bool dark, Color text) {
  final base = dark ? atomOneDarkTheme : atomOneLightTheme;
  return {...base, 'root': TextStyle(color: text)};
}

String _shortcutLabel(String key) =>
    defaultTargetPlatform == TargetPlatform.macOS ? '⌘$key' : 'Ctrl+$key';

class const _Badge(final String label) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSecondaryContainer,
        ),
      ),
    );
  }
}

class const _ImagePreview({required final Uint8List bytes})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      maxScale: 8,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Image.memory(
            bytes,
            filterQuality: FilterQuality.medium,
            errorBuilder: (context, _, _) =>
                const NetworkPlaceholder('This image could not be decoded.'),
          ),
        ),
      ),
    );
  }
}

/// The find bar re_editor shows above the body: the query, case and regex
/// toggles, the match count, previous / next and close. ↵ steps forward,
/// ⇧↵ back, Esc closes.
class const _FindBar({
  required final CodeFindController controller,
  required final FocusNode editorFocus,
}) extends StatelessWidget implements PreferredSizeWidget {
  @override
  Size get preferredSize =>
      Size(double.infinity, controller.value == null ? 0 : 40);

  @override
  Widget build(BuildContext context) {
    final value = controller.value;
    if (value == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tokens = context.eaglyTheme;
    final result = value.result;
    final query = controller.findInputController.text;
    final noMatches =
        query.isNotEmpty &&
        !value.searching &&
        (result == null || result.matches.isEmpty);
    final invalid = value.option.regex && value.option.regExp == null;

    void close() {
      controller.close();
      editorFocus.requestFocus();
    }

    return Container(
      height: preferredSize.height,
      padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        border: Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      child: Row(
        children: [
          Icon(Icons.search, size: 16, color: cs.onSurfaceVariant),
          const SizedBox(width: 6),
          Expanded(
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.escape): close,
                const SingleActivator(LogicalKeyboardKey.enter):
                    controller.nextMatch,
                const SingleActivator(LogicalKeyboardKey.enter, shift: true):
                    controller.previousMatch,
              },
              child: TextField(
                controller: controller.findInputController,
                focusNode: controller.findInputFocusNode,
                style: theme.textTheme.bodySmall,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Find in body',
                  border: InputBorder.none,
                  filled: noMatches || invalid,
                  fillColor: invalid
                      ? cs.errorContainer.withValues(alpha: 0.5)
                      : tokens.searchNoResultsFillColor,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 8,
                  ),
                ),
              ),
            ),
          ),
          _FindToggle(
            label: 'Aa',
            tooltip: 'Match case',
            value: value.option.caseSensitive,
            onPressed: controller.toggleCaseSensitive,
          ),
          _FindToggle(
            label: '.*',
            tooltip: 'Use regular expression',
            value: value.option.regex,
            onPressed: controller.toggleRegex,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              invalid
                  ? 'Invalid regex'
                  : query.isEmpty
                  ? ''
                  : noMatches
                  ? 'No results'
                  : result == null
                  ? '…'
                  : '${result.index + 1} / ${result.matches.length}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: invalid
                    ? cs.error
                    : noMatches
                    ? tokens.searchNoResultsTextColor
                    : cs.onSurfaceVariant,
              ),
            ),
          ),
          AppIconButton(
            tooltip: 'Previous match (⇧↵)',
            icon: Icons.keyboard_arrow_up,
            iconSize: 16,
            padding: 4,
            onPressed: (result?.matches.isNotEmpty ?? false)
                ? controller.previousMatch
                : null,
          ),
          AppIconButton(
            tooltip: 'Next match (↵)',
            icon: Icons.keyboard_arrow_down,
            iconSize: 16,
            padding: 4,
            onPressed: (result?.matches.isNotEmpty ?? false)
                ? controller.nextMatch
                : null,
          ),
          AppIconButton(
            tooltip: 'Close (Esc)',
            icon: Icons.close,
            iconSize: 16,
            padding: 4,
            onPressed: close,
          ),
        ],
      ),
    );
  }
}

class const _FindToggle({
  required final String label,
  required final String tooltip,
  required final bool value,
  required final VoidCallback onPressed,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: '$tooltip (${value ? 'on' : 'off'})',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            margin: const EdgeInsets.only(left: 2),
            width: context.scaled(26),
            height: context.scaled(24),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: value ? cs.primaryContainer : null,
              borderRadius: BorderRadius.circular(4),
              border: value ? Border.all(color: cs.primary) : null,
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: value ? cs.primary : cs.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The body's right-click menu.
class const _BodyContextMenu({
  required final VoidCallback onFind,
  required final VoidCallback onCopyAll,
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
    showMenu<void>(
      context: context,
      position: menuPositionAt(anchors.primaryAnchor),
      items: [
        PopupMenuItem(
          enabled: hasSelection,
          onTap: controller.copy,
          child: NetworkMenuRow(
            Icons.content_copy,
            'Copy',
            shortcut: _shortcutLabel('C'),
          ),
        ),
        PopupMenuItem(
          onTap: controller.selectAll,
          child: NetworkMenuRow(
            Icons.select_all,
            'Select all',
            shortcut: _shortcutLabel('A'),
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          onTap: onFind,
          child: NetworkMenuRow(
            Icons.search,
            'Find…',
            shortcut: _shortcutLabel('F'),
          ),
        ),
        PopupMenuItem(
          onTap: onCopyAll,
          child: const NetworkMenuRow(Icons.copy_all, 'Copy whole body'),
        ),
      ],
    );
  }
}
