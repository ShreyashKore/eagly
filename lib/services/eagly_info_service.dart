import 'package:package_info_plus/package_info_plus.dart';

class EaglyInfoService {
  static PackageInfo? _packageInfo;

  static Future<void> init() async {
    _packageInfo = await PackageInfo.fromPlatform();
  }

  static String get appVersion {
    final packageInfo = _packageInfo;
    if (packageInfo == null) return 'Unknown';
    return packageInfo.buildNumber.isEmpty
        ? packageInfo.version
        : '${packageInfo.version}+${packageInfo.buildNumber}';
  }

  /// Plain semantic version (no `+build` suffix), e.g. `1.1.5`. Used for update
  /// comparisons where a bare semver is required. Falls back to `0.0.0` so a
  /// missing package info never blocks the update check from running.
  static String get versionName => _packageInfo?.version ?? '0.0.0';
}
