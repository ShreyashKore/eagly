import 'dart:io';

import '../../../src/rust/api/ios.dart' as rust;
import '../../../utils/utils.dart';
import '../data/device_file_entry.dart';
import 'device_file_system.dart';

/// AFC-backed file system for iOS devices, over the `idevice` crate.
///
/// Talks to the AFC "media" sandbox directly — the user-visible area Finder
/// exposes (DCIM, Downloads, Books, …). Unlike the `afcclient` backend this
/// needs no external binary, which matters: `afcclient` is bundled on no
/// platform, so the CLI path only works for users who installed
/// libimobiledevice themselves.
class RustIosFileSystem implements DeviceFileSystem {
  RustIosFileSystem({required this.deviceId});

  final String deviceId;

  @override
  String get storageLabel => 'Media (AFC)';

  @override
  String get initialPath => '/';

  // AFC media sandbox: `/Downloads` is the user-visible spot exposed in Finder
  // and is writable, so dropped files land somewhere the user can find them.
  @override
  String get dropTargetDirectory => '/Downloads';

  @override
  String get rootPath => '/';

  @override
  bool get supportsCreateDirectory => true;

  @override
  bool get supportsDelete => true;

  @override
  bool get supportsRename => true;

  @override
  Future<List<DeviceFileEntry>> list(String path) async {
    final entries = await _guard(
      () => rust.listIosFiles(udid: deviceId, path: path),
      'Failed to list $path.',
    );

    return [
      for (final entry in entries)
        DeviceFileEntry(
          name: entry.name,
          path: posixJoin(path, entry.name),
          type: _typeFromIfmt(entry.kind),
          sizeBytes: entry.kind == 'S_IFDIR' ? null : entry.sizeBytes.toInt(),
          modified: entry.modifiedMs == null || entry.modifiedMs == 0
              ? null
              : DateTime.fromMillisecondsSinceEpoch(entry.modifiedMs!.toInt()),
          linkTarget: entry.linkTarget,
        ),
    ];
  }

  @override
  Future<String> download({
    required DeviceFileEntry entry,
    required String localDirectory,
  }) async {
    final localPath = '$localDirectory${Platform.pathSeparator}${entry.name}';
    await _guard(
      () => rust.downloadIosPath(
        udid: deviceId,
        devicePath: entry.path,
        localPath: localPath,
      ),
      'Failed to download ${entry.name}.',
    );
    return localPath;
  }

  @override
  Future<void> upload({
    required String localPath,
    required String deviceDirectory,
  }) {
    final name = extractFileName(localPath);
    return _guard(
      () => rust.uploadIosPath(
        udid: deviceId,
        localPath: localPath,
        devicePath: posixJoin(deviceDirectory, name),
      ),
      'Failed to upload $name.',
    );
  }

  @override
  Future<void> createDirectory({
    required String parentPath,
    required String name,
  }) {
    return _guard(
      () => rust.createIosDirectory(
        udid: deviceId,
        path: posixJoin(parentPath, name),
      ),
      'Failed to create folder "$name".',
    );
  }

  @override
  Future<void> rename({
    required DeviceFileEntry entry,
    required String newName,
  }) {
    return _guard(
      () => rust.renameIosPath(
        udid: deviceId,
        from: entry.path,
        to: posixJoin(posixParent(entry.path), newName),
      ),
      'Failed to rename ${entry.name}.',
    );
  }

  @override
  Future<void> delete(DeviceFileEntry entry) {
    return _guard(
      () => rust.deleteIosPath(udid: deviceId, path: entry.path),
      'Failed to delete ${entry.name}.',
    );
  }

  /// Turns an `IosError` into the [DeviceFileException] the file-manager UI
  /// already knows how to surface.
  Future<T> _guard<T>(Future<T> Function() operation, String fallback) async {
    try {
      return await operation();
    } catch (error) {
      throw DeviceFileException('$fallback ($error)');
    }
  }

  DeviceFileType _typeFromIfmt(String ifmt) => switch (ifmt) {
    'S_IFDIR' => DeviceFileType.directory,
    'S_IFREG' => DeviceFileType.file,
    'S_IFLNK' => DeviceFileType.symlink,
    _ => DeviceFileType.other,
  };
}
