enum LogColumn {
  timestamp('Timestamp', 170.0, 250.0),
  pid('Package', 150.0, 200.0),
  tid('PID/TID', 65.0, 100.0),
  level('Level', 65.0, 100.0),
  tag('Tag', 150.0, 300.0),
  message('Message', 0.0, 0.0); // expands to fill remaining space

  final String label;
  final double defaultWidth;
  final double maxWidth;

  const LogColumn(this.label, this.defaultWidth, this.maxWidth);

  static const double minWidth = 30.0;

  bool get isExpandable => this == message;

  String labelFor({bool isIos = false}) => switch (this) {
    LogColumn.pid => isIos ? 'Process' : 'Package',
    LogColumn.tag => isIos ? 'Category' : 'Tag',
    _ => label,
  };
}
