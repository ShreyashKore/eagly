import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../presentation/theme/app_theme.dart';
import '../../../utils/utils.dart';
import '../data/network_transaction.dart';
import '../data/network_transaction_store.dart';
import '../network_controller.dart';
import 'network_transaction_list.dart';

/// One exchange in full: the URL and status line, any failure or override,
/// then headers and bodies for each side. Bodies are fetched when this opens.
class const NetworkTransactionDetail({
  super.key,
  required final NetworkController controller,
  required final NetworkEntry entry,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.eaglyTheme;
    final transaction = entry.transaction;
    final request = transaction.request;
    final response = transaction.response;
    final override = transaction.override;
    final source = controller.sourceOf(entry.key);
    final elapsed = transaction.elapsed;

    final facts = [
      request.method,
      if (response != null)
        [response.code, response.message ?? ''].join(' ').trim()
      else
        statusLabel(transaction),
      ?request.protocol,
      if (elapsed != null) formatElapsed(elapsed),
      ?transaction.adapter,
      ?source?.label,
    ];

    return SelectionArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Text(
            request.url,
            style: tokens.monoStyle.copyWith(
              fontSize: theme.textTheme.bodyMedium?.fontSize,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            facts.join('  ·  '),
            style: theme.textTheme.bodySmall?.copyWith(
              color: tokens.secondaryTextColor,
            ),
          ),
          if (transaction.error case final error?)
            _Notice(
              icon: Icons.error_outline,
              color: tokens.errorColor,
              text: error,
            ),
          if (override != null)
            _Notice(
              icon: Icons.edit_note,
              color: tokens.warningColor,
              text: override.originalResponseCode == null
                  ? 'Rewritten by an Inspektor override.'
                  : 'Rewritten by an Inspektor override; the server '
                        'answered ${override.originalResponseCode}.',
            ),
          _Section(
            title: 'Request headers',
            child: _Headers(headers: request.headers),
          ),
          _Section(
            title: 'Request body',
            child: _Body(
              controller: controller,
              entryKey: entry.key,
              part: NetworkBodyPart.request,
              state: request.body,
              contentType: request.contentType,
            ),
          ),
          if (response != null) ...[
            _Section(
              title: 'Response headers',
              child: _Headers(headers: response.headers),
            ),
            _Section(
              title: 'Response body',
              child: _Body(
                controller: controller,
                entryKey: entry.key,
                part: NetworkBodyPart.response,
                state: response.body,
                contentType: response.contentType,
              ),
            ),
            if (response.tlsVersion != null || response.cipherSuite != null)
              _Section(
                title: 'Connection',
                child: _Headers(
                  headers: [
                    if (response.tlsVersion case final tls?)
                      NetworkHeader('TLS', tls),
                    if (response.cipherSuite case final cipher?)
                      NetworkHeader('Cipher suite', cipher),
                  ],
                ),
              ),
          ],
          if (transaction.timings case final timings?)
            _Section(
              title: 'Timing',
              child: _Timings(timings: timings),
            ),
        ],
      ),
    );
  }
}

class const _Notice({
  required final IconData icon,
  required final Color color,
  required final String text,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: context.scaled(16), color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class const _Section({required final String title, required final Widget child})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}

class const _Headers({required final List<NetworkHeader> headers})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.eaglyTheme;
    if (headers.isEmpty) return const _Placeholder('None');
    final style = tokens.monoStyle.copyWith(
      fontSize: theme.textTheme.bodySmall?.fontSize,
      height: 1.5,
    );
    return Text.rich(
      TextSpan(
        children: [
          for (final (index, header) in headers.indexed) ...[
            if (index > 0) const TextSpan(text: '\n'),
            TextSpan(
              text: '${header.name}: ',
              style: style.copyWith(color: tokens.secondaryTextColor),
            ),
            TextSpan(text: header.value, style: style),
          ],
        ],
      ),
    );
  }
}

class const _Timings({required final NetworkTimings timings})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final phases = [
      ('DNS lookup', timings.dns),
      ('Connecting', timings.connect),
      ('TLS handshake', timings.tls),
      ('Sending', timings.send),
      ('Waiting for the server', timings.wait),
      ('Receiving', timings.receive),
    ];
    return _Headers(
      headers: [
        for (final (label, duration) in phases)
          if (duration != null) NetworkHeader(label, formatElapsed(duration)),
      ],
    );
  }
}

class const _Placeholder(final String text) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.bodySmall
          ?.copyWith(color: context.eaglyTheme.tertiaryTextColor),
    );
  }
}

/// A body, fetched from its source the first time it is shown. JSON is
/// pretty-printed; a body that is not UTF-8 is described rather than shown.
class const _Body({
  required final NetworkController controller,
  required final NetworkTransactionKey entryKey,
  required final NetworkBodyPart part,
  required final NetworkBodyState state,
  final String? contentType,
}) extends StatefulWidget {
  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  NetworkBody? _formattedFor;
  String? _formatted;

  @override
  void initState() {
    super.initState();
    _ensureLoading();
  }

  @override
  void didUpdateWidget(_Body oldWidget) {
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

  String? _display(NetworkBody body) {
    if (identical(body, _formattedFor)) return _formatted;
    _formattedFor = body;
    final text = body.text;
    _formatted = text == null ? null : _prettyJson(text) ?? text;
    return _formatted;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.eaglyTheme;
    switch (widget.state) {
      case NetworkBodyState.empty:
        return const _Placeholder('Empty');
      case NetworkBodyState.notCaptured:
        return const _Placeholder('Not captured');
      case NetworkBodyState.available || NetworkBodyState.truncated:
        break;
    }

    final load = widget.controller.bodyLoad(widget.entryKey, widget.part);
    switch (load) {
      case null || NetworkBodyLoading():
        return const Align(
          alignment: Alignment.centerLeft,
          child: SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      case NetworkBodyFailed(:final message):
        return Row(
          children: [
            Expanded(child: _Placeholder('Could not load the body: $message')),
            TextButton(
              onPressed: () {
                widget.controller.retryBody(widget.entryKey, widget.part);
                _ensureLoading();
              },
              child: const Text('Retry'),
            ),
          ],
        );
      case NetworkBodyLoaded(:final body):
        final text = _display(body);
        final truncated =
            body.truncated || widget.state == NetworkBodyState.truncated;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (text == null)
              _Placeholder(
                'Binary body, ${formatBytes(body.bytes.length)}'
                '${widget.contentType == null ? '' : ' of ${widget.contentType}'}',
              )
            else
              Text(
                text,
                style: tokens.monoStyle.copyWith(
                  fontSize: theme.textTheme.bodySmall?.fontSize,
                  height: 1.4,
                ),
              ),
            if (truncated)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: _Placeholder(
                  'Cut at ${formatBytes(body.bytes.length)}'
                  '${body.originalSize == null ? '' : ' of ${formatBytes(body.originalSize!)}'}'
                  ' by the app\'s capture limit.',
                ),
              ),
          ],
        );
    }
  }
}

/// [text] re-indented when it is a JSON object or array, else null.
String? _prettyJson(String text) {
  final trimmed = text.trimLeft();
  if (!trimmed.startsWith('{') && !trimmed.startsWith('[')) return null;
  try {
    return const JsonEncoder.withIndent('  ').convert(jsonDecode(trimmed));
  } on FormatException {
    return null;
  }
}
