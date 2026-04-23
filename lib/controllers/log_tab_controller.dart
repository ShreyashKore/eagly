import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';

import '../data/device.dart';
import '../data/log_column.dart';
import '../data/log_entry.dart';
import '../data/log_tab_settings.dart';
import '../services/adb_service.dart';
import '../services/log_file_service.dart';
import '../utils/log_utils.dart';

enum LogcatState { stopped, running, paused }

class WirelessPairResult {
  const WirelessPairResult({
    required this.paired,
    this.autoConnected = false,
    this.connectAddresses = const [],
    this.message,
    this.error,
  });

  final bool paired;
  final bool autoConnected;
  final List<String> connectAddresses;
  final String? message;
  final String? error;

  bool get isSuccess => error == null;
  bool get shouldShowConnectAction =>
      paired && !autoConnected && connectAddresses.isNotEmpty;

  factory WirelessPairResult.failure({required String error}) {
    return WirelessPairResult(paired: false, error: error);
  }

  factory WirelessPairResult.paired({
    String? message,
    List<String> connectAddresses = const [],
  }) {
    return WirelessPairResult(
      paired: true,
      message: message,
      connectAddresses: connectAddresses,
    );
  }

  factory WirelessPairResult.autoConnected({required String message}) {
    return WirelessPairResult(
      paired: true,
      autoConnected: true,
      message: message,
    );
  }
}

class LogTabController extends ChangeNotifier {
  LogTabController({
    required this.id,
    required String initialTitle,
    required LogTabSettings initialSettings,
    this.onExitGetStarted,
    this.isDeviceSelectedInAnotherTab,
    AdbService? adbService,
  }) : _title = initialTitle,
       _settings = initialSettings,
       _adbService = adbService ?? AdbService() {
    filterController.text = searchQuery;
    logLinesController.text = logLinesLimit.toString();
  }

  final String id;
  final VoidCallback? onExitGetStarted;
  final bool Function(String deviceId)? isDeviceSelectedInAnotherTab;
  final AdbService _adbService;

  final ScrollController scrollController = ScrollController();
  final TextEditingController filterController = TextEditingController();
  final FocusNode filterFocusNode = FocusNode();
  final TextEditingController searchController = TextEditingController();
  final FocusNode searchFocusNode = FocusNode();
  final TextEditingController logLinesController = TextEditingController();

  final List<LogEntry> _buffer = [];

  StreamSubscription<LogEntry>? _logSub;
  Timer? _flushTimer;
  Timer? _debounceTimer;
  Timer? _inlineSearchDebounce;

  var devices = <Device>[];
  var _loadingDevices = false;
  var _hasAttemptedDeviceLoad = false;
  var _discoveringWireless = false;
  var _pairingWireless = false;
  var _connectingWireless = false;
  var _hasAttemptedWirelessDiscovery = false;
  var _wirelessServices = <AdbMdnsService>[];
  String? _wirelessMessage;
  String? _wirelessError;
  Device? selectedDevice;
  var logs = <LogEntry>[];

  var logcatState = LogcatState.stopped;
  var searchQuery = '';
  var _appliedSearchQuery = '';

  var _searchBarVisible = false;
  var _inlineSearchQuery = '';
  var _appliedInlineSearchQuery = '';
  var _searchCaseSensitive = false;
  var _searchCurrentMatchIndex = 0;

  var _editingLogLinesLimit = false;
  var _logsMemoryBytes = 0;
  var _bufferMemoryBytes = 0;
  var _logViewerRevision = 0;

  var _disposed = false;
  var _showGetStarted = true;
  final String _title;
  String? _importedFileName;
  LogTabSettings _settings;

  List<LogEntry>? _cachedFilteredLogs;
  int _lastLogsLength = 0;
  String _lastFilterQuery = '';
  String _lastLogLevel = 'V';

  List<int>? _cachedSearchMatchIndices;
  String _smCacheQuery = '';
  bool _smCacheCaseSensitive = false;
  Set<String> _smCacheHiddenCols = {};
  int _smCacheFilteredLen = -1;

  String get title {
    if (selectedDevice != null) return selectedDevice!.displayName;
    if (_importedFileName != null) return _importedFileName!;
    if (_showGetStarted) return 'Get Started';
    return _title;
  }

