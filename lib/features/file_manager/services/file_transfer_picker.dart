import 'dart:io';

import 'package:file_picker/file_picker.dart';

import '../../../services/preferences_service.dart';

/// Thin wrapper over `file_picker` for the file-manager's host-side dialogs:
/// choosing local files to upload to the device, and choosing a destination
/// folder for downloads. Reuses the app-wide "last dialog directory" so the
/// pickers reopen where the user last was.
class FileTransferPicker {
  const FileTransferPicker._();

  /// Opens a multi-select file picker; returns the chosen absolute paths, or an
  /// empty list if cancelled.
  static Future<List<String>> pickFilesToUpload(String deviceLabel) async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Upload to $deviceLabel',
      initialDirectory: await _initialDirectory(),
      allowMultiple: true,
      type: FileType.any,
    );
    if (result == null) return const [];

    final paths = result.files
        .map((file) => file.path)
        .whereType<String>()
        .where((path) => path.trim().isNotEmpty)
        .toList();
    if (paths.isNotEmpty) {
      await _rememberDirectory(File(paths.first).parent.path);
    }
    return paths;
  }

  /// Opens a directory picker for a download destination; returns the chosen
  /// folder, or `null` if cancelled.
  static Future<String?> pickDownloadDirectory(String fileName) async {
    final directory = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Download $fileName to…',
      initialDirectory: await _initialDirectory(),
    );
    if (directory != null) {
      await _rememberDirectory(directory);
    }
    return directory;
  }

  static Future<void> _rememberDirectory(String path) async {
    if (_isUsableDirectory(path)) {
      await PreferencesService.setLastFileDialogDirectory(path);
    }
  }

  static Future<String?> _initialDirectory() async {
    final remembered = PreferencesService.lastFileDialogDirectory;
    if (_isUsableDirectory(remembered)) return remembered;

    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'];
    if (home == null || home.isEmpty) return null;
    for (final candidate in [
      '$home${Platform.pathSeparator}Downloads',
      '$home${Platform.pathSeparator}Documents',
      home,
    ]) {
      if (_isUsableDirectory(candidate)) return candidate;
    }
    return null;
  }

  static bool _isUsableDirectory(String? path) {
    if (path == null || path.isEmpty) return false;
    final directory = Directory(path);
    return directory.isAbsolute && directory.existsSync();
  }
}
