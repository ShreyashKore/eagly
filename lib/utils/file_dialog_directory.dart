import 'dart:io';

import '../services/preferences_service.dart';

/// Where the host's file dialogs open: the folder the user last picked from
/// in any of them (`PreferencesService.lastFileDialogDirectory`), else
/// Downloads, Documents or the home folder — the first that exists.
class const FileDialogDirectory._() {
  /// The folder a dialog should open in, or `null` to leave it to the system.
  static String? initial() {
    final remembered = PreferencesService.lastFileDialogDirectory;
    if (_isUsable(remembered)) return remembered;

    final home = userHomeDirectory();
    if (home == null) return null;
    for (final candidate in [
      '$home${Platform.pathSeparator}Downloads',
      '$home${Platform.pathSeparator}Documents',
      home,
    ]) {
      if (_isUsable(candidate)) return candidate;
    }
    return null;
  }

  /// Remembers [directory] for the next dialog, if it exists.
  static Future<void> remember(String directory) async {
    if (_isUsable(directory)) {
      await PreferencesService.setLastFileDialogDirectory(directory);
    }
  }

  /// Remembers the folder holding [path] — a picked file, or a bundle
  /// directory such as an `.app`.
  static Future<void> rememberParentOf(String path) =>
      remember(File(path).parent.path);

  static bool _isUsable(String? path) {
    if (path == null || path.isEmpty) return false;
    final directory = Directory(path);
    return directory.isAbsolute && directory.existsSync();
  }
}

/// The user's home folder, or `null` when the environment doesn't say:
/// `HOME`, then Windows' `USERPROFILE`, then `HOMEDRIVE` + `HOMEPATH`.
String? userHomeDirectory() {
  final env = Platform.environment;
  for (final home in [
    env['HOME'],
    env['USERPROFILE'],
    if ((env['HOMEDRIVE'] ?? '').isNotEmpty &&
        (env['HOMEPATH'] ?? '').isNotEmpty)
      '${env['HOMEDRIVE']}${env['HOMEPATH']}',
  ]) {
    if (home != null && home.isNotEmpty) return home;
  }
  return null;
}
