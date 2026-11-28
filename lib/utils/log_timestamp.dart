/// A log timestamp split into the parts the viewer draws differently: the
/// date, which the timestamp column shows once in its header rather than on
/// every row; the time of day; and the fraction of a second, which is read
/// least often.
///
/// Concatenating [datePrefix], [time], [fraction] and [suffix] gives back the
/// original string exactly, so whatever is drawn from the parts can still be
/// selected and copied whole.
class const LogTimestampParts._({
  /// The date and the separator after it (`10-18 `, `2026-10-18 `), or empty
  /// for a timestamp with no date.
  required final String datePrefix,

  /// `HH:mm:ss`.
  required final String time,

  /// The fractional seconds with their separator (`.312`), or empty.
  required final String fraction,

  /// Anything after the time, such as a zone offset, or empty.
  required final String suffix,

  /// The year, when the timestamp carries one (iOS and imported logs do,
  /// Android's `logcat -v long` does not).
  final int? year,
  final int? month,
  final int? day,
}) {
  // Android `MM-dd HH:mm:ss.SSS`, iOS and imports `yyyy-MM-dd HH:mm:ss.SSS`,
  // ISO's `T` separator, a bare time of day; a fraction with `.` or `,`.
  static final _pattern = RegExp(
    r'^((?:(\d{4})-)?(\d{1,2})-(\d{1,2})[ T]+)?'
    r'(\d{1,2}:\d{2}:\d{2})([.,]\d+)?(\s*(?:Z|[+-]\d{2}:?\d{2})?)$',
  );

  /// The parts of [timestamp], or null when it isn't in a shape the viewer
  /// knows — the caller then shows it as it is.
  static LogTimestampParts? tryParse(String timestamp) {
    final match = _pattern.firstMatch(timestamp);
    if (match == null) return null;
    final month = int.tryParse(match.group(3) ?? '');
    final day = int.tryParse(match.group(4) ?? '');
    final hasDate = month != null && day != null;
    if (hasDate && (month < 1 || month > 12 || day < 1 || day > 31)) {
      return null;
    }
    return LogTimestampParts._(
      datePrefix: match.group(1) ?? '',
      time: match.group(5)!,
      fraction: match.group(6) ?? '',
      suffix: match.group(7) ?? '',
      year: int.tryParse(match.group(2) ?? ''),
      month: hasDate ? month : null,
      day: hasDate ? day : null,
    );
  }

  bool get hasDate => month != null && day != null;

  static const _monthNames = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  /// `Oct 18`, with the year added (`Oct 18, 2025`) when it is known and not
  /// [currentYear]; null for a timestamp with no date.
  String? dateLabel({int? currentYear}) {
    if (!hasDate) return null;
    final label = '${_monthNames[month! - 1]} $day';
    final y = year;
    if (y == null || y == (currentYear ?? DateTime.now().year)) return label;
    return '$label, $y';
  }
}
