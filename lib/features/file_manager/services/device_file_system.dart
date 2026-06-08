import '../../../data/device.dart';
import '../data/device_file_entry.dart';
import 'android_file_system.dart';
import 'ios_file_system.dart';

/// Thrown when a device file operation fails. [message] is already
/// human-readable and safe to surface in the UI.
class DeviceFileException implements Exception {
  DeviceFileException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Platform-agnostic view of a device's browsable file system. Android is
/// backed by `adb`, iOS by `afcclient` (the AFC "media" sandbox). Both speak
/// POSIX-style paths, so navigation helpers are shared as top-level functions.
///
/// This abstraction is intentionally self-contained inside the file-manager
/// feature so the feature owns its own device dependencies rather than routing
/// through the shared session service.
abstract interface class DeviceFileSystem {
  /// Builds the file system appropriate for [device]. [executablePath] lets
  /// tests inject a stub binary; production resolves the bundled tool.
  factory DeviceFileSystem.forDevice(Device device, {String? executablePath}) {
    return switch (device) {
      AndroidDevice() => AndroidFileSystem(
        deviceId: device.id,
        executablePath: executablePath,
      ),
      IosDevice() => IosFileSystem(
        deviceId: device.id,
        executablePath: executablePath,
      ),
    };
  }

  /// Short label for the browsable storage (e.g. "Internal storage").
  String get storageLabel;

  /// Absolute path the browser opens at on first load.
  String get initialPath;

  /// The absolute root past which the user cannot navigate up.
  String get rootPath;

  bool get supportsCreateDirectory;
  bool get supportsDelete;
  bool get supportsRename;

  /// Lists the directory at [path]. Throws [DeviceFileException] on failure.
  Future<List<DeviceFileEntry>> list(String path);

  /// Copies [entry] off the device into [localDirectory] (recursively for
  /// directories). Returns the absolute local path that was written.
  Future<String> download({
    required DeviceFileEntry entry,
    required String localDirectory,
  });

  /// Copies the local file/directory at [localPath] into the device directory
  /// [deviceDirectory] (recursively for directories).
  Future<void> upload({
    required String localPath,
    required String deviceDirectory,
  });

  /// Creates a new directory named [name] inside [parentPath].
  Future<void> createDirectory({
    required String parentPath,
    required String name,
  });

  /// Renames [entry] to [newName], keeping it in the same directory.
  Future<void> rename({
    required DeviceFileEntry entry,
    required String newName,
  });

  /// Removes [entry] from the device (recursively for directories).
  Future<void> delete(DeviceFileEntry entry);
}

/// Joins [parent] and a child [name] into an absolute POSIX path.
String posixJoin(String parent, String name) {
  if (parent.isEmpty || parent == '/') return '/$name';
  return parent.endsWith('/') ? '$parent$name' : '$parent/$name';
}

/// Returns the parent directory of [path], or `/` at the root.
String posixParent(String path) {
  final normalized = _stripTrailingSlash(path);
  final index = normalized.lastIndexOf('/');
  if (index <= 0) return '/';
  return normalized.substring(0, index);
}

/// Splits [path] into its non-empty segments (e.g. `/a/b` → `['a', 'b']`).
List<String> posixSegments(String path) {
  return path.split('/').where((segment) => segment.isNotEmpty).toList();
}

String _stripTrailingSlash(String path) {
  if (path.length > 1 && path.endsWith('/')) {
    return path.substring(0, path.length - 1);
  }
  return path;
}
