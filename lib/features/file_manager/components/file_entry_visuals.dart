import 'package:flutter/material.dart';

import '../../../utils/utils.dart';
import '../data/device_file_entry.dart';

/// Icon, colour and text formatting helpers shared by the list and grid views
/// so an entry renders identically in both.
class FileEntryVisuals {
  const FileEntryVisuals._();

  static IconData iconFor(DeviceFileEntry entry) {
    if (entry.isDirectory) return Icons.folder_rounded;
    if (entry.isSymlink) return Icons.link_rounded;
    if (entry.type == DeviceFileType.other) return Icons.dataset_linked_outlined;

    return switch (_extension(entry.name)) {
      'png' || 'jpg' || 'jpeg' || 'gif' || 'webp' || 'bmp' || 'heic' || 'svg' =>
        Icons.image_outlined,
      'mp4' || 'mov' || 'mkv' || 'avi' || 'webm' || 'm4v' =>
        Icons.movie_outlined,
      'mp3' || 'wav' || 'aac' || 'flac' || 'ogg' || 'm4a' =>
        Icons.audiotrack_outlined,
      'zip' || 'rar' || '7z' || 'tar' || 'gz' || 'xz' || 'bz2' =>
        Icons.folder_zip_outlined,
      'pdf' => Icons.picture_as_pdf_outlined,
      'apk' || 'ipa' || 'aab' => Icons.android_outlined,
      'json' || 'xml' || 'yaml' || 'yml' || 'html' || 'js' || 'dart' || 'kt' ||
          'java' || 'swift' || 'c' || 'cpp' || 'py' || 'sh' =>
        Icons.code_outlined,
      'txt' || 'log' || 'md' || 'csv' => Icons.description_outlined,
      'db' || 'sqlite' || 'sql' => Icons.storage_outlined,
      _ => Icons.insert_drive_file_outlined,
    };
  }

  static Color colorFor(DeviceFileEntry entry, ColorScheme scheme) {
    if (entry.isDirectory) return scheme.primary;
    if (entry.isSymlink) return scheme.tertiary;
    return scheme.onSurfaceVariant;
  }

  static String formatSize(DeviceFileEntry entry) {
    if (entry.isDirectory) return '—';
    final size = entry.sizeBytes;
    return size == null ? '—' : formatBytes(size);
  }

  static String formatModified(DateTime? modified) {
    if (modified == null) return '—';
    final local = modified.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  static String _extension(String name) {
    final dot = name.lastIndexOf('.');
    if (dot <= 0 || dot == name.length - 1) return '';
    return name.substring(dot + 1).toLowerCase();
  }
}
