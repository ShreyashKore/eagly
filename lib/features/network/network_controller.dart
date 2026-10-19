import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../services/eagly_info_service.dart';
import '../../session/feature_controller.dart';
import '../../session/workspace_layout.dart';
import '../../utils/utils.dart';
import 'data/har.dart';
import 'data/network_filter.dart';
import 'data/network_transaction.dart';
import 'data/network_transaction_store.dart';
import 'services/har_source.dart';
import 'services/inspektor/inspektor_watcher.dart';
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

/// The tabs of an open exchange. The pane remembers the last one picked, so
/// stepping through the list keeps showing the same part of each exchange.
enum NetworkDetailTab { headers, payload, response, timing }

/// The list columns that can be sorted on.
enum NetworkSortColumn { status, method, name, type, size, time }

/// How the list is ordered when it is not in capture order.
class const NetworkSort(
  final NetworkSortColumn column, {
  final bool descending = false,
}) {
  @override
  bool operator ==(Object other) =>
      other is NetworkSort &&
      other.column == column &&
      other.descending == descending;

  @override
  int get hashCode => Object.hash(column, descending);
}

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
///
/// While the Network pane is open and the device connected, an
/// [InspektorWatcher] finds apps that serve their traffic and attaches each
/// under its store's key (see [attach]).
class NetworkController(super.session) extends FeatureController {
  this {
    // The pane may already be open when its controller is first built (a
    // restored layout), with no session change to come.
    scheduleMicrotask(_syncWatching);
  }

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

  /// Per source key, the highest transaction id seen — where a reconnecting
  /// app resumes. Kept apart from the store so [clear] does not bring cleared
  /// transactions back on the next reconnect.
  final Map<String, String> _cursors = {};
  NetworkTransactionKey? _selectedKey;

  NetworkFilter _filter = NetworkFilter.none;
  NetworkSort? _sort;
  bool _showOverview = true;

  /// The tab an opened exchange starts on: the last one picked. View state
  /// only, so changing it notifies no one.
  NetworkDetailTab detailTab = NetworkDetailTab.headers;
  _VisibleCache? _visibleCache;

  late final InspektorWatcher _watcher = InspektorWatcher(
    findEndpoints: service.findInspektorEndpoints,
    openTunnel: service.openInspektorTunnel,
    resumeAfter: lastIdFor,
    attach: (source, key) => attach(source, key: key),
  );
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

  // ── Filtering and sorting ─────────────────────────────────────────────

  NetworkFilter get filter => _filter;

  void setFilter(NetworkFilter filter) {
    if (filter == _filter) return;
    _filter = filter;
    _notify();
  }

  /// Null while the list is in capture order.
  NetworkSort? get sort => _sort;

  void setSort(NetworkSort? sort) {
    if (sort == _sort) return;
    _sort = sort;
    _notify();
  }

  /// Whether the timeline overview is shown above the list.
  bool get showOverview => _showOverview;

  void toggleOverview() {
    _showOverview = !_showOverview;
    _notify();
  }

  /// The entries the list shows: [entries] through [filter], in [sort]
  /// order. Cached until either, or the store, changes.
  List<NetworkEntry> get visibleEntries => _visible().list;

  /// The entries the overview draws: everything [filter] lets through except
  /// its time window, which is drawn over them instead.
  List<NetworkEntry> get timelineEntries => _visible().timeline;

  _VisibleCache _visible() {
    final all = _store.entries;
    final cached = _visibleCache;
    if (cached != null &&
        identical(cached.source, all) &&
        cached.filter == _filter &&
        cached.sort == _sort &&
        cached.sourcesVersion == _sourcesVersion) {
      return cached;
    }
    final unwindowed = _filter.timeWindow == null
        ? _filter
        : _filter.copyWith(timeWindow: () => null);
    final timeline = !unwindowed.isActive
        ? all
        : [
            for (final entry in all)
              if (unwindowed.matches(
                entry.transaction,
                sourceLabel: _sources[entry.key.source]?.source.label,
              ))
                entry,
          ];
    final window = _filter.timeWindow == null
        ? null
        : NetworkFilter(timeWindow: _filter.timeWindow);
    var list = window == null
        ? timeline
        : [
            for (final entry in timeline)
              if (window.matches(entry.transaction)) entry,
          ];
    if (_sort case final sort?) {
      list = [...list];
      mergeSort(list, compare: _comparator(sort));
    }
    return _visibleCache = _VisibleCache(
      all,
      _filter,
      _sort,
      _sourcesVersion,
      list: list,
      timeline: timeline,
    );
  }

  int _sourcesVersion = 0;

