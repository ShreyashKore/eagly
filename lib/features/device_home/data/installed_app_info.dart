class const InstalledAppInfo({
  required final String packageName,
  final String? appName,
  final DateTime? installTime,
}) {
  String get displayName => appName ?? packageName;
}
