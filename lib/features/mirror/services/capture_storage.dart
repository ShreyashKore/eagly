import 'dart:io';

import 'package:file_picker/file_picker.dart';

import '../../../services/preferences_service.dart';

/// Where screenshots and screen recordings are written.
///
/// By default captures land in a fixed folder (`<Pictures>/Eagly`, overridable
/// from Settings) and no dialog is shown; turning on
/// [PreferencesService.captureAskEveryTime] restores the save-file dialog.
class CaptureStorage {
  const CaptureStorage._();

  /// Sub-folder created inside the user's pictures folder by default.
  static const _defaultFolderName = 'Eagly';

  /// The effective capture folder: the saved preference when it is set,
  /// otherwise [defaultDirectory]. The folder is not guaranteed to exist yet —
  /// [ensureDirectory] creates it.
  static String resolveDirectory() =>
      PreferencesService.captureDirectory ?? defaultDirectory();

  /// Platform default: `<home>/Pictures/Eagly`, falling back to `<home>/Eagly`
  /// when there is no pictures folder, and to the system temp dir when the
  /// home directory cannot be determined at all.
  static String defaultDirectory() {
    final home =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    if (home == null || home.isEmpty) {
      return _join(Directory.systemTemp.path, _defaultFolderName);
    }
    final pictures = _join(home, 'Pictures');
    final parent = Directory(pictures).existsSync() ? pictures : home;
    return _join(parent, _defaultFolderName);
  }

  /// Creates the capture folder if needed and returns it. Falls back to the
  /// platform default when the configured folder cannot be created (e.g. an
  /// external drive that is no longer mounted).
  static Future<Directory> ensureDirectory() async {
    final configured = Directory(resolveDirectory());
    try {
      return await configured.create(recursive: true);
    } on FileSystemException {
      return Directory(defaultDirectory()).create(recursive: true);
    }
  }

  /// `<prefix>-20260901-134512.<extension>`, de-duplicated with a `-2`, `-3`, …
  /// suffix so a burst of captures within the same second never overwrites.
  static String buildFileName(
    String prefix,
    String extension, {
    DateTime? now,
  }) {
    final n = now ?? DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final stamp =
        '${n.year}${two(n.month)}${two(n.day)}-'
        '${two(n.hour)}${two(n.minute)}${two(n.second)}';
    return '$prefix-$stamp.$extension';
  }

  /// Resolves the absolute path a capture should be written to.
  ///
  /// Returns `null` only when the user cancels the save dialog (which is shown
  /// exclusively when "ask every time" is on).
  static Future<String?> resolveTargetPath({
    required String dialogTitle,
    required String prefix,
    required String extension,
  }) async {
    final fileName = buildFileName(prefix, extension);

    if (!PreferencesService.captureAskEveryTime) {
      final directory = await ensureDirectory();
      return _uniquePath(directory.path, fileName, extension);
    }

    final chosen = await FilePicker.platform.saveFile(
      dialogTitle: dialogTitle,
      fileName: fileName,
      initialDirectory: _existingDirectory(resolveDirectory()),
      type: FileType.custom,
      allowedExtensions: [extension],
    );
    if (chosen == null) return null;
    final path = chosen.toLowerCase().endsWith('.$extension')
        ? chosen
        : '$chosen.$extension';
    await PreferencesService.setLastFileDialogDirectory(File(path).parent.path);
    return path;
  }

  static String _uniquePath(
    String directory,
    String fileName,
    String extension,
  ) {
    final stem = fileName.substring(0, fileName.length - extension.length - 1);
    var candidate = _join(directory, fileName);
    var counter = 2;
    while (File(candidate).existsSync()) {
      candidate = _join(directory, '$stem-$counter.$extension');
      counter++;
    }
    return candidate;
  }

  static String? _existingDirectory(String path) =>
      Directory(path).existsSync() ? path : null;

  static String _join(String parent, String child) =>
      '$parent${Platform.pathSeparator}$child';
}
