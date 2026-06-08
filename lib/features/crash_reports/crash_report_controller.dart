import 'dart:async';
import 'dart:io';

import '../../data/crash_report.dart';
import '../../data/device.dart';
import '../../services/tools/idevice_crash_report_tool.dart';
import '../../session/feature_controller.dart';
import '../../utils/utils.dart';

enum CrashReportLoadState { idle, loading, ready, error, unsupported }

/// Per-device crash-report feature for iOS. Pulls crash reports off the device
/// with `idevicecrashreport`, keeps the parsed list + the currently selected
/// report's body, and manages the temp directory the reports are copied into.
/// Pane *visibility* lives on the owning [DeviceSessionController]; this
/// controller only manages the data.
class CrashReportController extends FeatureController {
  CrashReportController(super.session);

  CrashReportLoadState loadState = CrashReportLoadState.idle;
  String? error;
  List<CrashReport> reports = const [];
  CrashReport? selectedReport;
  String? selectedReportBody;
  double paneWidth = 360;

  Directory? _outputDir;
  bool _disposed = false;
  bool _loadedOnce = false;

  bool get isLoading => loadState == CrashReportLoadState.loading;
  bool get isSupported => device is IosDevice;

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
      _notify();
    } catch (err) {
      if (_disposed) return;
      loadState = CrashReportLoadState.error;
      error = describeError(err);
      _notify();
    }
  }

  /// Selects a report and loads its full body for display.
  Future<void> select(CrashReport report) async {
    selectedReport = report;
    selectedReportBody = null;
    _notify();
    try {
      final body = await File(report.filePath).readAsString();
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

  /// Adjusts the crash pane width (clamped) when the user drags its edge.
  void setPaneWidth(double width) {
    final clamped = width.clamp(300.0, 760.0);
    if (clamped == paneWidth) return;
    paneWidth = clamped;
    _notify();
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
    unawaited(_deleteDir(_outputDir));
    super.dispose();
  }
}
