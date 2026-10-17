import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../../../data/device.dart';
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
                color: theme.colorScheme.onSurfaceVariant,
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
        return _SuggestionField(
          param: param,
          controller: _textControllers[param.key]!,
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

/// A text field with a dropdown of common values attached. Typing filters the
/// list; picking an entry fills the field. Anything typed is kept as-is — the
/// suggestions are a shortcut, not a whitelist.
class _SuggestionField extends StatefulWidget {
  const _SuggestionField({
    required this.param,
    required this.controller,
    required this.decoration,
    required this.autofocus,
    required this.onChanged,
    required this.onSubmitted,
  });

  final UtilityParam param;
  final TextEditingController controller;
  final InputDecoration decoration;
  final bool autofocus;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;

  @override
  State<_SuggestionField> createState() => _SuggestionFieldState();
}

class _SuggestionFieldState extends State<_SuggestionField> {
  final GlobalKey _fieldKey = GlobalKey();

  /// Suggestions matching what has been typed so far. Falls back to the whole
  /// list when nothing matches, so the menu is never empty.
  List<UtilityOption> get _matches {
    final query = widget.controller.text.trim().toLowerCase();
    if (query.isEmpty) return widget.param.options;
    final matches = widget.param.options
        .where(
          (option) =>
              option.value.toLowerCase().contains(query) ||
              option.label.toLowerCase().contains(query),
        )
        .toList();
    return matches.isEmpty ? widget.param.options : matches;
  }

  Future<void> _openMenu() async {
    final box = _fieldKey.currentContext?.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;

    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
    final position = RelativeRect.fromLTRB(
      topLeft.dx,
      topLeft.dy + box.size.height,
      overlay.size.width - topLeft.dx - box.size.width,
      0,
    );

    final picked = await showMenu<String>(
      context: context,
      position: position,
      constraints: BoxConstraints(minWidth: box.size.width),
      items: [
        for (final option in _matches)
          PopupMenuItem(
            value: option.value,
            height: option.description == null ? 40 : 52,
            child: _SuggestionRow(option: option),
          ),
      ],
    );
    if (picked == null || !mounted) return;
    widget.controller.text = picked;
    widget.controller.selection = TextSelection.collapsed(
      offset: picked.length,
    );
    widget.onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: _fieldKey,
      controller: widget.controller,
      autofocus: widget.autofocus,
      decoration: widget.decoration.copyWith(
        suffixIcon: IconButton(
          tooltip: 'Suggestions',
          iconSize: 20,
          visualDensity: VisualDensity.compact,
          onPressed: widget.param.options.isEmpty ? null : _openMenu,
          icon: const Icon(Icons.arrow_drop_down),
        ),
      ),
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
    );
  }
}

class _SuggestionRow extends StatelessWidget {
  const _SuggestionRow({required this.option});

  final UtilityOption option;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final description = option.description;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(option.label, style: theme.textTheme.bodyMedium),
        if (description != null)
          Text(
            description,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontFamily: 'monospace',
              fontSize: 11,
            ),
            overflow: TextOverflow.ellipsis,
          ),
      ],
    );
  }
}

/// Shows the exact line that will run, so the dialog is never a black box.
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
    if (commandLine == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.terminal,
                size: 13,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const Gap(6),
              Text(
                'WILL RUN',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.6,
                ),
              ),
              const Spacer(),
              Text(
                expectsOutput ? 'Shows output below' : 'No output',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const Gap(6),
          SelectableText(
            commandLine!,
            style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
              fontSize: 11.5,
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
