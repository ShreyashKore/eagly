import '../../../../data/device.dart';
import '../../data/models/log_entry.dart';

/// Identifies a supported log file format.
enum LogFormatId {
  androidLogcat('Android Logcat JSON', ['json', 'logcat']);

  const LogFormatId(this.displayName, this.fileExtensions);

  /// Human-readable label shown in UI pickers and menus.
  final String displayName;

  /// Allowed file extensions for this format (without the leading dot).
  final List<String> fileExtensions;
}

/// Result of serialising a list of [LogEntry] objects into bytes / a string.
class LogFormatExportResult {
  const LogFormatExportResult({
    required this.content,
    required this.suggestedFileName,
  });

  /// The serialised representation ready to be written to disk.
  final String content;

  /// A filename suggestion (including extension) for save dialogs.
  final String suggestedFileName;
}

/// Result of parsing a file's content into [LogEntry] objects.
class LogFormatParseResult {
  const LogFormatParseResult({required this.logs});

  final List<LogEntry> logs;
}

/// Base interface every log-file format must implement.
///
/// A [LogFormat] is a pure, stateless transformation layer between a
/// list of [LogEntry] objects and a serialised file representation.
/// It has no knowledge of file-pickers, preferences, or UI.
///
/// Implement this class to add support for a new file format
/// (e.g. plain text, CSV, iOS syslog JSON, …).
abstract class LogFormat {
  const LogFormat();

  /// Stable identifier for this format.
  LogFormatId get id;

  /// Whether a file at [path] / with [mimeType] could belong to this format.
  ///
  /// Used during import to auto-detect the format when none is specified.
  /// Both [path] and [mimeType] may be null; implementations must handle that.
  bool canParse({String? path, String? mimeType}) {
    if (path == null) return false;
    final ext = path.split('.').last.toLowerCase();
    return id.fileExtensions.contains(ext);
  }

  /// Serialise [entries] (from [device] context) into a string ready to write.
  LogFormatExportResult export(List<LogEntry> entries, {Device? device});

  /// Parse [content] and return the decoded [LogEntry] list.
  ///
  /// Throws a [FormatException] when the content is structurally invalid.
  LogFormatParseResult parse(String content);
}
