import 'package:flutter/material.dart';

// Extension to trigger a DropdownButton (or similar) open action by
// invoking the ActivateIntent on the appropriate descendant Actions widget.
// This encapsulates the traversal logic so callers can simply call
// `someGlobalKey.openDropdown()`.
extension GlobalKeyDropdownExtension on GlobalKey {
  void openDropdown() {
    currentContext?.visitChildElements((element) {
      if (element.widget is Semantics) {
        element.visitChildElements((element) {
          if (element.widget is Actions) {
            element.visitChildElements((element) {
              Actions.invoke(element, ActivateIntent());
            });
          }
        });
      }
    });
  }
}
