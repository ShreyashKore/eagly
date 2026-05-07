class LogEntryIdGenerator {
  LogEntryIdGenerator({int initialValue = 0}) : _nextValue = initialValue;

  static final LogEntryIdGenerator instance = LogEntryIdGenerator();

  int _nextValue;

  int next() => _nextValue++;
}
