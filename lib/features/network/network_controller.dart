import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../services/eagly_info_service.dart';
import '../../session/feature_controller.dart';
import '../../utils/utils.dart';
import 'data/har.dart';
import 'data/network_transaction.dart';
import 'data/network_transaction_store.dart';
import 'services/har_source.dart';
import 'services/network_source.dart';

/// One source attached to the Network pane, as the pane shows it.
class const NetworkSourceInfo({
  required final String id,
  required final NetworkSourceKind kind,
  required final String label,
  required final NetworkSourceStatus status,
  final String? message,
});

/// Where a body the pane asked for has got to.
sealed class const NetworkBodyLoad();

final class const NetworkBodyLoading() extends NetworkBodyLoad;

final class const NetworkBodyLoaded(final NetworkBody body)
    extends NetworkBodyLoad;

final class const NetworkBodyFailed(final String message)
    extends NetworkBodyLoad;

/// Per-device Network feature: the HTTP exchanges captured from this device's
/// apps, whichever [NetworkSource] they came from. See docs/NETWORK_INSPECTOR.md.
///
/// Sources are attached with [attach]. Their transactions land in one
/// [NetworkTransactionStore], keyed by source, oldest first and capped.
/// Bodies are fetched only when the pane shows them ([loadBody]) and kept in a
/// [NetworkBodyCache] under a byte budget.
///
/// Sources can deliver thousands of transactions at once (a HAR file, the
/// backfill after connecting to an app), so their events are applied straight
/// away but listeners hear about them at most once per [notifyInterval].
class NetworkController(super.session) extends FeatureController {
  /// The most often a burst of source events notifies listeners.
  @visibleForTesting
  static Duration notifyInterval = const Duration(milliseconds: 100);

  /// How many transactions the pane keeps before dropping the oldest.
  @visibleForTesting
  static int transactionCapacity = 5000;

  late final NetworkTransactionStore _store = NetworkTransactionStore(
    capacity: transactionCapacity,
  );
  final NetworkBodyCache _bodyCache = NetworkBodyCache();
  final Map<String, _AttachedSource> _sources = {};
  final Map<(NetworkTransactionKey, NetworkBodyPart), Future<NetworkBody>>
  _bodyRequests = {};
  final Map<(NetworkTransactionKey, NetworkBodyPart), String> _bodyFailures =
      {};
  int _nextSourceId = 1;
  NetworkTransactionKey? _selectedKey;
  Timer? _notifyTimer;
  bool _disposed = false;

  /// Every transaction, oldest first.
  List<NetworkEntry> get entries => _store.entries;
  bool get isEmpty => _store.isEmpty;

  List<NetworkSourceInfo> get sources => [
    for (final source in _sources.values) source.info,
  ];

  /// The transaction shown in detail, if it is still in the store.
  NetworkEntry? get selected {
    final key = _selectedKey;
    if (key == null) return null;
    final transaction = _store[key];
    return transaction == null ? null : NetworkEntry(key, transaction);
  }

  /// The source that delivered the transaction with [key].
  NetworkSourceInfo? sourceOf(NetworkTransactionKey key) =>
      _sources[key.source]?.info;

  // ── Sources ───────────────────────────────────────────────────────────

  /// Starts showing what [source] delivers. Returns the id it is filed under.
  /// The controller owns [source] from here and disposes it.
  String attach(NetworkSource source) {
    final id = 's${_nextSourceId++}';
    final attached = _AttachedSource(id, source);
    _sources[id] = attached;
    attached.subscription = source.events.listen(
      (event) => _handleEvent(attached, event),
      onError: (Object error) {
        attached
          ..status = NetworkSourceStatus.failed
          ..message = describeError(error);
        _scheduleNotify();
      },
    );
    _notify();
    return id;
  }

  /// Stops the source filed under [sourceId] and drops its transactions.
  Future<void> detach(String sourceId) async {
    final attached = _sources.remove(sourceId);
    if (attached == null) return;
    await attached.subscription?.cancel();
    _forget(_store.removeSource(sourceId));
    _notify();
    await attached.source.dispose();
  }

  /// Opens the HAR file at [path] as a new source. Throws a
  /// [FormatException] when it is not a HAR, or a [FileSystemException] when
  /// it cannot be read; both carry a message fit to show.
  Future<String> openHar(String path) async {
    final source = await HarSource.open(path);
    if (_disposed) {
      await source.dispose();
      return source.label;
    }
    attach(source);
    return source.label;
  }

  void _handleEvent(_AttachedSource attached, NetworkSourceEvent event) {
    if (_disposed || _sources[attached.id] != attached) return;
    switch (event) {
      case NetworkTransactionUpserted(:final transaction):
        final key = (source: attached.id, id: transaction.id);
        final wasPending =
            _store[key]?.state == NetworkTransactionState.pending;
        _forget(_store.upsert(attached.id, transaction));
        // A body fetched while the exchange was still running is incomplete;
        // once it finishes, the next look fetches it afresh.
        if (wasPending &&
            transaction.state != NetworkTransactionState.pending) {
          _forgetBodies({key});
        }
      case NetworkTransactionsCleared():
        _forget(_store.removeSource(attached.id));
      case NetworkSourceStatusChanged(:final status, :final message):
        attached
          ..status = status
          ..message = message ?? attached.message;
    }
    _scheduleNotify();
  }

