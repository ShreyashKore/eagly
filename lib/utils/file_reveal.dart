import 'dart:io';

/// Host-side helpers for handing a saved file back to the OS: opening it in the
/// default application, or revealing it in the file manager. Both spawn a
/// detached process (same approach as [openExternalUrl]) so nothing blocks and
/// no console window flashes on Windows.

/// Opens [path] (file or folder) with the OS default handler.
/// Returns false when the handler could not be launched.
Future<bool> openPathExternally(String path) {
  return _spawn(switch (Platform.operatingSystem) {
    // ShellExecute via rundll32 launches as a GUI process, so no console
    // window flashes the way `cmd /c start` does.
    'windows' => ('rundll32.exe', ['url.dll,FileProtocolHandler', path]),
    'macos' => ('open', [path]),
    _ => ('xdg-open', [path]),
  });
}

/// Reveals [path] in the OS file manager, selecting the entry where the
/// platform supports it (macOS and Windows do; on Linux we fall back to just
/// opening the containing folder). Returns false if nothing could be launched.
Future<bool> revealPathInFileManager(String path) async {
  final launched = await _spawn(switch (Platform.operatingSystem) {
    'windows' => ('explorer.exe', ['/select,${_windowsPath(path)}']),
    'macos' => ('open', ['-R', path]),
    _ => ('xdg-open', [_containingFolder(path)]),
  });
  if (launched) return true;
  // Selecting failed (deleted file, unusual file manager) — settle for the
  // containing folder.
  return openPathExternally(_containingFolder(path));
}

/// The folder holding [path], or [path] itself when it is already a folder.
String _containingFolder(String path) {
  if (Directory(path).existsSync()) return path;
  return File(path).parent.path;
}

/// `explorer /select,` wants back-slashes and no quoting of its own.
String _windowsPath(String path) => path.replaceAll('/', r'\');

Future<bool> _spawn((String, List<String>) command) async {
  final (executable, arguments) = command;
  try {
    await Process.start(executable, arguments, mode: ProcessStartMode.detached);
    return true;
  } on ProcessException {
    return false;
  }
}
