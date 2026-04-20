import 'package:package_info_plus/package_info_plus.dart';

class AppInfoService {
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
}
