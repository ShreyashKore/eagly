import 'package:flutter/material.dart';

import '../../../presentation/theme/app_theme.dart';
import '../../../utils/utils.dart';
import '../data/network_transaction.dart';
import '../data/network_transaction_store.dart';
import '../network_controller.dart';

/// The Network pane's list of exchanges, oldest first: status, method, path
/// and host, then time taken and response size. Tapping a row opens it.
class const NetworkTransactionList({
  super.key,
  required final NetworkController controller,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final entries = controller.entries;
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemExtent: context.scaled(44),
      itemCount: entries.length,
      itemBuilder: (context, index) => _Row(
        entry: entries[index],
        onTap: () => controller.select(entries[index].key),
      ),
    );
  }
}

class const _Row({
  required final NetworkEntry entry,
  required final VoidCallback onTap,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.eaglyTheme;
    final transaction = entry.transaction;
    final uri = transaction.request.uri;
    final path = uri == null
        ? transaction.request.url
        : '${uri.path.isEmpty ? '/' : uri.path}${uri.hasQuery ? '?${uri.query}' : ''}';
    final size = transaction.response?.size;
    final elapsed = transaction.elapsed;
    final metaStyle = theme.textTheme.bodySmall?.copyWith(
      color: tokens.tertiaryTextColor,
    );

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            SizedBox(
              width: context.scaled(44),
              child: Text(
                statusLabel(transaction),
                style: tokens.monoStyle.copyWith(
                  fontSize: theme.textTheme.bodySmall?.fontSize,
                  fontWeight: FontWeight.w600,
                  color: statusColor(context, transaction),
                ),
              ),
            ),
            SizedBox(
              width: context.scaled(56),
              child: Text(
                transaction.request.method,
                overflow: TextOverflow.ellipsis,
                style: tokens.monoStyle.copyWith(
                  fontSize: theme.textTheme.bodySmall?.fontSize,
                ),
              ),
            ),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                  if (uri != null && uri.host.isNotEmpty)
                    Text(
                      uri.host,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: tokens.secondaryTextColor,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (elapsed != null)
                  Text(formatElapsed(elapsed), style: metaStyle),
                if (size != null) Text(formatBytes(size), style: metaStyle),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The status column's text: the code, `…` while waiting, `ERR` on failure.
String statusLabel(NetworkTransaction transaction) =>
    switch (transaction.state) {
      NetworkTransactionState.pending => '…',
      NetworkTransactionState.failed => 'ERR',
      NetworkTransactionState.complete => '${transaction.response?.code ?? ''}',
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

/// `850 ms`, `1.24 s`, `2 min 5 s`.
String formatElapsed(Duration elapsed) {
  final ms = elapsed.inMicroseconds / 1000;
  if (ms < 1000) return '${ms.round()} ms';
  if (ms < 60000) return '${(ms / 1000).toStringAsFixed(2)} s';
  return '${elapsed.inMinutes} min ${elapsed.inSeconds % 60} s';
}
