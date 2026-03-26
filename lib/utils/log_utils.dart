import 'package:flutter/material.dart';

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

  /// Get color for log level
  static Color colorForLevel(String level) {
    switch (level) {
      case 'E':
        return Colors.red;
      case 'W':
        return Colors.orange;
      case 'I':
        return Colors.green;
      case 'D':
        return Colors.blue;
      default:
        return Colors.grey[400]!;
    }
  }

  /// Define log level hierarchy (lower number = higher priority)
  static const levelHierarchy = {'E': 0, 'W': 1, 'I': 2, 'D': 3, 'V': 4};
}
