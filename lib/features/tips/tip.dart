import 'package:flutter/material.dart';

/// A single feature tip surfaced in the header tips panel.
///
/// [title] is the short, one-line headline shown inline in the header;
/// [detail] is the longer explanation revealed in the tap-through dialog.
@immutable
class const Tip({
  /// Stable identifier (handy for tests and analytics).
  required final String id,

  /// Small leading glyph shown both inline and in the detail dialog.
  required final IconData icon,

  /// Short headline shown inline. Keep it to a single terse line.
  required final String title,

  /// Longer explanation shown in the detail dialog.
  required final String detail,

  /// Optional "how to get there" hint, emphasized in the detail dialog.
  final String? actionHint,

  /// Optional short looping clip of the feature in use, shown above [detail].
  final TipMedia? media,
});

/// An animated WebP clip hosted outside the app (see `scripts/tips_media/`).
///
/// Only the file name lives here; [url] joins it to [baseUrl], so every clip
/// moves together when the media is re-published under a new version.
@immutable
class const TipMedia(
  /// File name under [baseUrl], e.g. `hide-columns.webp`.
  final String fileName, {

  /// Width ÷ height of the clip. The dialog reserves this box while the clip
  /// loads, so the text below it doesn't jump.
  required final double aspectRatio,
}) {
  /// Where the clips are served from. A tagged jsDelivr URL never changes, so
  /// a re-recorded clip ships as a new tag without breaking older builds.
  ///
  /// Override with `--dart-define=EAGLY_TIPS_MEDIA_BASE=http://localhost:8000/`
  /// to preview clips before publishing them.
  static const baseUrl = String.fromEnvironment(
    'EAGLY_TIPS_MEDIA_BASE',
    defaultValue:
        'https://cdn.jsdelivr.net/gh/ShreyashKore/eagly-tips-media@v1/',
  );

  String get url => '$baseUrl$fileName';
}
