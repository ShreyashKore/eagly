enum LogFilterViewMode {
  classic,
  inline;

  String get label => switch (this) {
	LogFilterViewMode.classic => 'Classic',
	LogFilterViewMode.inline => 'Inline',
  };

  String get description => switch (this) {
	LogFilterViewMode.classic =>
	  'Separate fields for level, package, tag, and message.',
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

