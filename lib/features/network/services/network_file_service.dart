import 'package:collection/collection.dart';
import 'package:file_picker/file_picker.dart';

import '../../../utils/timestamp_utils.dart';

/// The Network pane's file dialogs. Reading and writing the files is the
/// controller's job; this only asks the user where.
abstract final class NetworkFileService {
  /// Asks for a HAR file to open. Null when the user cancels.
  static Future<String?> pickHarToOpen() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Open HAR file',
      type: FileType.custom,
      allowedExtensions: const ['har', 'json'],
    );
    return result?.files.firstOrNull?.path;
  }

  /// Asks where to save an export. Null when the user cancels.
  static Future<String?> pickHarSavePath(String suggestedName) {
    return FilePicker.platform.saveFile(
      dialogTitle: 'Export as HAR',
      fileName: suggestedName,
      type: FileType.custom,
      allowedExtensions: const ['har'],
    );
  }

  /// `<device>-network-<yyyyMMdd-HHmmss>.har`, safe on every file system.
  static String suggestedHarName(String deviceName, DateTime now) {
    final stamp = fileNameTimestamp(now);
    final device = deviceName
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return '${device.isEmpty ? 'device' : device}-network-$stamp.har';
  }
}
