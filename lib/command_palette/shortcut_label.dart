import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Renders a [SingleActivator] as a short, platform-appropriate label (e.g.
/// `⌘⇧R` on macOS, `Ctrl+Shift+R` elsewhere) for display in the command
/// palette and its entry points. Display-only — it does not register the
/// shortcut itself (see `app_menu/shortcuts.dart` for that).
String describeShortcut(SingleActivator activator) {
  final isMac = Platform.isMacOS;
  final modifiers = <String>[
    if (activator.control) isMac ? '⌃' : 'Ctrl',
    if (activator.alt) isMac ? '⌥' : 'Alt',
    if (activator.shift) isMac ? '⇧' : 'Shift',
    if (activator.meta) isMac ? '⌘' : 'Meta',
  ];
  final key = _keyLabel(activator.trigger);
  return isMac ? '${modifiers.join()}$key' : [...modifiers, key].join('+');
}

String _keyLabel(LogicalKeyboardKey key) {
  if (key == LogicalKeyboardKey.space) return 'Space';
  if (key == LogicalKeyboardKey.end) return 'End';
  if (key == LogicalKeyboardKey.equal) return '=';
  if (key == LogicalKeyboardKey.minus) return '-';
  if (key == LogicalKeyboardKey.comma) return ',';
  return key.keyLabel.toUpperCase();
}
