class InstalledAppInfo {
  const InstalledAppInfo({
    required this.packageName,
    this.appName,
    this.installTime,
  });

  final String packageName;
  final String? appName;
  final DateTime? installTime;

  String get displayName => appName ?? packageName;
}
