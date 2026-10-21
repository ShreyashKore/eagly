import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../presentation/components/feature_view.dart';
import '../../../presentation/theme/app_theme.dart';
import '../data/network_transaction.dart';

/// The status column's text: the code, `…` while waiting, `ERR` on failure.
String statusLabel(NetworkTransaction transaction) =>
    switch (transaction.state) {
      NetworkTransactionState.pending => '…',
      NetworkTransactionState.failed => 'ERR',
      NetworkTransactionState.complete => '${transaction.response?.code ?? ''}',
    };

/// The status as a sentence for a tooltip: `404 Not Found`, `Failed: …`.
String statusDescription(NetworkTransaction transaction) =>
    switch (transaction.state) {
      NetworkTransactionState.pending => 'Waiting for the response',
      NetworkTransactionState.failed =>
        'Failed${transaction.error == null ? '' : ': ${transaction.error}'}',
      NetworkTransactionState.complete => [
        transaction.response?.code ?? '',
        transaction.response?.message ?? '',
      ].join(' ').trim(),
    };

/// Color carries meaning only: errors and failures in the error color,
/// redirects in the warning color, a pending request in metadata grey.
Color? statusColor(BuildContext context, NetworkTransaction transaction) {
  final tokens = context.eaglyTheme;
  final code = transaction.response?.code ?? 0;
  return switch (transaction.state) {
    NetworkTransactionState.pending => tokens.tertiaryTextColor,
    NetworkTransactionState.failed => tokens.errorColor,
    NetworkTransactionState.complete when code >= 400 => tokens.errorColor,
    NetworkTransactionState.complete when code >= 300 => tokens.warningColor,
    NetworkTransactionState.complete => null,
  };
}

/// Whether the exchange is shown as an error: a failure or a 4xx/5xx.
bool isErrorTransaction(NetworkTransaction transaction) =>
    transaction.state == NetworkTransactionState.failed ||
    (transaction.response?.code ?? 0) >= 400;

/// The list's name for an exchange: its path and query, or the raw URL when
/// it does not parse.
String displayPath(NetworkTransaction transaction) {
  final uri = transaction.request.uri;
  if (uri == null) return transaction.request.url;
  return '${uri.path.isEmpty ? '/' : uri.path}'
      '${uri.hasQuery ? '?${uri.query}' : ''}';
}

/// The last non-empty path segment, or the host: the detail header's title.
String shortName(NetworkTransaction transaction) {
  final uri = transaction.request.uri;
  if (uri == null) return transaction.request.url;
  return uri.pathSegments.lastWhere(
    (segment) => segment.isNotEmpty,
    orElse: () => uri.host,
  );
}

/// `application/json; charset=utf-8` → `json`; `image/svg+xml` → `svg+xml`.
String shortContentType(String? contentType) {
  if (contentType == null) return '';
  final type = contentType.split(';').first.trim();
  final slash = type.indexOf('/');
  return slash < 0 ? type : type.substring(slash + 1);
}

/// `850 ms`, `1.24 s`, `2 min 5 s`.
String formatElapsed(Duration elapsed) {
  final ms = elapsed.inMicroseconds / 1000;
  if (ms < 1000) return '${ms.round()} ms';
  if (ms < 60000) return '${(ms / 1000).toStringAsFixed(2)} s';
  return '${elapsed.inMinutes} min ${elapsed.inSeconds % 60} s';
}

/// `14:03:07.250`, local time.
String formatClockTime(DateTime time) {
  final local = time.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(local.hour)}:${two(local.minute)}:${two(local.second)}'
      '.${local.millisecond.toString().padLeft(3, '0')}';
}

/// Copies [text] and says so in a snackbar.
Future<void> copyWithToast(
  BuildContext context,
  String text,
  String message,
) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) FeatureView.showSnackBar(context, message);
}

/// An icon and a label, the row of every Network context-menu entry.
class const NetworkMenuRow(
  final IconData icon,
  final String label, {
  super.key,
  final String? shortcut,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final tokens = context.eaglyTheme;
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
                ?.copyWith(color: tokens.tertiaryTextColor),
          ),
        ],
      ],
    );
  }
}

/// A global pointer position as a [showMenu] anchor.
RelativeRect menuPositionAt(Offset globalPosition) => RelativeRect.fromLTRB(
  globalPosition.dx,
  globalPosition.dy,
  globalPosition.dx,
  globalPosition.dy,
);
