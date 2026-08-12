/// One app installed on a device, as shown by the Apps feature. Richer than
/// [InstalledAppInfo] in device_home (which only backs the small "recently
/// installed" list) — this carries everything the app-management UI and its
/// context-menu actions need. Icons are *not* stored here — they're fetched
/// lazily and cached by `AppsController`, keyed by [packageName].
class AppInfo {
  const AppInfo({
    required this.packageName,
    this.appName,
    this.versionName,
    this.versionCode,
    this.isSystemApp = false,
    this.isEnabled = true,
    this.apkPath,
    this.installTime,
    this.updateTime,
  });

  /// Android package name (`com.example.app`) or iOS bundle identifier.
  final String packageName;
  final String? appName;
  final String? versionName;
  final String? versionCode;

  /// True for apps preinstalled by the OS/OEM. Android only — always false
  /// for iOS, whose installer only ever lists user-installed apps.
  final bool isSystemApp;

  /// False when a system app has been disabled (Android only, via
  /// `pm disable`/`pm enable`). Always true on iOS.
  final bool isEnabled;

  /// On-device path to the installed APK (Android only), shown as extra
  /// detail — icon extraction resolves its own path via `pm path` rather
  /// than trusting this one, since `dumpsys`'s `codePath` points at the
  /// split-APK install directory on modern Android, not the base APK file.
  final String? apkPath;
  final DateTime? installTime;
  final DateTime? updateTime;

  String get displayName => appName ?? packageName;
}
