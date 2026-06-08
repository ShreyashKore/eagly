import 'dart:io';

Directory? resolveBundledToolsDirectory() {
  final execPath = Platform.resolvedExecutable;
  final execDir = File(execPath).parent;

  final candidatePath = switch (Platform.operatingSystem) {
    'macos' => execDir.path,
    'linux' => '${execDir.path}/data',
    'windows' => '${execDir.path}/data',
    _ => null,
  };

  if (candidatePath == null) {
    return null;
  }

  final directory = Directory(candidatePath);
  if (!directory.existsSync()) {
    return null;
  }

  return directory;
}

/// Resolves the path to a bundled executable based on the current platform.
String? resolveBundledExecutablePath(String executableName) {
  final toolsDirectory = resolveBundledToolsDirectory();
  final fileName = Platform.isWindows && !executableName.endsWith('.exe')
      ? '$executableName.exe'
      : executableName;

  if (toolsDirectory == null) {
    return null;
  }

  final executablePath = '${toolsDirectory.path}/$fileName';
  final file = File(executablePath);
  if (file.existsSync()) {
    return executablePath;
  }

  return null;
}
