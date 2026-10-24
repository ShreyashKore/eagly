import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:sentry_flutter/sentry_flutter.dart';

import 'data/crash_report.dart';
import '../../data/device.dart';
import '../../services/app_breadcrumbs.dart';
import '../../services/ios/ios_crash_report_service.dart';
import '../../session/feature_controller.dart';
import '../../utils/utils.dart';
import 'utils.dart';

enum CrashReportLoadState { idle, loading, ready, error, unsupported }

/// Per-device crash-report feature for iOS. Pulls crash reports off the device
/// with `idevicecrashreport`, keeps the parsed list + the currently selected
/// report's body, and manages the temp directory the reports are copied into.
/// Pane *visibility* lives on the owning [DeviceSessionController]; this
/// controller only manages the data.
class CrashReportController(super.session) extends FeatureController {
  CrashReportLoadState loadState = CrashReportLoadState.idle;
  String? error;
  List<CrashReport> reports = const [];
  CrashReport? selectedReport;
  String? selectedReportBody;

  Directory? _outputDir;
  bool _disposed = false;
  bool _loadedOnce = false;

  /// How long typing settles before report bodies are searched: each search
  /// reads every report off disk.
  static const contentSearchDelay = Duration(milliseconds: 200);

  String _searchText = '';

  /// Paths of [reports] whose body contains the last searched query.
  Set<String> _contentMatches = const {};
  Timer? _contentSearchTimer;
  int _contentSearchGeneration = 0;
  bool _isSearchingContent = false;

  bool get isLoading => loadState == CrashReportLoadState.loading;
  bool get isSupported => device is IosDevice;

  String get searchText => _searchText;

  /// Whether report bodies are still being searched for [searchText]; until
  /// they are, [filteredReports] holds the title matches and the body matches
  /// of the previous query.
  bool get isSearchingContent => _isSearchingContent;

  String get _query => _searchText.trim().toLowerCase();

  /// [reports] narrowed by [searchText]: a report stays when its process name
  /// or file name contains it, or its body does. Case-insensitive.
  List<CrashReport> get filteredReports {
    final query = _query;
    if (query.isEmpty) return reports;
    return reports
        .where(
          (report) =>
              report.processName.toLowerCase().contains(query) ||
              report.fileName.toLowerCase().contains(query) ||
              _contentMatches.contains(report.filePath),
        )
        .toList();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Loads reports the first time the pane is shown. Idempotent.
  Future<void> ensureLoaded() async {
    if (_loadedOnce) return;
    await refresh();
  }

  /// Re-pulls crash reports from the device.
  Future<void> refresh() async {
    if (_disposed) return;
    if (!isSupported) {
      loadState = CrashReportLoadState.unsupported;
      error = 'Crash report reading is available for iOS devices.';
      _notify();
      return;
    }
    if (!isConnected) {
      loadState = CrashReportLoadState.error;
      error = 'The device is disconnected. Reconnect it to read crash reports.';
      _notify();
      return;
    }
    if (isLoading) return;

    _loadedOnce = true;
    loadState = CrashReportLoadState.loading;
    error = null;
    _notify();

    try {
      final result = await service.pullCrashReports();
      if (_disposed) {
        await _deleteDir(result.outputDir);
        return;
      }

      await _deleteDir(_outputDir);
      _outputDir = result.outputDir;
      reports = result.reports;
      // The old matches are paths in the directory just deleted.
      _contentMatches = const {};
      _scheduleContentSearch();
      AppBreadcrumbs.action(
        'Pulled ${reports.length} crash report(s) from ${device.displayName}',
        category: 'crash_reports',
      );

      // Keep a valid selection across refreshes when possible.
      final previousPath = selectedReport?.filePath;
      selectedReport = null;
      selectedReportBody = null;
      loadState = CrashReportLoadState.ready;
      _notify();

      if (previousPath != null) {
        final previousName = _fileNameOf(previousPath);
        for (final report in reports) {
          if (report.fileName == previousName) {
            await select(report);
            break;
          }
        }
      }
    } on CrashReportException catch (err) {
      if (_disposed) return;
      loadState = CrashReportLoadState.error;
      error = err.message;
      AppBreadcrumbs.action(
        'Crash report pull failed for ${device.displayName}',
        category: 'crash_reports',
        level: SentryLevel.error,
        data: {'error': err.message},
      );
      _notify();
    } catch (err) {
      if (_disposed) return;
      loadState = CrashReportLoadState.error;
      error = describeError(err);
      AppBreadcrumbs.action(
        'Crash report pull failed for ${device.displayName}',
        category: 'crash_reports',
        level: SentryLevel.error,
        data: {'error': describeError(err)},
      );
      _notify();
    }
  }

  /// Selects a report and loads its full body for display.
  Future<void> select(CrashReport report) async {
    selectedReport = report;
    selectedReportBody = null;
    _notify();
    try {
      final body = await readTextLenient(File(report.filePath));
      if (_disposed || selectedReport != report) return;
      selectedReportBody = body;
    } catch (err) {
      if (_disposed || selectedReport != report) return;
      selectedReportBody = 'Failed to read crash report: ${describeError(err)}';
    }
    _notify();
  }

  void clearSelection() {
    if (selectedReport == null) return;
    selectedReport = null;
    selectedReportBody = null;
    _notify();
  }

  void setSearchText(String value) {
    if (_searchText == value) return;
    final queryChanged = value.trim().toLowerCase() != _query;
    _searchText = value;
    if (queryChanged) _scheduleContentSearch();
    _notify();
  }

  /// Searches report bodies for the current query once typing settles. A
  /// newer query, or a refresh, supersedes a search still in flight.
  void _scheduleContentSearch() {
    _contentSearchTimer?.cancel();
    final generation = ++_contentSearchGeneration;
    final query = _query;
    if (query.isEmpty) {
      _contentMatches = const {};
      _isSearchingContent = false;
      return;
    }
    _isSearchingContent = true;
    final paths = [for (final report in reports) report.filePath];
    _contentSearchTimer = Timer(contentSearchDelay, () async {
      final matches = await _searchContent(paths, query);
      if (_disposed || generation != _contentSearchGeneration) return;
      _contentMatches = matches;
      _isSearchingContent = false;
      _notify();
    });
  }

  /// Static, so the isolate's closure doesn't capture `this`.
  static Future<Set<String>> _searchContent(
    List<String> paths,
    String query,
  ) async {
    try {
      return await Isolate.run(
        () => CrashReportUtils.pathsContaining(paths, query),
      );
    } catch (_) {
      return const {};
    }
  }

  String _fileNameOf(String path) => extractFileName(path);

  Future<void> _deleteDir(Directory? dir) async {
    if (dir == null) return;
    try {
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {}
  }

  // Reports already pulled remain readable after a disconnect; a fresh load is
  // gated on reconnection inside [refresh], so no disconnect hook is needed.

  @override
  void dispose() {
    _disposed = true;
    _contentSearchTimer?.cancel();
    unawaited(_deleteDir(_outputDir));
    super.dispose();
  }
}