  // ── Selection and bodies ──────────────────────────────────────────────

  void select(NetworkTransactionKey? key) {
    if (key == _selectedKey) return;
    _selectedKey = key;
    _notify();
  }

  /// Where the [part] body of the transaction with [key] has got to, or null
  /// if nothing has asked for it yet.
  NetworkBodyLoad? bodyLoad(NetworkTransactionKey key, NetworkBodyPart part) {
    final body = _bodyCache.get(key, part);
    if (body != null) return NetworkBodyLoaded(body);
    if (_bodyRequests.containsKey((key, part))) {
      return const NetworkBodyLoading();
    }
    final failure = _bodyFailures[(key, part)];
    return failure == null ? null : NetworkBodyFailed(failure);
  }

  /// Fetches the [part] body of the transaction with [key] from its source.
  /// Concurrent calls share one fetch; a fetched body is cached, and a failed
  /// one is remembered until [retryBody]. Listeners hear about both. Safe to
  /// call from a widget's build or `initState`: the fetch starting is
  /// announced asynchronously.
  Future<NetworkBody> loadBody(
    NetworkTransactionKey key,
    NetworkBodyPart part,
  ) {
    final cached = _bodyCache.get(key, part);
    if (cached != null) return Future.value(cached);
    final inFlight = _bodyRequests[(key, part)];
    if (inFlight != null) return inFlight;
    final source = _sources[key.source]?.source;
    if (source == null) {
      return Future.error(StateError('Its source is no longer attached.'));
    }

    final request = source.body(key.id, part);
    _bodyRequests[(key, part)] = request;
    _bodyFailures.remove((key, part));
    // Deferred: views call this while they build, and a synchronous notify
    // would mark them dirty mid-build.
    _scheduleNotify();
    unawaited(
      request.then(
        (body) {
          if (_bodyRequests.remove((key, part)) == null || _disposed) return;
          _bodyCache.put(key, part, body);
          _notify();
        },
        onError: (Object error) {
          if (_bodyRequests.remove((key, part)) == null || _disposed) return;
          _bodyFailures[(key, part)] = describeError(error);
          _notify();
        },
      ),
    );
    return request;
  }

  /// Forgets a failed fetch so the next [loadBody] tries again.
  void retryBody(NetworkTransactionKey key, NetworkBodyPart part) {
    if (_bodyFailures.remove((key, part)) != null) _notify();
  }

  // ── Clearing and export ───────────────────────────────────────────────

  /// Empties the pane. Sources stay attached, so a live app keeps adding to
  /// it; nothing is deleted on the device.
  void clear() {
    _store.clear();
    _bodyCache.clear();
    _bodyRequests.clear();
    _bodyFailures.clear();
    _selectedKey = null;
    _notify();
  }

  /// The pane's transactions as a HAR 1.2 document, with every body the
  /// sources can still provide. Bodies that fail to load are left out rather
  /// than failing the export.
  Future<String> exportHarText() async {
    final entries = <HarEntry>[];
    for (final entry in _store.entries) {
      final bodies = <NetworkBodyPart, NetworkBody>{};
      for (final (part, state) in [
        (NetworkBodyPart.request, entry.transaction.request.body),
        (NetworkBodyPart.response, entry.transaction.response?.body),
      ]) {
        if (state == null || !state.isFetchable) continue;
        try {
          bodies[part] = await loadBody(entry.key, part);
        } catch (_) {
          // Exported without this body.
        }
      }
      entries.add(HarEntry(entry.transaction, bodies: bodies));
    }
    return encodeHar(
      entries,
      creatorName: 'Eagly',
      creatorVersion: EaglyInfoService.appVersion,
    );
  }

  /// Writes [exportHarText] to [path].
  Future<void> exportHar(String path) async {
    await File(path).writeAsString(await exportHarText());
  }

  // ── Plumbing ──────────────────────────────────────────────────────────

  void _forget(List<NetworkTransactionKey> keys) {
    if (keys.isEmpty) return;
    final removed = keys.toSet();
    _forgetBodies(removed);
    if (removed.contains(_selectedKey)) _selectedKey = null;
  }

  void _forgetBodies(Set<NetworkTransactionKey> keys) {
    _bodyCache.removeAll(keys);
    _bodyRequests.removeWhere((request, _) => keys.contains(request.$1));
    _bodyFailures.removeWhere((request, _) => keys.contains(request.$1));
  }

  void _scheduleNotify() {
    if (_disposed || _notifyTimer != null) return;
    _notifyTimer = Timer(notifyInterval, () {
      _notifyTimer = null;
      if (!_disposed) notifyListeners();
    });
  }

  void _notify() {
    if (_disposed) return;
    _notifyTimer?.cancel();
    _notifyTimer = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _notifyTimer?.cancel();
    for (final attached in _sources.values) {
      unawaited(attached.subscription?.cancel());
      unawaited(attached.source.dispose());
    }
    _sources.clear();
    super.dispose();
  }
}

class _AttachedSource(final String id, final NetworkSource source) {
  StreamSubscription<NetworkSourceEvent>? subscription;
  NetworkSourceStatus status = NetworkSourceStatus.connecting;
  String? message;

  NetworkSourceInfo get info => NetworkSourceInfo(
    id: id,
    kind: source.kind,
    label: source.label,
    status: status,
    message: message,
  );
}
