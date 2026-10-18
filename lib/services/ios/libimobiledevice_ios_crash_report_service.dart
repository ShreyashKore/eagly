import '../tools/idevice_crash_report_tool.dart';
import 'ios_crash_report_service.dart';

/// [IosCrashReportService] backed by the bundled `idevicecrashreport` CLI.
class LibimobiledeviceIosCrashReportService({
  IdeviceCrashReportTool? ideviceCrashReportTool,
}) implements IosCrashReportService {
  this : _tool = ideviceCrashReportTool ?? IdeviceCrashReportTool();

  final IdeviceCrashReportTool _tool;

  @override
  Future<CrashReportPullResult> pullReports(String deviceId) =>
      _tool.pullReports(deviceId);
}
