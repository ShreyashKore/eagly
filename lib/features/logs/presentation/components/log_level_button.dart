import 'package:flutter/material.dart';

import '../../../../presentation/components/anchored_popover.dart';
import '../../../../presentation/theme/log_level_presentation.dart';
import '../../data/models/log_level.dart';
import 'filter_bar_shared.dart';
import 'log_filter_controller.dart';
import 'log_filter_parts.dart';

/// The filter bar's **Level** button on its own, for a host that places it
/// apart from the filter field.
class const LogLevelButton({
  super.key,
  required final LogFilterController controller,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => _LevelButton(controller: controller),
  );
}

class const _LevelButton({required final LogFilterController controller})
    extends StatefulWidget {
  @override
  State<_LevelButton> createState() => _LevelButtonState();
}

class _LevelButtonState extends State<_LevelButton> {
  final PopoverController _popover = PopoverController();

  @override
  void dispose() {
    _popover.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final isIos = controller.isIos;
    final level = controller.selectedLevel.normalizeSelectionForPlatform(
      isIos: isIos,
    );
    final style = FilterControlStyle.of(context);
    final levels = isIos ? LogLevel.iosValues : LogLevel.androidValues;
    return AnchoredPopover(
      controller: _popover,
      width: 220,
      popoverBuilder: (context) => Padding(
        padding: const EdgeInsets.all(6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const FilterMenuSectionLabel('Show this level and above'),
            for (final option in levels)
              FilterMenuRow(
                highlighted: option == level,
                trailing: option == level
                    ? Icon(
                        Icons.check,
                        size: 15,
                        color: Theme.of(context).colorScheme.primary,
                      )
                    : null,
                onTap: () {
                  _popover.close();
                  controller.setLevel(option);
                },
                child: LogLevelLabel(
                  level: option,
                  isIos: isIos,
                  includeValueInLabel: true,
                  compact: true,
                  textStyle: const TextStyle(fontSize: 12.5),
                ),
              ),
          ],
        ),
      ),
      child: FilterControlButton(
        icon: Icons.signal_cellular_alt_rounded,
        active: level != controller.defaultLevel,
        tooltip: 'Minimum log level',
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Level', style: style.hint),
            const SizedBox(width: 6),
            LogLevelLabel(
              level: level,
              isIos: isIos,
              compact: true,
              textStyle: style.label,
            ),
          ],
        ),
        trailing: Icon(Icons.expand_more, size: 16, color: style.icon),
        onPressed: _popover.toggle,
      ),
    );
  }
}
