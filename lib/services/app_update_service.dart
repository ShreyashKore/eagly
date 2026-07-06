import 'dart:convert';
import 'dart:io';

import 'package:eagly/constants/app_constants.dart';
import 'package:http/http.dart' as http;

/// GitHub-releases-backed update source consumed by `UpdatWidget`.
///
/// It reads the latest published release from the GitHub API and maps it onto
/// the stable-named artifacts produced by the release workflow
/// (`.github/workflows/release.yml`): `eagly-macos.dmg`,
/// `eagly-windows-setup.exe`, and `eagly-linux.deb`. Because those names are
/// identical on every release, the download URL only needs the tag.
class AppUpdateService {
  const AppUpdateService._();

  /// Auto-update only makes sense on the packaged desktop builds we ship.
  static bool get isSupported =>
      Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  static const _latestReleaseApi =
      'https://api.github.com/repos/${AppConstants.repoOwner}/'
      '${AppConstants.repoName}/releases/latest';

  static const _headers = {
    'Accept': 'application/vnd.github+json',
    // GitHub rejects API requests that omit a User-Agent.
    'User-Agent': '${AppConstants.repoName}-app',
  };

  /// Latest published release as a bare semantic version (leading `v` stripped),
  /// e.g. `1.1.6`. `updat` parses this with `pub_semver`, which rejects a `v`
  /// prefix. Returns `null` when the payload can't be understood so the widget
  /// stays quiet instead of surfacing an error.
  static Future<String?> getLatestVersion() async {
    final res = await http.get(Uri.parse(_latestReleaseApi), headers: _headers);
    if (res.statusCode != 200) {
      throw Exception('GitHub release lookup failed (${res.statusCode})');
    }
    final tag = (jsonDecode(res.body) as Map<String, dynamic>)['tag_name'];
    if (tag is! String || tag.isEmpty) return null;
    return _stripV(tag);
  }

  /// Release notes body of the latest release, shown in the update dialog.
  static Future<String?> getChangelog(
    String latestVersion,
    String appVersion,
  ) async {
    final res = await http.get(Uri.parse(_latestReleaseApi), headers: _headers);
    if (res.statusCode != 200) return null;
    final body = (jsonDecode(res.body) as Map<String, dynamic>)['body'];
    return body is String && body.trim().isNotEmpty ? body : null;
  }

  /// Download URL of this platform's installer for [version] — the bare semver
  /// handed back by [getLatestVersion]. Release tags follow the `v<semver>`
  /// convention (`release.yml` triggers on `v*`), so the tag is `v$version`.
  static Future<String> getBinaryUrl(String? version) async {
    return '${AppConstants.repoUrl}/releases/download/v$version/$_assetName';
  }

  static String get _assetName {
    if (Platform.isMacOS) return 'eagly-macos.dmg';
    if (Platform.isWindows) return 'eagly-windows-setup.exe';
    return 'eagly-linux.deb';
  }

  static String _stripV(String tag) =>
      tag.startsWith('v') || tag.startsWith('V') ? tag.substring(1) : tag;
}
