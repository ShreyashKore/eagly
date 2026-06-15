import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../services/tools/tool_process_runner.dart';
import '../../../utils/utils.dart';
import '../data/device_file_entry.dart';
import 'device_file_system.dart';

/// `afcclient`-backed file system for iOS devices.
///
/// `afcclient` is a stdin REPL (commands: `ls`, `info`, `get`, `put`, `mkdir`,
/// `rm`, …) operating on the device's AFC "media" sandbox — the same
/// user-visible area Finder exposes (DCIM, Downloads, Books, …). We drive it by
/// feeding a short command script on stdin and parsing stdout.
///
/// Listing is two passes: `ls <dir>` for names, then a single batched `info`
/// session for attributes (size, kind, modified time). Output is de-noised by
/// stripping ANSI colour codes and the `afc:… >` prompt, and `info` blocks are
/// split on their leading `st_size:` key so parsing is robust regardless of
/// whether the prompt lands on stdout or stderr.
///
/// Requires `libimobiledevice`'s `afcclient` on PATH (or bundled) and a paired,
/// trusted device; otherwise operations surface the tool's own error.
class IosFileSystem extends ToolProcessRunner implements DeviceFileSystem {
  IosFileSystem({required this.deviceId, super.executablePath})
    : super(executableName: 'afcclient');

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
    final lsSegments = _commandSegments(await _runAfc(['ls ${_afcArg(path)}']));
    final names = _parseNames(lsSegments.isEmpty ? '' : lsSegments.first, path);
    if (names.isEmpty) return const [];

    // One batched session, then one segment per `info` (aligned to [names]).
    final infoSegments = _commandSegments(
      await _runAfc([
        for (final name in names) 'info ${_afcArg(posixJoin(path, name))}',
      ]),
    );

