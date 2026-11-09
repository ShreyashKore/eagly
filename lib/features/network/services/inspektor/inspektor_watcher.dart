import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../app_log/app_logger.dart';
import 'inspektor_endpoint.dart';
import 'inspektor_messages.dart';
import 'inspektor_source.dart';
import 'inspektor_token.dart';

/// The key a connection's transactions are filed under: one per app store,
/// not per connection, so a restarted app continues its own list.
String inspektorStoreKey(InspektorHello hello) =>
    'inspektor:${hello.appId}:${hello.storeId}';

/// Keeps the Network pane connected to every Inspektor server on one device.
///
/// While [start]ed it polls [findEndpoints] every [pollInterval]:
///
/// - A new endpoint gets a tunnel and an [InspektorSource]. Once the app's
///   `hello` names its store, the source resumes after [resumeAfter] for that
///   store's key and is handed to [attach] under it. A restarted app (new pid,
///   so a new socket and endpoint) therefore continues the list it had,
///   instead of starting a second one or sending its history again.
/// - An endpoint that disappears has its tunnel closed. Its source has ended
///   by then: the app's socket closed when the process did.
/// - A connection that ends is let go of, tunnel and all, so the next poll
///   connects to the endpoint again if it is still there. On iOS a restarted
///   app usually takes the same port, so this is the only way to see it.
/// - A failed connection is retried after [retryDelay], not on every poll.
/// - Where an app asks for its token (iOS), [listenForToken] starts reading
///   the device log before the connection opens, because the app writes the
///   token line as it accepts the connection. The listener is stopped once
///   the source is ready or has failed.
///
/// [stop] only stops polling: connections stay up, so traffic keeps arriving
/// while the pane is hidden, and the next [start] picks up what changed.
class InspektorWatcher({
  required final Future<List<InspektorEndpoint>> Function() findEndpoints,
  required final Future<InspektorTunnel> Function(InspektorEndpoint) openTunnel,
  required final String? Function(String key) resumeAfter,
  required final void Function(InspektorSource source, String key) attach,

  /// Starts following the device log for [InspektorEndpoint]'s token, or
  /// returns null where no token is needed (Android checks the peer itself).
  final InspektorTokenListener? Function(InspektorEndpoint endpoint)?
  listenForToken,
}) {
  /// How often the device is asked for its Inspektor endpoints.
  @visibleForTesting
  static Duration pollInterval = const Duration(seconds: 2);

  /// How long an endpoint that failed to connect is left alone.
  @visibleForTesting
  static Duration retryDelay = const Duration(seconds: 10);

  /// How long a new connection may take to say hello, present its token and
  /// subscribe. The token can take a moment to come through the device log.
  @visibleForTesting
  static Duration helloTimeout = const Duration(seconds: 10);

  /// How long to wait for the device log to start flowing before connecting.
  /// The connection goes ahead after it regardless.
  @visibleForTesting
  static Duration logStartTimeout = const Duration(seconds: 3);

  final AppLogger _logger = AppLogger(source: 'InspektorWatcher');
  final Map<InspektorEndpoint, _Connection> _connections = {};
  final Map<InspektorEndpoint, DateTime> _failedAt = {};
  int _generation = 0;
  bool _running = false;
  bool _disposed = false;

  bool get isRunning => _running;

  /// Starts polling. Does nothing when already running.
  void start() {
    if (_running || _disposed) return;
    _running = true;
    unawaited(_loop(++_generation));
  }

  /// Stops polling; open connections stay up.
  void stop() {
    if (!_running) return;
    _running = false;
    _generation++;
  }

  /// Stops polling and forgets every connection, closing its tunnel — for a
  /// device that went away, whose tunnels are gone anyway.
  void reset() {
    stop();
    final connections = _connections.values.toList();
    _connections.clear();
    _failedAt.clear();
    for (final connection in connections) {
      unawaited(connection.close());
    }
  }

  void dispose() {
    reset();
    _disposed = true;
  }

  Future<void> _loop(int generation) async {
    while (generation == _generation) {
      try {
        await _poll(generation);
      } catch (error) {
        _logger.warning('Looking for Inspektor apps failed: $error');
      }
      if (generation != _generation) return;
      await Future<void>.delayed(pollInterval);
    }
  }

  Future<void> _poll(int generation) async {
    final endpoints = (await findEndpoints()).toSet();
    if (generation != _generation) return;

    for (final gone in [
      for (final endpoint in _connections.keys)
        if (!endpoints.contains(endpoint)) endpoint,
    ]) {
      unawaited(_connections.remove(gone)?.close());
    }
    _failedAt.removeWhere((endpoint, _) => !endpoints.contains(endpoint));

    final now = DateTime.now();
    for (final endpoint in endpoints) {
      if (_connections.containsKey(endpoint)) continue;
      final failedAt = _failedAt[endpoint];
      if (failedAt != null && now.difference(failedAt) < retryDelay) continue;
      // Claimed before the connect starts, so the next poll leaves it alone.
      final claim = _Connection();
      _connections[endpoint] = claim;
      unawaited(_connect(endpoint, claim));
    }
  }

  /// Connects [endpoint] for [claim]. A claim that is no longer the
  /// endpoint's — it vanished, or the device went away and came back while
  /// this ran — is abandoned rather than attached twice.
  Future<void> _connect(InspektorEndpoint endpoint, _Connection claim) async {
    bool current() => !_disposed && identical(_connections[endpoint], claim);
    InspektorSource? source;
    final tokens = listenForToken?.call(endpoint);
    try {
      if (tokens != null) {
        await tokens.started.timeout(logStartTimeout, onTimeout: () {});
      }
      final tunnel = claim.tunnel = await openTunnel(endpoint);
      if (!current()) {
        await claim.close();
        return;
      }
      source = await InspektorSource.connect(
        tunnel.host,
        tunnel.port,
        resumeAfter: (hello) => resumeAfter(inspektorStoreKey(hello)),
        token: tokens == null ? null : (hello) => tokens.tokenFor(hello.pid),
      );
      final hello = await source.ready.timeout(helloTimeout);
      if (!current()) {
        await source.dispose();
        await claim.close();
        return;
      }
      _failedAt.remove(endpoint);
      attach(source, inspektorStoreKey(hello));
      unawaited(
        source.closed.then((_) {
          if (!current()) return;
          _connections.remove(endpoint);
          unawaited(claim.close());
        }),
      );
    } catch (error) {
      _logger.warning('Could not connect to ${endpoint.name}: $error');
      await source?.dispose();
      await claim.close();
      if (current()) {
        _connections.remove(endpoint);
        _failedAt[endpoint] = DateTime.now();
      }
    } finally {
      // The token is only needed to get in; the log relay isn't kept open.
      await tokens?.close();
    }
  }
}

/// One endpoint's connection: claimed when the connect starts, holding its
/// tunnel once there is one.
class _Connection() {
  InspektorTunnel? tunnel;

  Future<void> close() async {
    final open = tunnel;
    tunnel = null;
    await open?.close();
  }
}
