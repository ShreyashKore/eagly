import 'package:flutter/widgets.dart';

import 'app_menu_controller.dart';
import 'app_menu_state.dart';

/// Exposes the [AppMenuController] to the widget subtree.
///
/// Being an [InheritedNotifier], any widget that reads it via [of] rebuilds
/// when the controller notifies — i.e. when the [AppMenuState] snapshot
/// changes. Use [maybeOf]/[of] to reach the controller without passing it down
/// explicitly.
class AppMenuScope extends InheritedNotifier<AppMenuController> {
  const AppMenuScope({
    super.key,
    required AppMenuController controller,
    required super.child,
  }) : super(notifier: controller);

  static AppMenuController? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<AppMenuScope>()
        ?.notifier;
  }

  static AppMenuController of(BuildContext context) {
    final controller = maybeOf(context);
    assert(controller != null, 'No AppMenuScope found in context');
    return controller!;
  }

  /// Reads just the current snapshot (and subscribes to changes).
  static AppMenuState stateOf(BuildContext context) =>
      of(context).state;
}
