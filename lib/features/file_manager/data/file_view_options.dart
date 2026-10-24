import 'device_file_entry.dart';

enum FileManagerViewMode {
  list,
  grid;

  static FileManagerViewMode fromStored(String? stored) =>
      values.firstWhere((mode) => mode.name == stored, orElse: () => list);
}

enum FileSortField {
  name('Name'),
  kind('Kind'),
  size('Size'),
  modified('Date modified');

  const FileSortField(this.label);

  final String label;

  /// Name and Kind read A→Z; Size and Date start with the biggest / newest,
  /// which is what someone sorting by them is usually looking for.
  bool get defaultAscending =>
      this == FileSortField.name || this == FileSortField.kind;

  static FileSortField fromStored(String? stored) => values.firstWhere(
    (field) => field.name == stored,
    orElse: () => FileSortField.name,
  );
}

enum FileGrouping {
  none('None'),
  kind('Kind'),
  modified('Date modified');

  const FileGrouping(this.label);

  final String label;

  static FileGrouping fromStored(String? stored) =>
      values.firstWhere((g) => g.name == stored, orElse: () => none);
}

/// What an entry is, from its type and extension. Drives the icon, the Kind
/// sort and the Kind groups, so all three agree. Declared in group order.
enum FileKind {
  folder('Folders'),
  image('Images'),
  video('Videos'),
  audio('Audio'),
  document('Documents'),
  code('Code'),
  archive('Archives'),
  package('App packages'),
  database('Databases'),
  other('Other');

  const FileKind(this.groupLabel);

  final String groupLabel;

  static FileKind of(DeviceFileEntry entry) {
    // Symlinks navigate like folders, so they group and sort with them.
    if (entry.isNavigable) return folder;
    if (entry.type == DeviceFileType.other) return other;
    return switch (fileExtension(entry.name)) {
      'png' ||
      'jpg' ||
      'jpeg' ||
      'gif' ||
      'webp' ||
      'bmp' ||
      'heic' ||
      'svg' => image,
      'mp4' || 'mov' || 'mkv' || 'avi' || 'webm' || 'm4v' => video,
      'mp3' || 'wav' || 'aac' || 'flac' || 'ogg' || 'm4a' => audio,
      'zip' || 'rar' || '7z' || 'tar' || 'gz' || 'xz' || 'bz2' => archive,
      'pdf' || 'txt' || 'log' || 'md' || 'csv' => document,
      'apk' || 'ipa' || 'aab' => package,
      'json' ||
      'xml' ||
      'yaml' ||
      'yml' ||
      'html' ||
      'js' ||
      'dart' ||
      'kt' ||
      'java' ||
      'swift' ||
      'c' ||
      'cpp' ||
      'py' ||
      'sh' => code,
      'db' || 'sqlite' || 'sql' => database,
      _ => other,
    };
  }
}

/// The lower-cased extension of [name] without the dot, or `''` when it has
/// none (a leading dot alone — `.nomedia` — is a hidden file, not one).
String fileExtension(String name) {
  final dot = name.lastIndexOf('.');
  if (dot <= 0 || dot == name.length - 1) return '';
  return name.substring(dot + 1).toLowerCase();
}

/// One section of a grouped listing. [key] is stable across reloads so a
/// collapsed group stays collapsed; [label] is empty for the single group of
/// an ungrouped listing.
class const FileGroup({
  required final String key,
  required final String label,
  required final List<DeviceFileEntry> entries,
});

/// Splits already-sorted [entries] into [grouping]'s sections, keeping their
/// order within each. Empty sections are left out.
List<FileGroup> groupFileEntries(
  List<DeviceFileEntry> entries,
  FileGrouping grouping, {
  required DateTime now,
}) {
  switch (grouping) {
    case FileGrouping.none:
      return [FileGroup(key: 'all', label: '', entries: entries)];
    case FileGrouping.kind:
      final byKind = <FileKind, List<DeviceFileEntry>>{};
      for (final entry in entries) {
        (byKind[FileKind.of(entry)] ??= []).add(entry);
      }
      return [
        for (final kind in FileKind.values)
          if (byKind[kind] case final members?)
            FileGroup(
              key: 'kind:${kind.name}',
              label: kind.groupLabel,
              entries: members,
            ),
      ];
    case FileGrouping.modified:
      final byAge = <_Age, List<DeviceFileEntry>>{};
      for (final entry in entries) {
        (byAge[_Age.of(entry.modified, now)] ??= []).add(entry);
      }
      return [
        for (final age in _Age.values)
          if (byAge[age] case final members?)
            FileGroup(
              key: 'modified:${age.name}',
              label: age.label,
              entries: members,
            ),
      ];
  }
}

/// Date-modified buckets, newest first — the order Finder and Explorer use.
enum _Age {
  today('Today'),
  yesterday('Yesterday'),
  week('Previous 7 days'),
  month('Previous 30 days'),
  year('Earlier this year'),
  older('Older'),
  unknown('Unknown date');

  const _Age(this.label);

  final String label;

  static _Age of(DateTime? modified, DateTime now) {
    if (modified == null) return unknown;
    final local = modified.toLocal();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(local.year, local.month, local.day);
    final days = today.difference(day).inDays;
    // A clock skewed ahead of the desktop's still reads as today.
    if (days <= 0) return _Age.today;
    if (days == 1) return yesterday;
    if (days < 7) return week;
    if (days < 30) return month;
    if (local.year == now.year) return year;
    return older;
  }
}

/// Case-insensitive "natural" order, the one file managers use: runs of
/// digits compare by value, so `IMG_2` sorts before `IMG_10`.
int compareFileNames(String a, String b) {
  final left = a.toLowerCase();
  final right = b.toLowerCase();
  var i = 0;
  var j = 0;
  while (i < left.length && j < right.length) {
    final ca = left.codeUnitAt(i);
    final cb = right.codeUnitAt(j);
    if (_isDigit(ca) && _isDigit(cb)) {
      final startA = i;
      final startB = j;
      while (i < left.length && _isDigit(left.codeUnitAt(i))) {
        i++;
      }
      while (j < right.length && _isDigit(right.codeUnitAt(j))) {
        j++;
      }
      // Compare by value without parsing (runs can outgrow an int): strip
      // leading zeros, then the longer run is bigger, then digit by digit.
      final runA = left.substring(startA, i).replaceFirst(RegExp('^0+'), '');
      final runB = right.substring(startB, j).replaceFirst(RegExp('^0+'), '');
      if (runA.length != runB.length) return runA.length - runB.length;
      final byDigits = runA.compareTo(runB);
      if (byDigits != 0) return byDigits;
      continue;
    }
    if (ca != cb) return ca - cb;
    i++;
    j++;
  }
  final byLength = (left.length - i) - (right.length - j);
  // Names equal but for case still need a fixed order.
  return byLength != 0 ? byLength : a.compareTo(b);
}

bool _isDigit(int codeUnit) => codeUnit >= 0x30 && codeUnit <= 0x39;
