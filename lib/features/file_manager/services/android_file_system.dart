import 'dart:io';

import '../../../services/tools/tool_process_runner.dart';
import '../../../utils/utils.dart';
import '../data/device_file_entry.dart';
import 'device_file_system.dart';

/// `adb`-backed file system for Android devices. Listing uses
/// `adb shell ls -lA`; transfers use `adb pull` / `adb push`; mutations use
/// `adb shell mkdir` / `rm`.
///
/// Browsing starts at `/sdcard` (internal storage, readable on stock devices)
/// but the user can navigate up to the real root `/`; directories that require
/// root simply surface a permission error from the tool.
class AndroidFileSystem extends ToolProcessRunner implements DeviceFileSystem {
  AndroidFileSystem({required this.deviceId, super.executablePath})
    : super(executableName: 'adb');

  final String deviceId;

  @override
  String get storageLabel => 'Internal storage';

  @override
  String get initialPath => '/sdcard';

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
    final result = await runText([
      '-s',
      deviceId,
      'shell',
      'ls',
      '-lA',
      // Trailing slash forces `ls -l` to dereference the final path component,
      // so symlinked directories (e.g. `/sdcard` → `/storage/self/primary`,
      // `/storage/emulated/self` → `…/0`) list their target's contents instead
      // of a single symlink line. Child symlinks still report as symlinks.
      _shellQuote(_ensureTrailingSlash(path)),
    ]);

    final stderr = result.stderr.trim();
    // `ls` exits non-zero on permission/Not-found; surface its own message.
    if (!result.isSuccess && result.stdout.trim().isEmpty) {
      throw DeviceFileException(
        _humanizeListError(
          stderr.isEmpty ? result.combinedOutput : stderr,
          path,
        ),
      );
    }

    final entries = <DeviceFileEntry>[];
    for (final line in result.stdout.split('\n')) {
      final entry = _parseLsLine(line, path);
      if (entry != null) entries.add(entry);
    }
    return entries;
  }

  @override
  Future<String> download({
    required DeviceFileEntry entry,
    required String localDirectory,
  }) async {
    final localPath = '$localDirectory${Platform.pathSeparator}${entry.name}';
    final result = await runText([
      '-s',
      deviceId,
      'pull',
      entry.path,
      localPath,
    ]);
    if (!result.isSuccess) {
      throw DeviceFileException(
        describeCommandFailure('Failed to download ${entry.name}.', result),
      );
    }
    return localPath;
  }

  @override
  Future<void> upload({
    required String localPath,
    required String deviceDirectory,
  }) async {
    final result = await runText([
      '-s',
      deviceId,
      'push',
      localPath,
      _ensureTrailingSlash(deviceDirectory),
    ]);
    if (!result.isSuccess) {
      throw DeviceFileException(
        describeCommandFailure(
          'Failed to upload ${extractFileName(localPath)}.',
          result,
        ),
      );
    }
  }

  @override
  Future<void> createDirectory({
    required String parentPath,
    required String name,
  }) async {
    final target = posixJoin(parentPath, name);
    final result = await runText([
      '-s',
      deviceId,
      'shell',
      'mkdir',
      _shellQuote(target),
    ]);
    if (!result.isSuccess) {
      throw DeviceFileException(
        describeCommandFailure('Failed to create folder "$name".', result),
      );
    }
  }

  @override
  Future<void> rename({
    required DeviceFileEntry entry,
    required String newName,
  }) async {
    final target = posixJoin(posixParent(entry.path), newName);
    final result = await runText([
      '-s',
      deviceId,
      'shell',
      'mv',
      _shellQuote(entry.path),
      _shellQuote(target),
    ]);
    if (!result.isSuccess) {
      throw DeviceFileException(
        describeCommandFailure('Failed to rename ${entry.name}.', result),
      );
    }
  }

  @override
  Future<void> delete(DeviceFileEntry entry) async {
    final result = await runText([
      '-s',
      deviceId,
      'shell',
      'rm',
      entry.isDirectory ? '-rf' : '-f',
      _shellQuote(entry.path),
    ]);
    if (!result.isSuccess) {
      throw DeviceFileException(
        describeCommandFailure('Failed to delete ${entry.name}.', result),
      );
    }
  }

  // ── Parsing ───────────────────────────────────────────────────────────────

  /// Matches a toybox `ls -l` row:
  /// `mode links owner group size  YYYY-MM-DD HH:MM[:SS] name`.
  /// The size group is non-greedy so device files (`1, 3`) still parse.
  static final RegExp _lsLine = RegExp(
    r'^([dlbcps\-][rwxsStT\-]{9}[+.@]?)\s+'
    r'(\d+)\s+(\S+)\s+(\S+)\s+'
    r'(.+?)\s+'
    r'(\d{4}-\d{2}-\d{2})\s+(\d{2}:\d{2}(?::\d{2})?)\s+'
    r'(.*)$',
  );

  DeviceFileEntry? _parseLsLine(String rawLine, String parentPath) {
    final line = rawLine.trimRight();
    if (line.isEmpty || line.startsWith('total ')) return null;

    final match = _lsLine.firstMatch(line);
    if (match == null) return null;

    final mode = match.group(1)!;
    final owner = match.group(3);
    final group = match.group(4);
    final sizeToken = match.group(5)!.trim();
    final date = match.group(6)!;
    final time = match.group(7)!;
    var name = match.group(8)!;

    final type = _typeFromMode(mode[0]);

    String? linkTarget;
    if (type == DeviceFileType.symlink) {
      final arrow = name.indexOf(' -> ');
      if (arrow != -1) {
        linkTarget = name.substring(arrow + 4);
        name = name.substring(0, arrow);
      }
    }
    if (name.isEmpty || name == '.' || name == '..') return null;

    return DeviceFileEntry(
      name: name,
      path: posixJoin(parentPath, name),
      type: type,
      sizeBytes: sizeToken.contains(',') ? null : int.tryParse(sizeToken),
      modified: _parseDateTime(date, time),
      permissions: mode,
      owner: owner,
      group: group,
      linkTarget: linkTarget,
    );
  }

  DeviceFileType _typeFromMode(String first) => switch (first) {
    'd' => DeviceFileType.directory,
    'l' => DeviceFileType.symlink,
    '-' => DeviceFileType.file,
    _ => DeviceFileType.other,
  };

  DateTime? _parseDateTime(String date, String time) {
    final withSeconds = time.length == 5 ? '$time:00' : time;
    return DateTime.tryParse('${date}T$withSeconds');
  }

  String _humanizeListError(String raw, String path) {
    final lower = raw.toLowerCase();
    if (lower.contains('permission denied')) {
      return 'Permission denied for "$path".';
    }
    if (lower.contains('no such file')) {
      return '"$path" does not exist on the device.';
    }
    if (lower.contains('not a directory')) {
      return '"$path" is not a directory.';
    }
    return raw.isEmpty ? 'Failed to list "$path".' : raw;
  }

  /// Single-quotes a path for the on-device shell, escaping embedded quotes so
  /// names with spaces or shell metacharacters list correctly.
  String _shellQuote(String value) {
    return "'${value.replaceAll("'", r"'\''")}'";
  }

  String _ensureTrailingSlash(String path) =>
      path.endsWith('/') ? path : '$path/';
}
