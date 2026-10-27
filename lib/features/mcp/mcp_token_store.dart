import 'dart:ffi';
import 'dart:io';
import 'dart:math';

import 'package:ffi/ffi.dart';
import 'package:path_provider/path_provider.dart';

import '../../services/preferences_service.dart';

/// Keeps the MCP server's bearer token in a file only its owner can read
/// (docs/MCP_SERVER.md §3.3).
///
/// Not in shared_preferences: on Linux that plugin writes
/// `shared_preferences.json` 0644, so under a 0755 home any other account
/// could read the token. On macOS and Linux the file is 0600 from before the
/// token is written to it; on Windows the per-user app support folder is
/// private already.
class McpTokenStore({Future<Directory> Function()? directory}) {
  static const fileName = 'mcp_token';

  final Future<Directory> Function() _directory =
      directory ?? getApplicationSupportDirectory;

  /// The token, made on first use. A token from an older Eagly that kept it
  /// in preferences moves into the file, so configured clients keep working.
  Future<String> load() async {
    final file = await _file();
    final legacy = PreferencesService.legacyMcpToken;
    if (legacy != null && _isToken(legacy)) {
      await _write(file, legacy);
      await PreferencesService.removeLegacyMcpToken();
      return legacy;
    }
    if (legacy != null) await PreferencesService.removeLegacyMcpToken();

    if (await file.exists()) {
      final token = (await file.readAsString()).trim();
      if (_isToken(token)) {
        if (_isTooOpen(await file.stat())) {
          // Written by something else, or copied in: rewrite it 0600.
          await _write(file, token);
        }
        return token;
      }
    }
    return regenerate();
  }

  /// Replaces the token with a new one; clients holding the old one stop
  /// working.
  Future<String> regenerate() async {
    final random = Random.secure();
    final token = [
      for (var i = 0; i < 32; i++)
        random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ].join();
    await _write(await _file(), token);
    return token;
  }

  // ── Private ──────────────────────────────────────────────────────────

  Future<File> _file() async {
    final dir = await _directory();
    await dir.create(recursive: true);
    return File('${dir.path}${Platform.pathSeparator}$fileName');
  }

  static final _tokenPattern = RegExp(r'^[0-9a-f]{64}$');
  static bool _isToken(String value) => _tokenPattern.hasMatch(value);

  /// Whether group or others have any access.
  static bool _isTooOpen(FileStat stat) =>
      !Platform.isWindows && stat.mode & 0x3f != 0;

  /// Tells apart the temp files of writes in flight at once.
  static int _tempCounter = 0;

  /// Writes [token] to a fresh temp file that is 0600 before it holds
  /// anything, then renames it over [target], so the token is never on disk
  /// with wider permissions.
  static Future<void> _write(File target, String token) async {
    final temp = File('${target.path}.$pid.${_tempCounter++}.tmp');
    // Only a crashed run that had the same pid leaves one behind.
    if (await temp.exists()) await temp.delete();
    await temp.create(exclusive: true);
    try {
      if (!Platform.isWindows) _restrictToOwner(temp.path);
      await temp.writeAsString(token, flush: true);
      await temp.rename(target.path);
    } catch (_) {
      if (await temp.exists()) await temp.delete();
      rethrow;
    }
  }

  /// `chmod(path, 0600)` through libc.
  static void _restrictToOwner(String path) {
    final native = path.toNativeUtf8();
    try {
      if (_chmod(native, 0x180) != 0) {
        throw FileSystemException('Could not make the file private', path);
      }
    } finally {
      malloc.free(native);
    }
  }

  static final _chmod = DynamicLibrary.process()
      .lookupFunction<
        Int32 Function(Pointer<Utf8>, Uint32),
        int Function(Pointer<Utf8>, int)
      >('chmod');
}
