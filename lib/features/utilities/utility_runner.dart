import 'package:flutter/material.dart';

import 'components/utility_params_dialog.dart';
import 'data/utility_command.dart';
import 'utilities_controller.dart';

/// Runs [command] through [controller] the same way the Utilities pane does:
/// collect parameters (if any), confirm (if the command asks for it), run it,
/// then report the outcome via [showSnackBar]. Shared so anything that can
/// trigger a utility — the pane's own tiles, the command palette — goes
/// through one place for the params/confirm flow instead of reimplementing
/// it.
Future<void> runUtilityCommand(
  BuildContext context, {
  required UtilitiesController controller,
  required UtilityCommand command,
  required void Function(String message) showSnackBar,
}) async {
  var values = command.defaultValues;

  if (command.needsInput) {
    final collected = await showUtilityParamsDialog(context, command: command);
    if (collected == null || !context.mounted) return;
    values = collected;
  }

  final confirmation = command.confirmation;
  if (confirmation != null) {
    final confirmed = await _confirmUtility(context, command, confirmation);
    if (!confirmed || !context.mounted) return;
  }

  final result = await controller.run(command, values: values);
  if (result == null || !context.mounted) return;

  if (!result.isSuccess) {
    showSnackBar(result.failure ?? '${command.label} failed.');
  } else if (!command.expectsOutput) {
    showSnackBar(command.successMessage ?? '${command.label} done.');
  }
}

Future<bool> _confirmUtility(
  BuildContext context,
  UtilityCommand command,
  String message,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('${command.label}?'),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(command.label),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
