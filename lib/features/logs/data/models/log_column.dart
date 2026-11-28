enum LogColumn(
  final String label,
  final double defaultWidth,
  final double maxWidth,
) {
  // Wide enough for `HH:mm:ss.SSS` and the header's date: rows show the
  // time of day only (LogRow._timestampCell).
  timestamp('Timestamp', 112.0, 250.0),
  pid('Package', 150.0, 200.0),
  tid('PID/TID', 65.0, 100.0),
  level('Level', 65.0, 100.0),
  tag('Tag', 150.0, 300.0),
  message('Message', 0.0, 0.0); // expands to fill remaining space

  static const double minWidth = 30.0;

  bool get isExpandable => this == message;

  String labelFor({bool isIos = false}) => switch (this) {
    LogColumn.pid => isIos ? 'Process' : 'Package',
    LogColumn.tag => isIos ? 'Category' : 'Tag',
    _ => label,
  };
}
