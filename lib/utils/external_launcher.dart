import 'dart:io';

/// Opens [url] in the OS default handler (browser, Store, …) without pulling in
/// a plugin. Protocol URIs such as `ms-windows-store://` are handled by the
/// platform shell. Returns false if the handler could not be launched.
Future<bool> openExternalUrl(String url) async {
  try {
    final (executable, arguments) = switch (Platform.operatingSystem) {
      // Route through ShellExecute (via rundll32) so custom protocol URIs like
      // `ms-windows-store://` reach their registered handler. Handing the URI
      // to `explorer.exe` instead makes it open a File Explorer window, and
      // `rundll32` launches as a GUI process (no flashing console window).
      'windows' => ('rundll32.exe', ['url.dll,FileProtocolHandler', url]),
      'macos' => ('open', [url]),
      _ => ('xdg-open', [url]),
    };
    await Process.start(executable, arguments, mode: ProcessStartMode.detached);
    return true;
  } on ProcessException {
    return false;
  }
}
