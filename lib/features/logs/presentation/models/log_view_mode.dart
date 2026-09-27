enum LogFilterViewMode {
  classic,
  inline;

  String get label => switch (this) {
    LogFilterViewMode.classic => 'Classic',
    LogFilterViewMode.inline => 'Inline',
  };

  String get description => switch (this) {
    LogFilterViewMode.classic =>
      'A message field plus point-and-click filters for package, tag, PID, and '
          'age — each can match, match exactly, match a regex, or exclude.',
    LogFilterViewMode.inline =>
      'One Logcat-style field with smart suggestions such as level:error or tag:Auth.',
  };

  static LogFilterViewMode fromStored(String? value) {
    return LogFilterViewMode.values.firstWhere(
      (mode) => mode.name == value,
      orElse: () => LogFilterViewMode.classic,
    );
  }
}
