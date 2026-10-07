import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// Persistent, device-independent cache of extracted Android launcher icons.
///
/// Icons are stored as one file per package name under the application-support
/// directory, so the cache survives Eagly restarts and is shared across every
/// device session: a package icon pulled from one device is reused for the same
/// package on another, until a fresh fetch replaces it.
///
/// Purely cosmetic — every operation is best-effort and never throws, so a
/// missing directory or a corrupt file can't disturb the Apps feature itself.
class AppIconCache {
  AppIconCache._();

  /// Process-wide instance used by [AppsController]. Shared so controllers for
  /// different devices read the same in-memory copy.
  static final AppIconCache instance = AppIconCache._();

  /// Soft cap on the number of icon files retained on disk. Eviction is
  /// best-effort (oldest-by-mtime first) and triggered lazily.
  static const int maxEntries = 2000;

  static const String _subdir = 'app_icons';

  Directory? _dir;
  Future<Directory>? _dirFuture;

  /// Icons already loaded this process, keyed by package name. `null` means
  /// "already checked, nothing cached".
  final Map<String, Uint8List?> _memory = {};

  int _storesSinceTrim = 0;

  /// Loads a cached icon from disk (unless already in memory). Returns null
  /// when there is none, or when reading fails for any reason.
  Future<Uint8List?> load(String packageName) async {
    if (_memory.containsKey(packageName)) return _memory[packageName];
    try {
      final file = await _fileFor(packageName);
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        _memory[packageName] = bytes;
        return bytes;
      }
    } catch (_) {
      // Fall through to "no cached icon".
    }
    _memory[packageName] = null;
    return null;
  }

  /// Stores [bytes] for [packageName] in memory and on disk. Never throws.
  Future<void> store(String packageName, Uint8List bytes) async {
    _memory[packageName] = bytes;
    try {
      final file = await _fileFor(packageName);
      await file.writeAsBytes(bytes, flush: true);
      if (++_storesSinceTrim >= 50) {
        _storesSinceTrim = 0;
        unawaited(_trimToLimit());
      }
    } catch (_) {
      // The in-memory entry is enough for this session.
    }
  }

  Future<File> _fileFor(String packageName) async {
    final dir = await _ensureDir();
    final safe = packageName.replaceAll(RegExp(r'[\\/]'), '_');
    return File('${dir.path}${Platform.pathSeparator}$safe.png');
  }

  Future<Directory> _ensureDir() {
    final existing = _dir;
    if (existing != null) return Future.value(existing);
    return _dirFuture ??= _createDir();
  }

  Future<Directory> _createDir() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory('${support.path}${Platform.pathSeparator}$_subdir');
    await dir.create(recursive: true);
    _dir = dir;
    return dir;
  }

  /// Deletes the oldest icon files beyond [maxEntries]. Best-effort; any IO
  /// error simply aborts the sweep.
  Future<void> _trimToLimit() async {
    try {
      final dir = await _ensureDir();
      final files = <({File file, DateTime modified})>[];
      for (final entity in await dir.list().toList()) {
        if (entity is! File) continue;
        try {
          files.add((file: entity, modified: (await entity.stat()).modified));
        } catch (_) {}
      }
      if (files.length <= maxEntries) return;
      files.sort((a, b) => a.modified.compareTo(b.modified));
      final toDelete = files.length - maxEntries;
      for (final entry in files.take(toDelete)) {
        try {
          await entry.file.delete();
        } catch (_) {}
      }
    } catch (_) {}
  }
}
