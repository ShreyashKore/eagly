import 'package:flutter/material.dart';

import '../../../presentation/components/feature_view.dart';
import '../../../utils/utils.dart';
import '../data/network_copy.dart';
import '../data/network_filter.dart';
import '../data/network_transaction.dart';
import '../data/network_transaction_store.dart';
import '../network_controller.dart';
import 'network_presentation.dart';

enum _EntryAction {
  copyUrl,
  copyCurl,
  copyRequestHeaders,
  copyResponseHeaders,
  copyResponseBody,
  onlyHost,
  hideHost,
  onlyPath,
  onlyMethod,
  onlyStatus,
  clearFilters,
  clearList,
}

/// Right-click menu for one exchange in the list: copy it in the shapes
/// people paste elsewhere, or narrow the list to (or away from) things like
/// it. The filter entries add a term to the query, so they show up in the
/// filter field and can be edited or removed there.
Future<void> showNetworkEntryMenu(
  BuildContext context,
  Offset position, {
  required NetworkController controller,
  required NetworkEntry entry,
}) async {
  final transaction = entry.transaction;
  final request = transaction.request;
  final response = transaction.response;
  final host = request.uri?.host ?? '';
  final path = request.uri?.path ?? '';
  final code = response?.code;

  final result = await showMenu<_EntryAction>(
    context: context,
    position: menuPositionAt(position),
    items: [
      const PopupMenuItem(
        value: _EntryAction.copyUrl,
        child: NetworkMenuRow(Icons.link, 'Copy URL'),
      ),
      const PopupMenuItem(
        value: _EntryAction.copyCurl,
        child: NetworkMenuRow(Icons.terminal, 'Copy as cURL'),
      ),
      PopupMenuItem(
        value: _EntryAction.copyRequestHeaders,
        enabled: request.headers.isNotEmpty,
        child: const NetworkMenuRow(Icons.north_east, 'Copy request headers'),
      ),
      PopupMenuItem(
        value: _EntryAction.copyResponseHeaders,
        enabled: response?.headers.isNotEmpty ?? false,
        child: const NetworkMenuRow(Icons.south_west, 'Copy response headers'),
      ),
      PopupMenuItem(
        value: _EntryAction.copyResponseBody,
        enabled: response?.body.isFetchable ?? false,
        child: const NetworkMenuRow(Icons.data_object, 'Copy response body'),
      ),
      const PopupMenuDivider(),
      if (host.isNotEmpty) ...[
        PopupMenuItem(
          value: _EntryAction.onlyHost,
          child: NetworkMenuRow(Icons.filter_alt_outlined, 'Show only $host'),
        ),
        PopupMenuItem(
          value: _EntryAction.hideHost,
          child: NetworkMenuRow(Icons.filter_alt_off_outlined, 'Hide $host'),
        ),
      ],
      if (path.isNotEmpty && path != '/')
        PopupMenuItem(
          value: _EntryAction.onlyPath,
          child: NetworkMenuRow(Icons.route_outlined, 'Show only $path'),
        ),
      PopupMenuItem(
        value: _EntryAction.onlyMethod,
        child: NetworkMenuRow(
          Icons.swap_vert,
          'Show only ${request.method} requests',
        ),
      ),
      if (code != null)
        PopupMenuItem(
          value: _EntryAction.onlyStatus,
          child: NetworkMenuRow(Icons.tag, 'Show only status $code'),
        ),
      if (controller.filter.isActive)
        const PopupMenuItem(
          value: _EntryAction.clearFilters,
          child: NetworkMenuRow(Icons.clear_all, 'Clear filters'),
        ),
      const PopupMenuDivider(),
      const PopupMenuItem(
        value: _EntryAction.clearList,
        child: NetworkMenuRow(Icons.block, 'Clear list'),
      ),
    ],
  );
  if (result == null || !context.mounted) return;

  void addTerm(String term) =>
      controller.setFilter(controller.filter.withTerm(term));

  switch (result) {
    case _EntryAction.copyUrl:
      await copyWithToast(context, request.url, 'Copied URL.');
    case _EntryAction.copyCurl:
      final body = await _textBody(controller, entry, NetworkBodyPart.request);
      if (!context.mounted) return;
      await copyWithToast(
        context,
        curlCommand(transaction, body: body),
        'Copied as cURL.',
      );
    case _EntryAction.copyRequestHeaders:
      await copyWithToast(
        context,
        headersText(request.headers),
        'Copied request headers.',
      );
    case _EntryAction.copyResponseHeaders:
      await copyWithToast(
        context,
        headersText(response!.headers),
        'Copied response headers.',
      );
    case _EntryAction.copyResponseBody:
      try {
        final body = await controller.loadBody(
          entry.key,
          NetworkBodyPart.response,
        );
        if (!context.mounted) return;
        final text = body.text;
        if (text == null) {
          FeatureView.showSnackBar(
            context,
            'The response body is binary; export a HAR file to keep it.',
          );
          return;
        }
        await copyWithToast(context, text, 'Copied response body.');
      } catch (error) {
        if (context.mounted) {
          FeatureView.showSnackBar(
            context,
            'Could not load the body: ${describeError(error)}',
          );
        }
      }
    case _EntryAction.onlyHost:
      addTerm('domain:$host');
    case _EntryAction.hideHost:
      addTerm('-domain:$host');
    case _EntryAction.onlyPath:
      addTerm('path:$path');
    case _EntryAction.onlyMethod:
      addTerm('method:${request.method}');
    case _EntryAction.onlyStatus:
      addTerm('status-code:$code');
    case _EntryAction.clearFilters:
      controller.setFilter(NetworkFilter.none);
    case _EntryAction.clearList:
      controller.clear();
  }
}

/// The [part] body as text, or null when there is none, it is binary, or it
/// cannot be fetched.
Future<String?> _textBody(
  NetworkController controller,
  NetworkEntry entry,
  NetworkBodyPart part,
) async {
  final state = part == NetworkBodyPart.request
      ? entry.transaction.request.body
      : entry.transaction.response?.body;
  if (state == null || !state.isFetchable) return null;
  try {
    return (await controller.loadBody(entry.key, part)).text;
  } catch (_) {
    return null;
  }
}