  bool get showGetStarted => _showGetStarted;
  bool get searchBarVisible => _searchBarVisible;
  bool get searchCaseSensitive => _searchCaseSensitive;
  int get searchCurrentMatch => _searchCurrentMatchIndex;
  bool get editingLogLinesLimit => _editingLogLinesLimit;
  int get logViewerRevision => _logViewerRevision;
  bool get isRunning => logcatState != LogcatState.stopped;
  bool get isPaused => logcatState == LogcatState.paused;
  bool get hasLogs => logs.isNotEmpty;
  bool get hasSelectedDevice => selectedDevice != null;
  bool get hasVisibleWorkspace => hasSelectedDevice || hasLogs;
  int get totalLogsMemoryBytes => _logsMemoryBytes + _bufferMemoryBytes;
  String get appliedInlineSearchQuery => _appliedInlineSearchQuery;
  String get inlineSearchQuery => _inlineSearchQuery;
  bool get isLoadingDevices => _loadingDevices;
  bool get hasAttemptedDeviceLoad => _hasAttemptedDeviceLoad;
  bool get isDiscoveringWireless => _discoveringWireless;
  bool get isPairingWireless => _pairingWireless;
  bool get isConnectingWireless => _connectingWireless;
  bool get isWirelessBusy =>
      _discoveringWireless || _pairingWireless || _connectingWireless;
  bool get hasAttemptedWirelessDiscovery => _hasAttemptedWirelessDiscovery;
  List<AdbMdnsService> get wirelessServices =>
      List.unmodifiable(_wirelessServices);
  List<AdbMdnsService> get wirelessPairingServices => _wirelessServices
      .where((service) => service.type == AdbMdnsServiceType.pairing)
      .toList(growable: false);
  List<AdbMdnsService> get wirelessConnectServices => _wirelessServices
      .where((service) => service.type == AdbMdnsServiceType.connect)
      .toList(growable: false);
  String? get wirelessMessage => _wirelessMessage;
  String? get wirelessError => _wirelessError;
  String? get suggestedWirelessPairingAddress =>
      wirelessPairingServices.firstOrNull?.address;
  String? get suggestedWirelessConnectAddress =>
      wirelessConnectServices.firstOrNull?.address;

  bool get wrapText => _settings.wrapText;
  bool get autoScroll => _settings.autoScroll;
  String get selectedLogLevel => _settings.selectedLogLevel;
  int get logLinesLimit => _settings.logLinesLimit;
  Set<String> get hiddenColumns => _settings.hiddenColumns;
  Map<String, double> get columnWidths => _settings.columnWidths;

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  void _updateSettings(LogTabSettings settings) {
    _settings = settings;
    _notify();
  }

  void _exitGetStarted() {
    if (!_showGetStarted) return;
    _showGetStarted = false;
    onExitGetStarted?.call();
  }

  void _exitGetStartedIfWorkspaceReady() {
    if (selectedDevice != null || logs.isNotEmpty) {
      _exitGetStarted();
    }
  }

  Future<void> bootstrapInitialLoad() async {
    await loadDevices(autoStartSingleIfAvailable: true);
  }

