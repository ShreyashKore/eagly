import 'dart:io';

/// Resolves the path to the bundled adb binary based on the current platform.
///
/// The binary is placed in the app bundle during build:
/// - macOS: Contents/Resources/adb
/// - Linux: data/adb
/// - Windows: data/adb.exe
String? resolveBundledAdbPath() {
  final execPath = Platform.resolvedExecutable;
  final execDir = File(execPath).parent;

  String adbPath;

  if (Platform.isMacOS) {
    // macOS: executable is at AppBundle.app/Contents/MacOS/logview
    // adb is at AppBundle.app/Contents/MacOS/adb
    adbPath = '${execDir.path}/adb';
  } else if (Platform.isLinux) {
    // Linux: executable is at bundle/logview
    // adb is at bundle/data/adb
    adbPath = '${execDir.path}/data/adb';
  } else if (Platform.isWindows) {
    // Windows: executable is at bundle/logview.exe
    // adb is at bundle/data/adb.exe
    adbPath = '${execDir.path}/data/adb.exe';
  } else {
    return null;
  }

  final file = File(adbPath);
  if (file.existsSync()) {
    return adbPath;
  }

  return null;
}
