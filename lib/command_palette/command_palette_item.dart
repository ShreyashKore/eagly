import 'package:flutter/widgets.dart';

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

  bool matches(String query) {
    if (query.isEmpty) return true;
    final q = query.toLowerCase();
    return label.toLowerCase().contains(q) ||
        category.toLowerCase().contains(q) ||
        (subtitle?.toLowerCase().contains(q) ?? false) ||
        keywords.any((keyword) => keyword.toLowerCase().contains(q));
  }
}
