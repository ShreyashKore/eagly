import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tabbed_view/tabbed_view.dart';

import 'constants/app_constants.dart';
import 'controllers/log_tab_controller.dart';
import 'intents/home_page_intents.dart';
import 'widgets/device_presentation.dart';

const homePageShortcuts = <ShortcutActivator, Intent>{
  SingleActivator(LogicalKeyboardKey.keyF, control: true):
      ActivateSearchIntent(),
  SingleActivator(LogicalKeyboardKey.keyF, meta: true): ActivateSearchIntent(),
  SingleActivator(LogicalKeyboardKey.minus, control: true):
      DecreaseFontIntent(),
  SingleActivator(LogicalKeyboardKey.minus, meta: true): DecreaseFontIntent(),
  SingleActivator(LogicalKeyboardKey.equal, control: true):
      IncreaseFontIntent(),
  SingleActivator(LogicalKeyboardKey.equal, meta: true): IncreaseFontIntent(),
  SingleActivator(LogicalKeyboardKey.numpadAdd, control: true):
      IncreaseFontIntent(),
  SingleActivator(LogicalKeyboardKey.numpadAdd, meta: true):
      IncreaseFontIntent(),
};

class NewTabActionLabel extends StatelessWidget {
  const NewTabActionLabel({super.key, this.textStyle});

  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.add, size: (textStyle?.fontSize ?? 14) + 2),
        const SizedBox(width: 6),
        Text(AppConstants.newTabLabel, style: textStyle),
      ],
    );
  }
}

class WorkspaceTabBinding {
  WorkspaceTabBinding({
    required this.tabData,
    required this.controller,
    required this.syncListener,
  });

  final TabData tabData;
  final LogTabController controller;
  final VoidCallback syncListener;

  void dispose() {
    controller.removeListener(syncListener);
    controller.dispose();
  }
}

class WorkspaceTabLabel extends StatelessWidget {
  const WorkspaceTabLabel({
    super.key,
    required this.controller,
    this.textStyle,
  });

  final LogTabController controller;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final selectedDevice = controller.selectedDevice;
        if (selectedDevice == null) {
          return Text(
            controller.title,
            style: textStyle,
            overflow: TextOverflow.ellipsis,
          );
        }

        return DeviceSelectionLabel(
          device: selectedDevice,
          textStyle: textStyle,
          secondaryTextStyle: Theme.of(context).textTheme.labelSmall,
          maxWidth: 220,
          iconSize: (textStyle?.fontSize ?? 14) + 2,
        );
      },
    );
  }
}

class HomeTabsStyleResolver extends MinimalistTabStyleResolver {
  HomeTabsStyleResolver({required this.colorScheme});

  final ColorScheme colorScheme;

  @override
  Color? backgroundColor(TabStyleContext context) {
    if (context.status == TabStatus.selected) {
      return colorScheme.surface;
    }
    return colorScheme.surfaceContainerHighest;
  }

  @override
  Color buttonColor(TabStyleContext context) {
    return context.status == TabStatus.selected
        ? colorScheme.onSurface
        : colorScheme.onSurfaceVariant;
  }

  @override
  Color fontColor(TabStyleContext context) {
    return context.status == TabStatus.selected
        ? colorScheme.onSurface
        : colorScheme.onSurfaceVariant;
  }
}

void debugTabs(Object? message) {
  // ignore: avoid_print
  print('[DEBUG_TAB] $message');
}
