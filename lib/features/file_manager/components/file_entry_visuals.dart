import 'package:flutter/material.dart';

import '../../../presentation/components/search_highlight.dart';
import '../../../utils/text_search_pattern.dart';
import '../../../utils/utils.dart';
import '../data/device_file_entry.dart';
import '../data/file_view_options.dart';

/// Icon, colour and text formatting helpers shared by the list and grid views
/// so an entry renders identically in both.
class const FileEntryVisuals._() {
  static IconData iconFor(DeviceFileEntry entry) {
    if (entry.isSymlink) return Icons.link_rounded;
    if (entry.type == DeviceFileType.other) {
      return Icons.dataset_linked_outlined;
    }
    return switch (FileKind.of(entry)) {
      FileKind.folder => Icons.folder_rounded,
      FileKind.image => Icons.image_outlined,
      FileKind.video => Icons.movie_outlined,
      FileKind.audio => Icons.audiotrack_outlined,
      FileKind.archive => Icons.folder_zip_outlined,
      FileKind.document when fileExtension(entry.name) == 'pdf' =>
        Icons.picture_as_pdf_outlined,
      FileKind.document => Icons.description_outlined,
      FileKind.package => Icons.android_outlined,
      FileKind.code => Icons.code_outlined,
      FileKind.database => Icons.storage_outlined,
      FileKind.other => Icons.insert_drive_file_outlined,
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
}

/// Renders an entry's icon. Symlinks use the folder icon with a small link
/// badge in the corner (they navigate like folders), so they read as
/// navigable rather than as an unrelated "link" glyph.
class const FileEntryIcon({
  super.key,
  required final DeviceFileEntry entry,
  required final double size,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (entry.isSymlink) {
      return SizedBox(
        width: size,
        height: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Icon(Icons.folder_rounded, size: size, color: scheme.primary),
            Positioned(
              right: -size * 0.04,
              bottom: -size * 0.04,
              child: Container(
                padding: EdgeInsets.all(size * 0.05),
                decoration: BoxDecoration(
                  color: scheme.surface,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.link_rounded,
                  size: size * 0.46,
                  color: scheme.tertiary,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Icon(
      FileEntryVisuals.iconFor(entry),
      size: size,
      color: FileEntryVisuals.colorFor(entry, scheme),
    );
  }
}

/// An entry's name with the part matching a plain-text [filter] highlighted,
/// so it is clear why a row survived the filter. A glob filter matches the
/// whole name and highlights nothing.
class const FileNameText({
  super.key,
  required final String name,
  required final String filter,
  final TextStyle? style,
  final int maxLines = 1,
  final TextAlign textAlign = TextAlign.start,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final base = style ?? DefaultTextStyle.of(context).style;
    final query = filter.trim().toLowerCase();
    final start = query.isEmpty || query.contains('*') || query.contains('?')
        ? -1
        : name.toLowerCase().indexOf(query);
    return Text.rich(
      TextSpan(
        children: buildSearchHighlightSpans(
          context: context,
          text: name,
          style: base,
          matches: [
            if (start >= 0)
              TextSearchMatch(start: start, end: start + query.length),
          ],
        ),
      ),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      textAlign: textAlign,
    );
  }
}