  void focusFilterInputs() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed) return;
      filterFocusNode.requestFocus();
      filterController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: filterController.text.length,
      );
    });
  }

  Future<void> loadDevices({bool autoStartSingleIfAvailable = false}) async {
    _loadingDevices = true;
    _hasAttemptedDeviceLoad = true;
    _notify();

    try {
      final fetchedDevices = await _adbService.getDevices();
      if (_disposed) return;
      await _applyFetchedDevices(
        fetchedDevices,
        autoStartSingleIfAvailable: autoStartSingleIfAvailable,
      );
    } finally {
      _loadingDevices = false;
      _notify();
    }
  }

  Future<AdbMdnsDiscoveryResult> discoverWirelessServices() async {
    if (_pairingWireless || _connectingWireless) {
      const error =
          'Finish the current wireless ADB action before starting another one.';
      _wirelessError = error;
      _wirelessMessage = null;
      _notify();
      return AdbMdnsDiscoveryResult.failure(error: error);
    }

    _discoveringWireless = true;
    _hasAttemptedWirelessDiscovery = true;
    _wirelessMessage = null;
    _wirelessError = null;
    _notify();

    try {
      final result = await _adbService.discoverMdnsServices();
      if (_disposed) return result;

      if (result.isSuccess) {
        _wirelessServices = result.services;
        _wirelessError = null;
        _wirelessMessage = result.services.isEmpty
            ? 'No wireless ADB services found on the local network.'
            : 'Found ${result.services.length} wireless ADB service${result.services.length == 1 ? '' : 's'}.';
      } else {
        _wirelessServices = [];
        _wirelessMessage = null;
        _wirelessError = result.error;
      }

      return result;
    } finally {
      _discoveringWireless = false;
      _notify();
    }
  }

  Future<WirelessPairResult> pairWirelessDevice({
    required String address,
    required String pairingCode,
    Iterable<String> connectAddresses = const [],
  }) async {
    final normalizedAddress = address.trim();
    final normalizedCode = pairingCode.trim();
    if (normalizedAddress.isEmpty) {
      const error = 'Enter a pairing address such as 192.168.0.104:45673.';
      _wirelessError = error;
      _wirelessMessage = null;
      _notify();
      return WirelessPairResult.failure(error: error);
    }
    if (normalizedCode.isEmpty) {
      const error = 'Enter the wireless pairing code shown on the device.';
      _wirelessError = error;
      _wirelessMessage = null;
      _notify();
      return WirelessPairResult.failure(error: error);
    }
    if (_discoveringWireless || _connectingWireless) {
      const error =
          'Finish the current wireless ADB action before pairing a device.';
      _wirelessError = error;
      _wirelessMessage = null;
      _notify();
      return WirelessPairResult.failure(error: error);
    }

    _pairingWireless = true;
    _wirelessMessage = null;
    _wirelessError = null;
    _notify();

    try {
      final result = await _adbService.pairDevice(
        address: normalizedAddress,
        pairingCode: normalizedCode,
      );
      if (_disposed) {
        return result.isSuccess
            ? WirelessPairResult.paired(message: result.message)
            : WirelessPairResult.failure(
                error:
                    result.error ?? 'Failed to pair with $normalizedAddress.',
              );
      }

      if (!result.isSuccess) {
        final error = result.error ?? 'Failed to pair with $normalizedAddress.';
        _wirelessMessage = null;
        _wirelessError = error;
        return WirelessPairResult.failure(error: error);
      }

      _pairingWireless = false;
      _notify();

      final resolvedConnectAddresses = await _resolveWirelessConnectAddresses(
        pairingAddress: normalizedAddress,
        candidateAddresses: connectAddresses,
      );
      if (_disposed) {
        return WirelessPairResult.paired(
          message: result.message,
          connectAddresses: resolvedConnectAddresses,
        );
      }

      if (resolvedConnectAddresses.isEmpty) {
        final message =
            '${result.message ?? 'Paired successfully.'} No connect endpoint was discovered automatically.';
        _wirelessMessage = message;
        _wirelessError = null;
        return WirelessPairResult.paired(message: message);
      }

      final connectResult = await _connectWirelessDeviceInternal(
        candidateAddresses: resolvedConnectAddresses,
        host: _wirelessHostFromAddress(normalizedAddress),
        suppressFailureState: true,
      );
      if (_disposed) {
        return connectResult.isSuccess
            ? WirelessPairResult.autoConnected(
                message:
                    connectResult.message ??
                    'Paired and connected successfully.',
              )
            : WirelessPairResult.paired(
                message: connectResult.error,
                connectAddresses: resolvedConnectAddresses,
              );
      }

      if (connectResult.isSuccess) {
        final message =
            connectResult.message ?? 'Paired and connected successfully.';
        _wirelessMessage = message;
        _wirelessError = null;
        return WirelessPairResult.autoConnected(message: message);
      }

      final message =
          '${result.message ?? 'Paired successfully.'} Automatic connection could not be completed. You can retry connect manually.';
      _wirelessMessage = message;
      _wirelessError = null;
      return WirelessPairResult.paired(
        message: message,
        connectAddresses: resolvedConnectAddresses,
      );
    } finally {
      _pairingWireless = false;
      _notify();
    }
  }

  Future<AdbCommandResult> connectWirelessDevice({
    String? address,
    Iterable<String> candidateAddresses = const [],
  }) async {
    final normalizedAddresses = <String>[];
    void addAddress(String raw) {
      final normalized = raw.trim();
      if (normalized.isEmpty || normalizedAddresses.contains(normalized)) {
        return;
      }
      normalizedAddresses.add(normalized);
    }

    if (address != null) {
      addAddress(address);
    }
    for (final candidate in candidateAddresses) {
      addAddress(candidate);
    }

    if (normalizedAddresses.isEmpty) {
      const error = 'Enter a connect address such as 192.168.0.117:37251.';
      _wirelessError = error;
      _wirelessMessage = null;
      _notify();
      return AdbCommandResult.failure(error: error);
    }
    if (_discoveringWireless || _pairingWireless) {
      const error =
          'Finish the current wireless ADB action before connecting a device.';
      _wirelessError = error;
      _wirelessMessage = null;
      _notify();
      return AdbCommandResult.failure(error: error);
    }

    return _connectWirelessDeviceInternal(
      candidateAddresses: normalizedAddresses,
      host: _wirelessHostFromAddress(normalizedAddresses.first),
    );
  }

  Future<void> setSelectedDevice(Device? device) async {
    if (device == null) {
      if (selectedDevice == null) return;
      selectedDevice = null;
      if (isRunning) {
        await _stopLogcatInternal(resetState: true);
      }
      _notify();
      return;
    }

    await selectDeviceAndStart(device);
  }

  Future<void> selectDeviceAndStart(Device device) async {
    final sameDevice = selectedDevice?.id == device.id;
    _importedFileName = null;
    selectedDevice = device;
    _exitGetStarted();
    _notify();

    if (sameDevice && isRunning) return;
    await startLogcat();
  }

  Future<void> startLogcat() async {
    if (selectedDevice == null) return;
    _exitGetStartedIfWorkspaceReady();

    await _stopLogcatInternal(resetState: false);
    if (_disposed) return;

    _importedFileName = null;
    logs = [];
    _buffer.clear();
    _logsMemoryBytes = 0;
    _bufferMemoryBytes = 0;
    _invalidateFilteredLogs();
    logcatState = LogcatState.running;
    _notify();

    _logSub = _adbService.startLogcat(selectedDevice!).listen((logEntry) {
      if (_disposed || logcatState == LogcatState.paused) return;
      _buffer.add(logEntry);
      _bufferMemoryBytes += _estimateLogEntryBytes(logEntry);
    });

    _flushTimer?.cancel();
    _flushTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (_disposed || _buffer.isEmpty) return;

      logs = [...logs, ..._buffer];
      _logsMemoryBytes += _bufferMemoryBytes;
      _buffer.clear();
      _bufferMemoryBytes = 0;

      if (logs.length > logLinesLimit * 1.2) {
        final keep = logLinesLimit.floor();
        logs = logs.sublist(logs.length - keep);
        _logsMemoryBytes = _estimateLogsBytes(logs);
      }

      _invalidateFilteredLogs();
      _notify();

      if (autoScroll && scrollController.hasClients) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!scrollController.hasClients) return;
          scrollController.animateTo(
            scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 100),
            curve: Curves.easeOut,
          );
        });
      }
    });
  }

  Future<void> stopLogcat() => _stopLogcatInternal(resetState: true);

  Future<void> _stopLogcatInternal({required bool resetState}) async {
    _flushTimer?.cancel();
    _flushTimer = null;

    await _logSub?.cancel();
    _logSub = null;
    await _adbService.stopActiveLogcat();

    if (resetState && !_disposed) {
      logcatState = LogcatState.stopped;
      _notify();
    }
  }

  void togglePauseResume() {
    if (!isRunning) return;
    logcatState = isPaused ? LogcatState.running : LogcatState.paused;
    _notify();
  }

  void clearLogs() {
    logs = [];
    _buffer.clear();
    _logsMemoryBytes = 0;
    _bufferMemoryBytes = 0;
    _invalidateFilteredLogs();
    _notify();
  }

  Future<LogExportResult> exportLogs() async {
    return LogFileService.exportLogs(logs, selectedDevice);
  }

  Future<LogImportResult> importLogs() async {
    final result = await LogFileService.importLogs();
    if (_disposed || !result.isSuccess || result.logs == null) return result;

    await _stopLogcatInternal(resetState: false);
    if (_disposed) return result;

    selectedDevice = null;
    _importedFileName = result.fileName;
    logs = result.logs!;
    _buffer.clear();
    _logsMemoryBytes = _estimateLogsBytes(logs);
    _bufferMemoryBytes = 0;
    logcatState = LogcatState.stopped;
    _exitGetStarted();
    _invalidateFilteredLogs();
    _notify();
    return result;
  }

  void scrollToEnd() {
    if (!scrollController.hasClients) return;
    scrollController.animateTo(
      scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  void disableAutoScroll() {
    if (!autoScroll) return;
    _updateSettings(_settings.copyWith(autoScroll: false));
  }

  void clearFilter() {
    _debounceTimer?.cancel();
    filterController.clear();
    searchQuery = '';
    _appliedSearchQuery = '';
    _invalidateFilteredLogs();
    focusFilterInputs();
    _notify();
  }

  void onSearchChanged(String value) {
    searchQuery = value;
    _notify();

    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (_disposed) return;
      _appliedSearchQuery = value;
      _invalidateFilteredLogs();
      _notify();
    });
  }

  void setSelectedLogLevel(String level) {
    _updateSettings(_settings.copyWith(selectedLogLevel: level));
    _invalidateFilteredLogs();
  }

  void toggleWrapText() {
    _logViewerRevision++;
    _updateSettings(_settings.copyWith(wrapText: !wrapText));
  }

  void toggleAutoScroll() {
    _updateSettings(_settings.copyWith(autoScroll: !autoScroll));
  }

  void setHiddenColumns(Set<String> columns) {
    _logViewerRevision++;
    _updateSettings(_settings.copyWith(hiddenColumns: Set.of(columns)));
    _invalidateSearchMatches();
  }

  void setColumnWidths(Map<String, double> widths) {
    _updateSettings(_settings.copyWith(columnWidths: Map.of(widths)));
  }

  void setEditingLogLinesLimit(bool value) {
    _editingLogLinesLimit = value;
    if (value) {
      logLinesController.text = logLinesLimit.toString();
    }
    _notify();
  }

  bool submitLogLinesLimit([String? rawValue]) {
    final parsed = int.tryParse((rawValue ?? logLinesController.text).trim());
    if (parsed == null || parsed < 1000) {
      _editingLogLinesLimit = false;
      _notify();
      return false;
    }

    _editingLogLinesLimit = false;
    logLinesController.text = parsed.toString();
    _updateSettings(_settings.copyWith(logLinesLimit: parsed));

    if (logs.length > parsed) {
      logs = logs.sublist(logs.length - parsed);
      _logsMemoryBytes = _estimateLogsBytes(logs);
      _invalidateFilteredLogs();
    }

    _notify();
    return true;
  }

  void toggleSearchBar() {
    _inlineSearchDebounce?.cancel();
    _searchBarVisible = !_searchBarVisible;

    if (!_searchBarVisible) {
      _inlineSearchQuery = '';
      _appliedInlineSearchQuery = '';
      searchController.clear();
      _invalidateSearchMatches();
      _searchCurrentMatchIndex = 0;
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_disposed) return;
        searchFocusNode.requestFocus();
        searchController.selection = TextSelection(
          baseOffset: 0,
          extentOffset: searchController.text.length,
        );
      });
    }

    _notify();
  }

  void onInlineSearchChanged(String value) {
    _inlineSearchQuery = value;
    _searchCurrentMatchIndex = 0;
    _notify();

    _inlineSearchDebounce?.cancel();
    _inlineSearchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (_disposed) return;
      _appliedInlineSearchQuery = value;
      _invalidateSearchMatches();
      _notify();
    });
  }

  void setSearchCaseSensitive(bool value) {
    _inlineSearchDebounce?.cancel();
    _searchCaseSensitive = value;
    _appliedInlineSearchQuery = _inlineSearchQuery;
    _invalidateSearchMatches();
    _searchCurrentMatchIndex = 0;
    _notify();
  }

  void onSearchNext() {
    final matches = searchMatchIndices;
    if (matches.isEmpty) return;
    _searchCurrentMatchIndex = (_searchCurrentMatchIndex + 1) % matches.length;
    _notify();
  }

  void onSearchPrev() {
    final matches = searchMatchIndices;
    if (matches.isEmpty) return;
    _searchCurrentMatchIndex =
        (_searchCurrentMatchIndex - 1 + matches.length) % matches.length;
    _notify();
  }

  List<LogEntry> get filteredLogs {
    final selectedLevelValue = LogUtils.levelHierarchy[selectedLogLevel] ?? 4;

    if (_cachedFilteredLogs != null &&
        _lastLogsLength == logs.length &&
        _lastFilterQuery == _appliedSearchQuery &&
        _lastLogLevel == selectedLogLevel) {
      return _cachedFilteredLogs!;
    }

    _lastLogsLength = logs.length;
    _lastFilterQuery = _appliedSearchQuery;
    _lastLogLevel = selectedLogLevel;

    final query = _appliedSearchQuery.toLowerCase();
    _cachedFilteredLogs = logs.where((log) {
      final logLevelValue = LogUtils.levelHierarchy[log.level] ?? 4;
      if (logLevelValue > selectedLevelValue) return false;
      if (_appliedSearchQuery.isEmpty) return true;
      return log.lowercaseSearchable.contains(query);
    }).toList();

    return _cachedFilteredLogs!;
  }

  List<int> get searchMatchIndices {
    final filtered = filteredLogs;
    if (_cachedSearchMatchIndices != null &&
        _smCacheQuery == _appliedInlineSearchQuery &&
        _smCacheCaseSensitive == _searchCaseSensitive &&
        _smCacheHiddenCols.length == hiddenColumns.length &&
        _smCacheHiddenCols.containsAll(hiddenColumns) &&
        _smCacheFilteredLen == filtered.length) {
      return _cachedSearchMatchIndices!;
    }

    _smCacheQuery = _appliedInlineSearchQuery;
    _smCacheCaseSensitive = _searchCaseSensitive;
    _smCacheHiddenCols = Set.of(hiddenColumns);
    _smCacheFilteredLen = filtered.length;
    _cachedSearchMatchIndices = _computeSearchMatches(filtered);
    return _cachedSearchMatchIndices!;
  }

  int currentSearchMatchLogIndex(List<int> matches) {
    if (matches.isEmpty) return -1;
    return matches[_searchCurrentMatchIndex.clamp(0, matches.length - 1)];
  }

  String formatBytes(int bytes) {
    const units = ['B', 'KB', 'MB', 'GB'];
    var value = bytes.toDouble();
    var unitIndex = 0;

    while (value >= 1024 && unitIndex < units.length - 1) {
      value /= 1024;
      unitIndex++;
    }

    final precision = value >= 100 || unitIndex == 0 ? 0 : 1;
    return '${value.toStringAsFixed(precision)} ${units[unitIndex]}';
  }

  void _invalidateFilteredLogs() {
    _cachedFilteredLogs = null;
    _invalidateSearchMatches();
  }

  void _invalidateSearchMatches() {
    _cachedSearchMatchIndices = null;
  }

  Future<void> _applyFetchedDevices(
    List<Device> fetchedDevices, {
    bool autoStartSingleIfAvailable = false,
  }) async {
    final currentSelectionId = selectedDevice?.id;
    devices = fetchedDevices;

    if (currentSelectionId != null) {
      selectedDevice = fetchedDevices.firstWhereOrNull(
        (device) => device.id == currentSelectionId,
      );
    }

    if (currentSelectionId != null && selectedDevice == null) {
      selectedDevice = null;
      await _stopLogcatInternal(resetState: true);
    }

    final shouldAutoStartSingleDevice =
        autoStartSingleIfAvailable &&
        logs.isEmpty &&
        selectedDevice == null &&
        fetchedDevices.length == 1 &&
        !(isDeviceSelectedInAnotherTab?.call(fetchedDevices.single.id) ??
            false);

    if (shouldAutoStartSingleDevice) {
      await selectDeviceAndStart(fetchedDevices.single);
      return;
    }

    _exitGetStartedIfWorkspaceReady();
  }

  Future<Device?> _awaitWirelessDevice({
    String? exactAddress,
    String? host,
  }) async {
    const attempts = 5;
    for (var attempt = 0; attempt < attempts; attempt++) {
      final fetchedDevices = await _adbService.getDevices();
      if (_disposed) return null;

      await _applyFetchedDevices(fetchedDevices);
      final matchedDevice = fetchedDevices.firstWhereOrNull(
        (device) => _matchesConnectedWirelessDevice(
          device,
          exactAddress: exactAddress,
          host: host,
        ),
      );
      if (matchedDevice != null) {
        return matchedDevice;
      }

      if (attempt < attempts - 1) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    }

    return null;
  }

  Future<AdbCommandResult> _connectWirelessDeviceInternal({
    required Iterable<String> candidateAddresses,
    String? host,
    bool suppressFailureState = false,
  }) async {
    final addresses = <String>[];
    for (final candidate in candidateAddresses) {
      final normalized = candidate.trim();
      if (normalized.isEmpty || addresses.contains(normalized)) continue;
      addresses.add(normalized);
    }

    if (addresses.isEmpty) {
      const error = 'Enter a connect address such as 192.168.0.117:37251.';
      if (!suppressFailureState) {
        _wirelessError = error;
        _wirelessMessage = null;
        _notify();
      }
      return AdbCommandResult.failure(error: error);
    }

    _connectingWireless = true;
    _wirelessMessage = null;
    _wirelessError = null;
    _notify();

    try {
      final existingDevice = await _findConnectedWirelessDevice(
        exactAddresses: addresses,
        host: host,
      );
      if (_disposed) {
        return AdbCommandResult.success(
          message: 'Using existing wireless connection.',
        );
      }
      if (existingDevice != null) {
        final reusedResult = await _activateConnectedWirelessDevice(
          existingDevice,
          prefixMessage: 'Wireless device is already connected.',
        );
        if (!suppressFailureState || reusedResult.isSuccess) {
          _wirelessMessage = reusedResult.message;
          _wirelessError = reusedResult.error;
        }
        return reusedResult;
      }

      final failures = <String>[];
      for (final candidate in addresses) {
        final result = await _adbService.connectDevice(candidate);
        if (_disposed) {
          return result;
        }

        if (!result.isSuccess) {
          failures.add(result.error ?? 'Failed to connect to $candidate.');
          continue;
        }

        final matchedDevice = await _awaitWirelessDevice(
          exactAddress: candidate,
          host: host,
        );
        if (_disposed) {
          return result;
        }

        if (matchedDevice == null) {
          final message =
              '${result.message ?? 'Connected to $candidate.'} The device has not appeared in the device list yet.';
          if (!suppressFailureState) {
            _wirelessMessage = message;
            _wirelessError = null;
          }
          return AdbCommandResult.success(message: message);
        }

        final activatedResult = await _activateConnectedWirelessDevice(
          matchedDevice,
          prefixMessage: result.message ?? 'Connected to ${matchedDevice.id}.',
        );
        if (!suppressFailureState || activatedResult.isSuccess) {
          _wirelessMessage = activatedResult.message;
          _wirelessError = activatedResult.error;
        }
        return activatedResult;
      }

      final error = _describeWirelessConnectFailures(addresses, failures);
      if (!suppressFailureState) {
        _wirelessMessage = null;
        _wirelessError = error;
      }
      return AdbCommandResult.failure(error: error);
    } finally {
      _connectingWireless = false;
      _notify();
    }
  }

  Future<List<String>> _resolveWirelessConnectAddresses({
    required String pairingAddress,
    Iterable<String> candidateAddresses = const [],
  }) async {
    final providedAddresses = <String>[];
    for (final candidate in candidateAddresses) {
      final normalized = candidate.trim();
      if (normalized.isEmpty || providedAddresses.contains(normalized)) {
        continue;
      }
      providedAddresses.add(normalized);
    }
    if (providedAddresses.isNotEmpty) {
      return providedAddresses;
    }

    final host = _wirelessHostFromAddress(pairingAddress);
    final cachedAddresses = _pickWirelessConnectAddresses(
      services: _wirelessServices,
      host: host,
    );
    if (cachedAddresses.isNotEmpty) {
      return cachedAddresses;
    }

    final refreshedDiscovery = await _refreshWirelessServicesSnapshot();
    if (_disposed || !refreshedDiscovery.isSuccess) {
      return cachedAddresses;
    }

    return _pickWirelessConnectAddresses(
      services: refreshedDiscovery.services,
      host: host,
    );
  }

  Future<AdbMdnsDiscoveryResult> _refreshWirelessServicesSnapshot() async {
    _hasAttemptedWirelessDiscovery = true;
    final result = await _adbService.discoverMdnsServices();
    if (_disposed) return result;
    if (result.isSuccess) {
      _wirelessServices = result.services;
      _notify();
    }
    return result;
  }

  List<String> _pickWirelessConnectAddresses({
    required List<AdbMdnsService> services,
    required String? host,
  }) {
    final addresses = <String>[];
    final connectServices = services.where(
      (service) => service.type == AdbMdnsServiceType.connect,
    );

    for (final service in connectServices) {
      if (host != null && service.host != host) continue;
      if (!addresses.contains(service.address)) {
        addresses.add(service.address);
      }
    }

    if (addresses.isNotEmpty || host != null) {
      return addresses;
    }

    final allConnectAddresses = connectServices
        .map((service) => service.address)
        .toSet()
        .toList(growable: false);
    return allConnectAddresses.length == 1 ? allConnectAddresses : const [];
  }

  Future<Device?> _findConnectedWirelessDevice({
    required List<String> exactAddresses,
    required String? host,
  }) async {
    final fetchedDevices = await _adbService.getDevices();
    if (_disposed) return null;

    await _applyFetchedDevices(fetchedDevices);
    return fetchedDevices.firstWhereOrNull(
      (device) => _matchesConnectedWirelessDevice(
        device,
        exactAddresses: exactAddresses,
        host: host,
      ),
    );
  }

  bool _matchesConnectedWirelessDevice(
    Device device, {
    String? exactAddress,
    List<String> exactAddresses = const [],
    String? host,
  }) {
    if (device.status != 'device') {
      return false;
    }
    if (exactAddress != null && device.id == exactAddress) {
      return true;
    }
    if (exactAddresses.contains(device.id)) {
      return true;
    }
    final deviceHost = _wirelessHostFromAddress(device.id);
    return host != null && deviceHost == host;
  }

  Future<AdbCommandResult> _activateConnectedWirelessDevice(
    Device matchedDevice, {
    String? prefixMessage,
  }) async {
    if ((isDeviceSelectedInAnotherTab?.call(matchedDevice.id) ?? false) &&
        selectedDevice?.id != matchedDevice.id) {
      final message =
          '${prefixMessage ?? 'Wireless device is already connected.'} The device is already open in another tab.';
      return AdbCommandResult.success(message: message);
    }

    await selectDeviceAndStart(matchedDevice);
    if (_disposed) {
      return AdbCommandResult.success(
        message: prefixMessage ?? 'Connected to ${matchedDevice.id}.',
      );
    }

    final message = selectedDevice?.id == matchedDevice.id && isRunning
        ? '${prefixMessage ?? 'Connected to ${matchedDevice.id}.'} Live logs are ready in this tab.'
        : 'Connected to ${matchedDevice.id} and started live logs in this tab.';
    return AdbCommandResult.success(message: message);
  }

  String _describeWirelessConnectFailures(
    List<String> addresses,
    List<String> failures,
  ) {
    if (addresses.length == 1) {
      return failures.isNotEmpty
          ? failures.last
          : 'Failed to connect to ${addresses.single}.';
    }

    final summary = failures.isNotEmpty
        ? failures.last
        : 'None of the discovered connect ports succeeded.';
    return 'Tried ${addresses.length} connect ports (${addresses.join(', ')}), but none succeeded. $summary';
  }

  String? _wirelessHostFromAddress(String? address) {
    if (address == null) return null;
    final trimmed = address.trim();
    if (trimmed.isEmpty) return null;
    final separatorIndex = trimmed.lastIndexOf(':');
    if (separatorIndex <= 0) return null;
    return trimmed.substring(0, separatorIndex);
  }

  String _logColumnValue(LogEntry log, LogColumn column) => switch (column) {
    LogColumn.timestamp => log.timestamp,
    LogColumn.pid => log.packageName ?? log.pid,
    LogColumn.tid => log.tid,
    LogColumn.level => log.level,
    LogColumn.tag => log.tag,
    LogColumn.message => log.message,
  };

  List<int> _computeSearchMatches(List<LogEntry> items) {
    if (_appliedInlineSearchQuery.isEmpty) return [];

    final query = _searchCaseSensitive
        ? _appliedInlineSearchQuery
        : _appliedInlineSearchQuery.toLowerCase();
    final visibleColumns = LogColumn.values
        .where((column) => !hiddenColumns.contains(column.name))
        .toList();

    final result = <int>[];
    for (var index = 0; index < items.length; index++) {
      final log = items[index];
      for (final column in visibleColumns) {
        final text = _searchCaseSensitive
            ? _logColumnValue(log, column)
            : _logColumnValue(log, column).toLowerCase();
        if (text.contains(query)) {
          result.add(index);
          break;
        }
      }
    }
    return result;
  }

  int _estimateLogEntryBytes(LogEntry log) {
    int stringBytes(String value) => value.length * 2;

    return 128 +
        stringBytes(log.timestamp) +
        stringBytes(log.pid) +
        stringBytes(log.tid) +
        stringBytes(log.level) +
        stringBytes(log.tag) +
        stringBytes(log.message) +
        stringBytes(log.lowercaseSearchable) +
        (log.packageName == null ? 0 : stringBytes(log.packageName!));
  }

  int _estimateLogsBytes(Iterable<LogEntry> entries) {
    var total = 0;
    for (final entry in entries) {
      total += _estimateLogEntryBytes(entry);
    }
    return total;
  }

  @override
  void dispose() {
    _disposed = true;
    _flushTimer?.cancel();
    _debounceTimer?.cancel();
    _inlineSearchDebounce?.cancel();
    unawaited(_logSub?.cancel());
    unawaited(_adbService.dispose());
    scrollController.dispose();
    filterController.dispose();
    filterFocusNode.dispose();
    searchController.dispose();
    searchFocusNode.dispose();
    logLinesController.dispose();
    super.dispose();
  }
}
