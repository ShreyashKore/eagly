import 'package:flutter/material.dart';

/// A single feature tip surfaced in the header tips panel.
///
/// [title] is the short, one-line headline shown inline in the header;
/// [detail] is the longer explanation revealed in the tap-through dialog.
@immutable
class Tip {
  const Tip({
    required this.id,
    required this.icon,
    required this.title,
    required this.detail,
    this.actionHint,
  });

  /// Stable identifier (handy for tests and analytics).
  final String id;

  /// Small leading glyph shown both inline and in the detail dialog.
  final IconData icon;

  /// Short headline shown inline. Keep it to a single terse line.
  final String title;

  /// Longer explanation shown in the detail dialog.
  final String detail;

  /// Optional "how to get there" hint, emphasized in the detail dialog.
  final String? actionHint;
}
