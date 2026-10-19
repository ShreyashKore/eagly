import 'dart:async';
import 'dart:convert';

import 'package:eagly/features/network/data/network_transaction.dart';
import 'package:eagly/features/network/services/network_source.dart';

/// A [NetworkSource] a test drives by hand.
class FakeNetworkSource({@override final String label = 'Example app'})
    implements NetworkSource {
  final StreamController<NetworkSourceEvent> _events =
      StreamController<NetworkSourceEvent>();

  /// How [body] answers; by default with `body of <id>` as text.
  Future<NetworkBody> Function(String id, NetworkBodyPart part)? onBody;

  int bodyCalls = 0;
  bool disposed = false;

  @override
  NetworkSourceKind get kind => NetworkSourceKind.inspektor;

  @override
  Stream<NetworkSourceEvent> get events => _events.stream;

  void upsert(NetworkTransaction transaction) =>
      _events.add(NetworkTransactionUpserted(transaction));

  void status(NetworkSourceStatus status, {String? message}) =>
      _events.add(NetworkSourceStatusChanged(status, message: message));

  void cleared() => _events.add(const NetworkTransactionsCleared());

  @override
  Future<NetworkBody> body(String transactionId, NetworkBodyPart part) {
    bodyCalls++;
    return onBody?.call(transactionId, part) ??
        Future.value(NetworkBody(bytes: utf8.encode('body of $transactionId')));
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    await _events.close();
  }
}

/// A finished GET of `https://api.example.com/<id>` with fetchable bodies.
NetworkTransaction networkTransaction(
  String id, {
  NetworkTransactionState state = NetworkTransactionState.complete,
  int code = 200,
}) => NetworkTransaction(
  id: id,
  state: state,
  request: NetworkRequestInfo(
    method: 'GET',
    url: 'https://api.example.com/items/$id',
    body: NetworkBodyState.available,
  ),
  response: state == NetworkTransactionState.complete
      ? NetworkResponseInfo(
          code: code,
          contentType: 'application/json',
          size: 12,
          body: NetworkBodyState.available,
        )
      : null,
  duration: state == NetworkTransactionState.complete
      ? const Duration(milliseconds: 85)
      : null,
);
