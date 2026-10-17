import 'package:flutter/material.dart';

import 'components/utility_params_dialog.dart';
import 'data/utility_command.dart';
import 'utilities_controller.dart';

/// Runs [command] through [controller] the same way the Utilities pane does:
/// collect parameters (if any), confirm (if the command asks for it), run it,
/// then report the outcome via [showSnackBar]. Shared so anything that can
/// trigger a utility — the pane's own tiles, the command palette, the Apps
/// pane's right-click menu — goes through one place for the params/confirm
/// flow instead of reimplementing it.
///
/// [initialValues] pre-fills parameters the caller already knows, keyed by
/// [UtilityParam.key]; the Apps pane uses it to hand over the package name of
/// the app that was right-clicked.
///
/// A command that needs input *and* wants confirmation is confirmed inside
/// the parameters dialog (which shows the warning and a destructive Run
/// button), so the user never has to clear two dialogs in a row.
Future<void> runUtilityCommand(
  BuildContext context, {
  required UtilitiesController controller,
  required UtilityCommand command,
  required void Function(String message) showSnackBar,
  Map<String, String> initialValues = const {},
}) async {
  var values = {...command.defaultValues, ...initialValues};

  if (command.needsInput) {
    final collected = await showUtilityParamsDialog(
      context,
      command: command,
      device: controller.device,
      initialValues: values,
    );
    if (collected == null || !context.mounted) return;
    values = collected;
  }

  final confirmation = command.confirmation;
  if (confirmation != null && !command.needsInput) {
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
