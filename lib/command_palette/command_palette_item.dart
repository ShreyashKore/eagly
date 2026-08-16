import 'package:flutter/widgets.dart';

import 'fuzzy_match.dart';

/// One entry in the global command palette: something the user can search for
/// and run.
///
/// Sourced from wherever Eagly already defines a command — existing menu
/// actions, per-device pane navigation, device switching, … (see
/// `command_palette_items.dart`). The palette UI itself knows nothing about
/// where an item came from, so adding a new source never touches it.
@immutable
class CommandPaletteItem {
  const CommandPaletteItem({
    required this.id,
    required this.label,
    required this.category,
    required this.icon,
    required this.run,
    this.subtitle,
    this.shortcutLabel,
    this.keywords = const [],
  });

  final String id;
  final String label;

  /// Groups items under a header in the results list (e.g. "Navigate",
  /// "Capture", "Search").
  final String category;
  final IconData icon;

  /// Shown under [label] — typically the device this command applies to.
  final String? subtitle;

  /// Display-only accelerator hint (e.g. `⌘R`); does not register a shortcut.
  final String? shortcutLabel;

  /// Extra search terms beyond [label]/[category]/[subtitle].
  final List<String> keywords;

  final VoidCallback run;

  /// Fuzzy-matches [query] against this item, trying [label] first (weighted
  /// highest), then [keywords]/[subtitle], then [category] — so a query that
  /// hits the label always outranks one that only hits a keyword. Returns
  /// `null` when [query] doesn't fuzzy-match anything, or `0` for an empty
  /// query (every item matches, unranked).
  int? matchScore(String query) {
    if (query.isEmpty) return 0;

    int? best;
    void consider(String? text, int weight) {
      if (text == null || text.isEmpty) return;
      final score = fuzzyScore(query, text);
      if (score == null) return;
      final weighted = score * weight;
      if (best == null || weighted > best!) best = weighted;
    }

    consider(label, 4);
    for (final keyword in keywords) {
      consider(keyword, 2);
    }
    consider(subtitle, 2);
    consider(category, 1);
    return best;
  }
}