  static Comparator<NetworkEntry> _comparator(NetworkSort sort) {
    int compare(NetworkEntry a, NetworkEntry b) {
      final x = a.transaction;
      final y = b.transaction;
      return switch (sort.column) {
        NetworkSortColumn.status => _statusRank(x).compareTo(_statusRank(y)),
        NetworkSortColumn.method => x.request.method.compareTo(
          y.request.method,
        ),
        NetworkSortColumn.name => _nameOf(x).compareTo(_nameOf(y)),
        NetworkSortColumn.type => (x.response?.contentType ?? '').compareTo(
          y.response?.contentType ?? '',
        ),
        NetworkSortColumn.size => (x.response?.size ?? -1).compareTo(
          y.response?.size ?? -1,
        ),
        NetworkSortColumn.time => (x.elapsed?.inMicroseconds ?? -1).compareTo(
          y.elapsed?.inMicroseconds ?? -1,
        ),
      };
    }

    return sort.descending ? (a, b) => compare(b, a) : compare;
  }

  static int _statusRank(NetworkTransaction t) => switch (t.state) {
    NetworkTransactionState.pending => -2,
    NetworkTransactionState.failed => -1,
    NetworkTransactionState.complete => t.response?.code ?? 0,
  };

  static String _nameOf(NetworkTransaction t) {
    final uri = t.request.uri;
    if (uri == null) return t.request.url;
    return '${uri.path}${uri.hasQuery ? '?${uri.query}' : ''}';
  }

  // ── Sources ───────────────────────────────────────────────────────────

  /// Starts showing what [source] delivers. Returns the id it is filed under:
  /// [key], or a fresh one. The controller owns [source] from here and
  /// disposes it.
  ///
  /// A [key] already in use replaces that source but keeps its transactions —
  /// a restarted app's new connection continues the old one's list, and its
  /// bodies are fetched through the new connection.
  String attach(NetworkSource source, {String? key}) {
    final id = key ?? 's${_nextSourceId++}';
    final previous = _sources[id];
    if (previous != null && !identical(previous.source, source)) {
      unawaited(previous.subscription?.cancel());
      unawaited(previous.source.dispose());
      _bodyFailures.removeWhere((request, _) => request.$1.source == id);
    }
    final attached = _AttachedSource(id, source);
    _sources[id] = attached;
    _sourcesVersion++;
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
    _sourcesVersion++;
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

  /// The highest transaction id seen from the source filed under [key], for
  /// resuming after it. Null when nothing has been seen.
  String? lastIdFor(String key) => _cursors[key];

  void _advanceCursor(String key, String id) {
    final current = _cursors[key];
    final number = int.tryParse(id);
    final currentNumber = current == null ? null : int.tryParse(current);
    if (current == null ||
        (number != null && currentNumber != null && number > currentNumber)) {
      _cursors[key] = id;
    }
  }

  void _handleEvent(_AttachedSource attached, NetworkSourceEvent event) {
    if (_disposed || _sources[attached.id] != attached) return;
    switch (event) {
      case NetworkTransactionUpserted(:final transaction):
        _advanceCursor(attached.id, transaction.id);
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

  /// Moves the selection [delta] rows through [visibleEntries], clamped at
  /// either end. With nothing selected, a step down picks the first row and
  /// a step up the last.
  void selectAdjacent(int delta) {
    final visible = visibleEntries;
    if (visible.isEmpty) return;
    final current = _selectedKey == null
        ? -1
        : visible.indexWhere((entry) => entry.key == _selectedKey);
    final next = current < 0
        ? (delta > 0 ? 0 : visible.length - 1)
        : (current + delta).clamp(0, visible.length - 1);
    select(visible[next].key);
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
    // The window points at a stretch of time that is no longer listed.
    if (_filter.timeWindow != null) {
      _filter = _filter.copyWith(timeWindow: () => null);
    }
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

  // ── Watching for apps ─────────────────────────────────────────────────

  /// Whether the device is being polled for apps to connect to.
  bool get isWatching => _watcher.isRunning;

  @override
  void onSessionChanged() => _syncWatching();

  @override
  void onDeviceDisconnected() {
    // Tunnels die with the device's transport; start over when it is back.
    _watcher.reset();
  }

  /// Polls for apps while the pane is open and the device connected; open
  /// connections outlive a closed pane.
  void _syncWatching() {
    if (_disposed) return;
    final watch =
        isConnected &&
        !session.isImportedWorkspace &&
        session.isPaneOpen(WorkspacePane.network);
    if (watch) {
      _watcher.start();
    } else {
      _watcher.stop();
    }
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
    _watcher.dispose();
    _notifyTimer?.cancel();
    for (final attached in _sources.values) {
      unawaited(attached.subscription?.cancel());
      unawaited(attached.source.dispose());
    }
    _sources.clear();
    super.dispose();
  }
}

class const _VisibleCache(
  final List<NetworkEntry> source,
  final NetworkFilter filter,
  final NetworkSort? sort,
  final int sourcesVersion, {
  required final List<NetworkEntry> list,
  required final List<NetworkEntry> timeline,
});

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
