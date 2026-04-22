class LogUtils {
  /// Convert log level short code to full name
  static String logLevelName(String level) {
    switch (level) {
      case 'E':
        return 'ERROR';
      case 'W':
        return 'WARN';
      case 'I':
        return 'INFO';
      case 'D':
        return 'DEBUG';
      case 'V':
        return 'VERBOSE';
      default:
        return 'UNKNOWN';
    }
  }

  /// Convert full log level name to short code
  static String logLevelFromName(String name) {
    switch (name.toUpperCase()) {
      case 'ERROR':
        return 'E';
      case 'WARN':
        return 'W';
      case 'INFO':
        return 'I';
      case 'DEBUG':
        return 'D';
      case 'VERBOSE':
        return 'V';
      default:
        return 'V';
    }
  }


  /// Define log level hierarchy (lower number = higher priority)
  static const levelHierarchy = {'E': 0, 'W': 1, 'I': 2, 'D': 3, 'V': 4};
}
