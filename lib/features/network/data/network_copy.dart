import '../../../utils/utils.dart';
import 'network_transaction.dart';

/// [transaction]'s request as a POSIX-shell `curl` command, with [body] (the
/// fetched request body, when there is one) sent as raw data.
///
/// Laid out like Inspektor's `toCurlString` (`Curl.kt`) — long options, one
/// per line — so a command copied from either reads the same, but every
/// value is single-quoted with `'` escaped the way a shell needs. Headers
/// curl works out for itself (`Content-Length`, `Host`, HTTP/2 pseudo
/// headers) are left out.
String curlCommand(NetworkTransaction transaction, {String? body}) {
  final request = transaction.request;
  final lines = <String>[
    'curl',
    '--request ${_shellToken(request.method.toUpperCase())}',
    '--url ${shellQuote(request.url)}',
  ];
  var hasContentType = false;
  for (final header in request.headers) {
    final name = header.name.toLowerCase();
    if (name == 'content-length' || name == 'host' || name.startsWith(':')) {
      continue;
    }
    hasContentType |= name == 'content-type';
    lines.add('--header ${shellQuote('${header.name}: ${header.value}')}');
  }
  if (request.contentType case final type? when !hasContentType) {
    lines.add('--header ${shellQuote('Content-Type: $type')}');
  }
  if (body != null && body.isNotEmpty) {
    lines.add('--data-raw ${shellQuote(body)}');
  }
  return lines.join(' \\\n  ');
}

/// [headers] one per line, `Name: value`, the way they went over the wire.
String headersText(List<NetworkHeader> headers) =>
    headers.map((header) => '${header.name}: ${header.value}').join('\n');

/// [value] bare when it is plain letters (every real HTTP method), so the
/// command reads `--request GET`; anything else, quoted.
String _shellToken(String value) =>
    RegExp(r'^[A-Za-z]+$').hasMatch(value) ? value : shellQuote(value);
