import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../../../data/device.dart';
import '../../../presentation/components/combo_field.dart';
import '../../../presentation/components/eagly_dialog.dart';
import '../../../presentation/theme/app_theme.dart';
import '../data/utility_command.dart';

/// Collects a command's [UtilityCommand.params] before it runs. Returns the
/// values keyed by [UtilityParam.key], or null when cancelled.
///
/// [initialValues] pre-fills fields the caller already knows (the Apps pane
/// passes the package name of the app that was right-clicked), and
/// [device] — when given — powers the live preview of the exact command line
/// the Run button will execute.
///
/// A command that also carries a [UtilityCommand.confirmation] is confirmed
/// *here*, inline, rather than in a second dialog: the body shows the warning
/// and the Run button turns destructive. [runUtilityCommand] relies on that.
Future<Map<String, String>?> showUtilityParamsDialog(
  BuildContext context, {
  required UtilityCommand command,
  Device? device,
  Map<String, String> initialValues = const {},
}) {
  return showEaglyDialog<Map<String, String>>(
    context: context,
    builder: (context) => _UtilityParamsDialog(
      command: command,
      device: device,
      initialValues: initialValues,
    ),
  );
}

class _UtilityParamsDialog extends StatefulWidget {
  const _UtilityParamsDialog({
    required this.command,
    required this.device,
    required this.initialValues,
  });

  final UtilityCommand command;
  final Device? device;
  final Map<String, String> initialValues;

  @override
  State<_UtilityParamsDialog> createState() => _UtilityParamsDialogState();
}

class _UtilityParamsDialogState extends State<_UtilityParamsDialog> {
  late final Map<String, String> _values = {
    for (final param in widget.command.params)
      param.key: widget.initialValues[param.key] ?? param.defaultValue,
  };
  late final Map<String, TextEditingController> _textControllers = {
    for (final param in widget.command.params)
      if (param.kind != UtilityParamKind.choice)
        param.key: TextEditingController(text: _values[param.key]),
  };

  /// The first field the user still has to fill in — so a dialog opened from
  /// the Apps pane with the package already known lands on the *next* field
  /// instead of the one that is done.
  late final UtilityParam? _autofocusParam = widget.command.params
      .cast<UtilityParam?>()
      .firstWhere(
        (param) => (_values[param!.key] ?? '').trim().isEmpty,
        orElse: () => widget.command.params.first,
      );

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

  void _setValue(UtilityParam param, String value) {
    setState(() => _values[param.key] = value);
  }

  void _submit() {
    if (!_canRun) return;
    Navigator.of(context).pop(Map<String, String>.from(_values));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final command = widget.command;
    final confirmation = command.confirmation;

    return EaglyDialog(
      title: command.label,
      icon: command.icon,
      width: 520,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              command.description,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: context.eaglyTheme.secondaryTextColor,
              ),
            ),
            if (confirmation != null) ...[
              const Gap(14),
              _WarningBanner(message: confirmation),
            ],
            const Gap(20),
            for (final param in command.params) ...[
              _buildField(param),
              const Gap(16),
            ],
            _CommandPreview(
              commandLine: _previewLine(),
              expectsOutput: command.expectsOutput,
            ),
            const Gap(20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const Gap(8),
                FilledButton.icon(
                  style: confirmation == null
                      ? null
                      : FilledButton.styleFrom(
                          backgroundColor: theme.colorScheme.error,
                          foregroundColor: theme.colorScheme.onError,
                        ),
                  onPressed: _canRun ? _submit : null,
                  icon: Icon(
                    confirmation == null
                        ? Icons.play_arrow
                        : Icons.warning_amber_rounded,
                    size: 18,
                  ),
                  label: Text(confirmation == null ? 'Run' : command.label),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// The command line as it stands, with anything still blank shown as a
  /// placeholder so the preview never looks like a broken command.
  String? _previewLine() {
    final device = widget.device;
    if (device == null) return null;
    final filled = {
      for (final param in widget.command.params)
        param.key: (_values[param.key] ?? '').trim().isEmpty
            ? '<${param.label.toLowerCase()}>'
            : _values[param.key]!,
    };
    return widget.command.previewWith(device, filled);
  }

  Widget _buildField(UtilityParam param) {
    final autofocus = param == _autofocusParam;
    switch (param.kind) {
      case UtilityParamKind.choice:
        return DropdownButtonFormField<String>(
          initialValue: _values[param.key],
          decoration: _decorationFor(param),
          items: [
            for (final option in param.options)
              DropdownMenuItem(value: option.value, child: Text(option.label)),
          ],
          onChanged: (value) {
            if (value == null) return;
            _setValue(param, value);
          },
        );
      case UtilityParamKind.suggestion:
        return ComboField(
          controller: _textControllers[param.key]!,
          options: [
            for (final option in param.options)
              ComboOption(
                value: option.value,
                label: option.label,
                description: option.description,
              ),
          ],
          decoration: _decorationFor(param),
          autofocus: autofocus,
          onChanged: (value) => _setValue(param, value),
          onSubmitted: (_) => _submit(),
        );
      case UtilityParamKind.text:
        return TextField(
          controller: _textControllers[param.key]!,
          autofocus: autofocus,
          decoration: _decorationFor(param),
          onChanged: (value) => _setValue(param, value),
          onSubmitted: (_) => _submit(),
        );
    }
  }

  InputDecoration _decorationFor(UtilityParam param) => InputDecoration(
    labelText: param.label,
    hintText: param.hint,
    helperText: param.helperText,
    helperMaxLines: 2,
    border: const OutlineInputBorder(),
    isDense: true,
  );
}

/// Shows the exact line that will run, so the dialog is never a black box.
///
/// It is there for whoever wants to check, not something to read before
/// every run, so it stays a footnote: a faint well with no border, a
/// sentence-case caption at tertiary, and the command at secondary — the
/// fields and the Run button stay the loudest things in the dialog.
class _CommandPreview extends StatelessWidget {
  const _CommandPreview({
    required this.commandLine,
    required this.expectsOutput,
  });

  final String? commandLine;
  final bool expectsOutput;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final eaglyTheme = context.eaglyTheme;
    if (commandLine == null) return const SizedBox.shrink();

    final caption = theme.textTheme.labelSmall?.copyWith(
      color: eaglyTheme.tertiaryTextColor,
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.terminal,
                size: 12,
                color: eaglyTheme.tertiaryTextColor,
              ),
              const Gap(6),
              Text('Will run', style: caption),
              const Spacer(),
              Text(
                expectsOutput ? 'Shows output below' : 'No output',
                style: caption,
              ),
            ],
          ),
          const Gap(4),
          SelectableText(
            commandLine!,
            style: eaglyTheme.monoStyle.copyWith(
              fontSize: 11.5,
              height: 1.35,
              color: eaglyTheme.secondaryTextColor,
            ),
          ),
        ],
      ),
    );
  }
}

/// The inline confirmation for a destructive command that also takes input —
/// shown here instead of stacking a second dialog on top of this one.
class _WarningBanner extends StatelessWidget {
  const _WarningBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final warning = context.eaglyTheme.warningColor;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: warning.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, size: 16, color: warning),
          const Gap(10),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
