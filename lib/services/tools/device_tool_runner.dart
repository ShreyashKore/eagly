import 'tool_process_runner.dart';

/// A [ToolProcessRunner] for any bundled CLI addressed only by name.
///
/// The dedicated tool wrappers (`AdbTool`, `IdeviceInstallerTool`, …) parse
/// their output into domain objects; the Utilities feature instead shows raw
/// output, so it needs nothing more than "run this executable with these
/// arguments" for a whole family of binaries.
class DeviceToolRunner extends ToolProcessRunner {
  DeviceToolRunner({required super.executableName, super.executablePath});
}
