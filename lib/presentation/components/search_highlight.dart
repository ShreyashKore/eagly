import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../../utils/text_search_pattern.dart';

/// Builds inline spans for [text] with every match in [matches] highlighted.
///
/// The match at [currentMatchIndex] (if any) is painted with the "current"
/// highlight color so it stands out from the rest. Returns a single plain span
/// when there are no matches.
List<InlineSpan> buildSearchHighlightSpans({
  required BuildContext context,
  required String text,
  required TextStyle style,
  required List<TextSearchMatch> matches,
  int? currentMatchIndex,
}) {
  if (matches.isEmpty) {
    return [TextSpan(text: text, style: style)];
  }

  final theme = context.eaglyTheme;
  final spans = <InlineSpan>[];
  var start = 0;

  for (var i = 0; i < matches.length; i++) {
    final match = matches[i];
    if (match.start > start) {
      spans.add(
        TextSpan(text: text.substring(start, match.start), style: style),
      );
    }
    final isCurrent = i == currentMatchIndex;
    spans.add(
      TextSpan(
        text: text.substring(match.start, match.end),
        style: style.copyWith(
          backgroundColor: isCurrent
              ? theme.searchCurrentMatchColor
              : theme.searchMatchColor,
          color: theme.searchHighlightForeground,
        ),
      ),
    );
    start = match.end;
  }

  if (start < text.length) {
    spans.add(TextSpan(text: text.substring(start), style: style));
  }

  return spans;
}