    final entries = <DeviceFileEntry>[];
    for (var i = 0; i < names.length; i++) {
      final segment = i < infoSegments.length ? infoSegments[i] : '';
      entries.add(_buildEntry(names[i], path, _parseInfo(segment)));
    }
    return entries;
  }

  @override
  Future<String> download({
    required DeviceFileEntry entry,
    required String localDirectory,
  }) async {
    final localPath = '$localDirectory${Platform.pathSeparator}${entry.name}';
    final output = await _runAfc([
      'get -rf ${_afcArg(entry.path)} ${_afcArg(localPath)}',
    ]);
    _throwIfAfcError(output, 'Failed to download ${entry.name}.');
    return localPath;
  }

  @override
  Future<void> upload({
    required String localPath,
    required String deviceDirectory,
  }) async {
    final target = posixJoin(deviceDirectory, extractFileName(localPath));
    final output = await _runAfc([
      'put -rf ${_afcArg(localPath)} ${_afcArg(target)}',
    ]);
    _throwIfAfcError(output, 'Failed to upload ${extractFileName(localPath)}.');
  }

  @override
  Future<void> createDirectory({
    required String parentPath,
    required String name,
  }) async {
    final output = await _runAfc([
      'mkdir ${_afcArg(posixJoin(parentPath, name))}',
    ]);
    _throwIfAfcError(output, 'Failed to create folder "$name".');
  }

  @override
  Future<void> rename({
    required DeviceFileEntry entry,
    required String newName,
  }) async {
    final target = posixJoin(posixParent(entry.path), newName);
    final output = await _runAfc([
      'mv ${_afcArg(entry.path)} ${_afcArg(target)}',
    ]);
    _throwIfAfcError(output, 'Failed to rename ${entry.name}.');
  }

  @override
  Future<void> delete(DeviceFileEntry entry) async {
    // `rm` asks "Continue? [y/N]" for non-empty paths; feed a 'y' so the delete
    // isn't silently aborted (a stray 'y' is a harmless no-op otherwise).
    final output = await _runAfc(['rm ${_afcArg(entry.path)}', 'y']);
    _throwIfAfcError(output, 'Failed to delete ${entry.name}.');
  }

  // ── REPL plumbing ───────────────────────────────────────────────────────

  /// Runs [commands] in one `afcclient` session and returns its output with
  /// ANSI colour codes stripped (the REPL prompt is kept — it delimits commands;
  /// see [_commandSegments]). afcclient writes everything to stdout.
  Future<String> _runAfc(List<String> commands) async {
    final Process process;
    try {
      process = await startProcess(['-u', deviceId]);
    } on ProcessException catch (error) {
      throw DeviceFileException(
        'Could not run afcclient (is libimobiledevice installed?): '
        '${describeError(error)}',
      );
    }

    final stdoutFuture = process.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .join();
    final stderrFuture = process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .join();

    for (final command in commands) {
      process.stdin.writeln(command);
    }
    process.stdin.writeln('quit');
    try {
      await process.stdin.flush();
      await process.stdin.close();
    } catch (_) {
      // Process may have exited early (e.g. device not trusted).
    }

    final combined = '${await stdoutFuture}${await stderrFuture}';
    await process.exitCode;
    return combined.replaceAll(_ansi, '');
  }

  /// Splits ANSI-stripped REPL [output] into one segment per issued command.
  /// The REPL prints its prompt *before* reading each command, so the prompt is
  /// a reliable delimiter: segment `i` is the output of command `i`. This keeps
  /// name↔attribute alignment even when an individual `info` fails.
  List<String> _commandSegments(String output) {
    final parts = output.split(_prompt);
    return parts.length <= 1 ? const [] : parts.sublist(1);
  }

  List<String> _parseNames(String segment, String path) {
    if (_looksLikeAfcError(segment)) {
      throw DeviceFileException(_extractAfcError(segment, 'list "$path"'));
    }
    final names = <String>[];
    for (final rawLine in segment.split('\n')) {
      final name = rawLine.trim();
      if (name.isEmpty || name == '.' || name == '..') continue;
      names.add(name);
    }
    return names;
  }

  /// Parses one `info` command's output. afcclient prints each attribute as
  /// `key value` (space-separated, one per line), e.g. `st_ifmt S_IFDIR`.
  Map<String, String> _parseInfo(String segment) {
    final attributes = <String, String>{};
    for (final match in _infoAttribute.allMatches(segment)) {
      attributes[match.group(1)!] = match.group(2)!;
    }
    return attributes;
  }

  DeviceFileEntry _buildEntry(
    String name,
    String parentPath,
    Map<String, String> attributes,
  ) {
    final type = _typeFromIfmt(attributes['st_ifmt']);
    final size = int.tryParse(attributes['st_size'] ?? '');
    return DeviceFileEntry(
      name: name,
      path: posixJoin(parentPath, name),
      type: type,
      sizeBytes: type == DeviceFileType.directory ? null : size,
      modified: _parseNanoseconds(attributes['st_mtime']),
      linkTarget: attributes['LinkTarget'],
    );
  }

  DeviceFileType _typeFromIfmt(String? ifmt) => switch (ifmt) {
    'S_IFDIR' => DeviceFileType.directory,
    'S_IFREG' => DeviceFileType.file,
    'S_IFLNK' => DeviceFileType.symlink,
    null => DeviceFileType.other,
    _ => DeviceFileType.other,
  };

  /// `st_mtime` is reported in nanoseconds since the Unix epoch.
  DateTime? _parseNanoseconds(String? raw) {
    final nanos = int.tryParse(raw ?? '');
    if (nanos == null || nanos == 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(nanos ~/ 1000000);
  }

  void _throwIfAfcError(String output, String fallback) {
    if (_looksLikeAfcError(output)) {
      throw DeviceFileException(_extractAfcError(output, fallback));
    }
  }

  /// afcclient reports failures as lines beginning `Error:` / `ERROR:`, so we
  /// match on the colon to avoid false positives from file names.
  bool _looksLikeAfcError(String output) =>
      output.toLowerCase().contains('error:');

  String _extractAfcError(String output, String fallback) {
    for (final rawLine in output.split('\n')) {
      final line = rawLine.trim();
      if (line.toLowerCase().contains('error:')) return line;
    }
    return fallback;
  }

  /// Quotes a REPL argument if it contains whitespace.
  String _afcArg(String value) {
    if (!value.contains(RegExp(r'\s'))) return value;
    return '"${value.replaceAll('"', r'\"')}"';
  }

  static final RegExp _ansi = RegExp(r'\x1B\[[0-9;]*m');
  static final RegExp _prompt = RegExp(r'afc:[^\n>]*>\s?');
  static final RegExp _infoAttribute = RegExp(r'(st_\w+|LinkTarget)\s+(\S+)');
}
