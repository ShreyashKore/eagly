import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:re_highlight/languages/css.dart';
import 'package:re_highlight/languages/graphql.dart';
import 'package:re_highlight/languages/javascript.dart';
import 'package:re_highlight/languages/json.dart';
import 'package:re_highlight/languages/xml.dart';
import 'package:re_highlight/languages/yaml.dart';
import 'package:re_highlight/re_highlight.dart';

import '../../../presentation/components/app_icon_button.dart';
import '../../../presentation/components/code_view.dart';
import '../../../presentation/theme/app_theme.dart';
import '../../../utils/utils.dart';
import '../data/network_transaction.dart';
import '../data/network_transaction_store.dart';
import '../network_controller.dart';

/// One request or response body, fetched from its source the first time it
/// is shown, in a [CodeView] highlighted for the content type (or sniffed). JSON and form bodies can be shown pretty-printed or raw;
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
  NetworkBody? _preparedFor;
  _Document? _document;
  bool _pretty = true;

  @override
  void initState() {
    super.initState();
    _prepareDocument();
  }

  @override
  void didUpdateWidget(_LoadedBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.body, _preparedFor)) _prepareDocument();
  }

  Future<void> _prepareDocument() async {
    final body = widget.body;
    _preparedFor = body;
    final input = (body.bytes, widget.contentType);
    final document = body.bytes.length > _backgroundThreshold
        ? await Isolate.run(() => _prepare(input))
        : _prepare(input);
    if (!mounted || !identical(body, _preparedFor)) return;
    setState(() => _document = document);
  }

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
    final summary = Row(
      children: [
        _Badge(document.language.label),
        const SizedBox(width: 6),
        Flexible(child: _sizeLine(context)),
      ],
    );

    if (document.language == BodyLanguage.image) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: context.scaled(32),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
            ),
            child: summary,
          ),
          Expanded(child: _ImagePreview(bytes: widget.body.bytes)),
        ],
      );
    }

    final pretty = _pretty && document.pretty != null;
    return CodeView(
      text: pretty ? document.pretty! : document.raw,
      language: document.language.grammar,
      // A long single-line body wraps into a wall; a pretty one reads
      // better unwrapped, like an editor.
      wordWrap: !pretty,
      noun: 'body',
      copyText: document.language == BodyLanguage.hex
          ? document.raw
          : (NetworkBody(bytes: widget.body.bytes).text ?? ''),
      leading: summary,
      actions: [
        if (document.pretty != null)
          AppIconButton(
            tooltip: _pretty ? 'Show as sent' : 'Pretty-print',
            icon: Icons.data_object,
            iconSize: 16,
            padding: 4,
            isActive: _pretty,
            onPressed: () => setState(() => _pretty = !_pretty),
          ),
      ],
    );
  }

  Widget _sizeLine(BuildContext context) {
    final tokens = context.eaglyTheme;
    final originalSize = widget.body.originalSize;
    return Text(
      [
        formatBytes(widget.body.bytes.length),
        if (widget.truncated)
          'cut by the app\'s capture limit'
              '${originalSize == null ? '' : ' (${formatBytes(originalSize)} in all)'}',
      ].join(' · '),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: widget.truncated
            ? tokens.warningColor
            : tokens.tertiaryTextColor,
      ),
    );
  }
}

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
