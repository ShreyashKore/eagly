import 'dart:io';

import 'package:flutter/foundation.dart';

/// Opens [url] in the user's default browser via the OS-native opener. The app
/// bundles its own CLI tools rather than depending on `url_launcher`, so we
/// shell out the same way the rest of the app drives external processes.
/// Best-effort and fire-and-forget — failures are swallowed (logged in debug).
Future<void> openExternalUrl(String url) async {
  try {
    if (Platform.isMacOS) {
      await Process.run('open', [url]);
    } else if (Platform.isWindows) {
      // The empty first argument is `start`'s window-title slot.
      await Process.run('cmd', ['/c', 'start', '', url]);
    } else if (Platform.isLinux) {
      await Process.run('xdg-open', [url]);
    }
  } catch (error) {
    if (kDebugMode) debugPrint('Failed to open $url: $error');
  }
}
