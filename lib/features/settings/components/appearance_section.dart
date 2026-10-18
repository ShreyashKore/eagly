import 'package:flutter/material.dart';

import 'settings_section_card.dart';

/// 'Appearance' section: theme toggle, log font size, and the feature-tips
/// switch.
class const AppearanceSection({
  super.key,
  required final int themeIndex,
  required final ValueChanged<int> onThemeChanged,
  required final double logFontSize,
  required final ValueChanged<double> onLogFontSizeChanged,
  required final bool tipsEnabled,
  required final ValueChanged<bool> onTipsEnabledChanged,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SettingsSectionCard(
      title: 'Appearance',
      children: [
        SettingsRow(
          child: Row(
            children: [
              Expanded(child: Text('Theme', style: theme.textTheme.bodyLarge)),
              ToggleButtons(
                isSelected: List.generate(
                  3,
                  (i) => i == themeIndex,
                  growable: false,
                ),
                onPressed: (index) => onThemeChanged(index),
                borderRadius: BorderRadius.circular(6),
                selectedBorderColor: theme.colorScheme.primary.withValues(
                  alpha: 0.5,
                ),
                constraints: const BoxConstraints(minWidth: 84, minHeight: 36),
                children: const [Text('Auto'), Text('Light'), Text('Dark')],
              ),
            ],
          ),
        ),
        SettingsRow(
          child: Row(
            children: [
              Expanded(
                child: Text('Log font size', style: theme.textTheme.bodyLarge),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 12,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('Aa', style: TextStyle(fontSize: logFontSize)),
                  ),
                  SizedBox(
                    width: 200,
                    child: Slider(
                      value: logFontSize,
                      min: 8,
                      max: 24,
                      divisions: 16,
                      label: logFontSize.toStringAsFixed(0),
                      onChanged: onLogFontSizeChanged,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        SwitchListTile(
          dense: true,
          value: tipsEnabled,
          title: const Text('Feature tips'),
          subtitle: const Text('Show a rotating tip in the app header'),
          onChanged: onTipsEnabledChanged,
        ),
      ],
    );
  }
}
