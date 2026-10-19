import '../data/network_transaction.dart';

/// Where a source is in its life.
enum NetworkSourceStatus {
  /// Connecting, or waiting for the app's handshake.
  connecting,

  /// Delivering transactions.
  live,

  /// Done delivering: the app closed the connection, or a file was read in
  /// full. Its transactions stay readable.
  ended,

  /// Stopped by an error; [NetworkSourceStatusChanged.message] says which.
  failed,
}

/// What a [NetworkSource] tells the Network pane.
sealed class const NetworkSourceEvent();

/// A transaction was seen for the first time, or changed. Sources send the
/// whole transaction every time, never a diff.
final class const NetworkTransactionUpserted(
  final NetworkTransaction transaction,
) extends NetworkSourceEvent;

/// The source dropped everything it had sent so far.
final class const NetworkTransactionsCleared() extends NetworkSourceEvent;

/// The source moved to [status]. [message] explains a failure, or describes
/// the source once it is known (the app's name, the file's).
final class const NetworkSourceStatusChanged(
  final NetworkSourceStatus status, {
  final String? message,
}) extends NetworkSourceEvent;

/// One place HTTP exchanges come from: an app's Inspektor socket, a HAR file,
/// later a WebView or a Dart VM service. See docs/NETWORK_INSPECTOR.md §3.4.
///
/// [events] is single-subscription and buffers until it is listened to, so
/// nothing a source sends before the Network pane subscribes is lost.
abstract interface class NetworkSource {
  NetworkSourceKind get kind;

  /// A short name for the source: the app, or the file.
  String get label;

  Stream<NetworkSourceEvent> get events;

  /// Fetches one body of the transaction with [transactionId]. Throws when
  /// the source cannot provide it.
  Future<NetworkBody> body(String transactionId, NetworkBodyPart part);

  /// Stops the source and releases what it holds (a socket, a file's
  /// contents). Its [events] stream closes.
  Future<void> dispose();
}
