/// The kind of a file-system entry on a device, derived from the leading mode
/// character (`adb shell ls -l`) or the `st_ifmt` attribute (`afcclient info`).
enum DeviceFileType { directory, file, symlink, other }

/// A single entry in a device directory listing, carrying every attribute the
/// underlying tool exposes (size, modified time, POSIX mode, owner/group and –
/// for symlinks – the link target). The platform-specific file systems parse
/// their tool output into this shared shape so the UI never has to care whether
/// it is talking to `adb` or `afcclient`.
class DeviceFileEntry {
  const DeviceFileEntry({
    required this.name,
    required this.path,
    required this.type,
    this.sizeBytes,
    this.modified,
    this.permissions,
    this.owner,
    this.group,
    this.linkTarget,
  });

  /// The entry's base name (no directory component).
  final String name;

  /// The absolute POSIX path of the entry on the device.
  final String path;

  final DeviceFileType type;

  /// File size in bytes. `null` for directories, special files, or when the
  /// tool did not report a parseable size.
  final int? sizeBytes;

  /// Last-modified time in the device's local time zone, when available.
  final DateTime? modified;

  /// POSIX permission string (e.g. `drwxr-xr-x`), when available.
  final String? permissions;

  final String? owner;
  final String? group;

  /// For [DeviceFileType.symlink], the raw link target (`name -> target`).
  final String? linkTarget;

  bool get isDirectory => type == DeviceFileType.directory;
  bool get isSymlink => type == DeviceFileType.symlink;
  bool get isFile => type == DeviceFileType.file;

  /// Whether tapping this entry should attempt to navigate into it. Symlinks
  /// are optimistically treated as navigable; the controller surfaces an error
  /// if the target turns out not to be a directory.
  bool get isNavigable => isDirectory || isSymlink;

  /// A short label describing the entry kind, shown in the details column.
  String get typeLabel => switch (type) {
    DeviceFileType.directory => 'Folder',
    DeviceFileType.symlink => 'Link',
    DeviceFileType.file => 'File',
    DeviceFileType.other => 'Special',
  };

  DeviceFileEntry copyWith({
    DeviceFileType? type,
    int? sizeBytes,
    DateTime? modified,
  }) {
    return DeviceFileEntry(
      name: name,
      path: path,
      type: type ?? this.type,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      modified: modified ?? this.modified,
      permissions: permissions,
      owner: owner,
      group: group,
      linkTarget: linkTarget,
    );
  }

  @override
  String toString() => 'DeviceFileEntry($type $path)';
}
