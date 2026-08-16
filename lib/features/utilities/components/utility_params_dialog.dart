import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../../../presentation/components/eagly_dialog.dart';
import '../data/utility_command.dart';

/// Collects a command's [UtilityCommand.params] before it runs. Returns the
/// values keyed by [UtilityParam.key], or null when cancelled.
Future<Map<String, String>?> showUtilityParamsDialog(
  BuildContext context, {
  required UtilityCommand command,
}) {
  return showEaglyDialog<Map<String, String>>(
    context: context,
    builder: (context) => _UtilityParamsDialog(command: command),
  );
}

class _UtilityParamsDialog extends StatefulWidget {
  const _UtilityParamsDialog({required this.command});

  final UtilityCommand command;

  @override
  State<_UtilityParamsDialog> createState() => _UtilityParamsDialogState();
}

class _UtilityParamsDialogState extends State<_UtilityParamsDialog> {
  late final Map<String, String> _values = widget.command.defaultValues;
  late final Map<String, TextEditingController> _textControllers = {
    for (final param in widget.command.params)
      if (param.kind == UtilityParamKind.text)
        param.key: TextEditingController(text: param.defaultValue),
  };

  @override
  void dispose() {
    for (final controller in _textControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  bool get _canRun => widget.command.params.every(
    (param) =>
        !param.isRequired || (_values[param.key] ?? '').trim().isNotEmpty,
  );

  void _submit() {
    if (!_canRun) return;
    Navigator.of(context).pop(Map<String, String>.from(_values));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final command = widget.command;

    return EaglyDialog(
      title: command.label,
      icon: command.icon,
      width: 460,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            command.description,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const Gap(20),
          for (final param in command.params) ...[
            _buildField(param),
            const Gap(14),
          ],
          const Gap(6),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              const Gap(8),
              FilledButton.icon(
                onPressed: _canRun ? _submit : null,
                icon: const Icon(Icons.play_arrow, size: 18),
                label: const Text('Run'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildField(UtilityParam param) {
    switch (param.kind) {
      case UtilityParamKind.choice:
        return DropdownButtonFormField<String>(
          initialValue: _values[param.key],
          decoration: InputDecoration(
            labelText: param.label,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
          items: [
            for (final option in param.options)
              DropdownMenuItem(value: option.value, child: Text(option.label)),
          ],
          onChanged: (value) {
            if (value == null) return;
            setState(() => _values[param.key] = value);
          },
        );
      case UtilityParamKind.text:
        return TextField(
          controller: _textControllers[param.key],
          autofocus: param == widget.command.params.first,
          decoration: InputDecoration(
            labelText: param.label,
            hintText: param.hint,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
          onChanged: (value) => setState(() => _values[param.key] = value),
          onSubmitted: (_) => _submit(),
        );
    }
  }
}
