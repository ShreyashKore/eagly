import 'dart:io';

/// Resolves the path to a bundled executable based on the current platform.
String? resolveBundledExecutablePath(String executableName) {
  final execPath = Platform.resolvedExecutable;
  final execDir = File(execPath).parent;
  final fileName = Platform.isWindows && !executableName.endsWith('.exe')
      ? '$executableName.exe'
      : executableName;

  final executablePath = switch (Platform.operatingSystem) {
    'macos' => '${execDir.path}/$fileName',
    'linux' => '${execDir.path}/data/$fileName',
    'windows' => '${execDir.path}/data/$fileName',
    _ => null,
  };

  if (executablePath == null) {
    return null;
  }

  final file = File(executablePath);
  if (file.existsSync()) {
    return executablePath;
  }

  return null;
}

/// Resolves the path to the bundled adb binary based on the current platform.
String? resolveBundledAdbPath() => resolveBundledExecutablePath('adb');

