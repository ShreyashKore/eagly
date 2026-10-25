import 'package:file_picker/file_picker.dart';

import '../../../utils/file_dialog_directory.dart';

/// Thin wrapper over `file_picker` for the file-manager's host-side dialogs:
/// choosing local files to upload to the device, and choosing a destination
/// folder for downloads. Reuses the app-wide "last dialog directory" so the
/// pickers reopen where the user last was.
class const FileTransferPicker._() {
  /// Opens a multi-select file picker; returns the chosen absolute paths, or an
  /// empty list if cancelled.
  static Future<List<String>> pickFilesToUpload(String deviceLabel) async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Upload to $deviceLabel',
      initialDirectory: FileDialogDirectory.initial(),
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
      await FileDialogDirectory.rememberParentOf(paths.first);
    }
    return paths;
  }

  /// Opens a directory picker for a download destination; returns the chosen
  /// folder, or `null` if cancelled.
  static Future<String?> pickDownloadDirectory(String fileName) async {
    final directory = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Download $fileName to…',
      initialDirectory: FileDialogDirectory.initial(),
    );
    if (directory != null) {
      await FileDialogDirectory.remember(directory);
    }
    return directory;
  }
}
