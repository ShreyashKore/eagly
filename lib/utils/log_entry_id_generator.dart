class LogEntryIdGenerator({int initialValue = 0}) {
  this : _nextValue = initialValue;

  static final LogEntryIdGenerator instance = LogEntryIdGenerator();

  int _nextValue;

  int next() => _nextValue++;
}
