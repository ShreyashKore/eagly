import 'package:flutter/material.dart';

import 'components/utility_params_dialog.dart';
import 'components/utility_result_dialog.dart';
import 'data/utility_command.dart';
import 'utilities_controller.dart';
import '../../presentation/components/confirm_dialog.dart';

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
///
/// [showResultInDialog] is for callers outside the Utilities pane, which
/// run a command without opening the pane: its output — and the output of
/// any failure, which a snackbar can't carry — then goes to a result dialog
/// instead of the pane's output panel. A side-effect-only command that
/// succeeds still just reports with a snackbar.
Future<void> runUtilityCommand(
  BuildContext context, {
  required UtilitiesController controller,
  required UtilityCommand command,
  required void Function(String message) showSnackBar,
  Map<String, String> initialValues = const {},
  bool showResultInDialog = false,
}) async {
  // The pane disables its tiles while a run is in flight; the palette and the
  // Apps menu can't, so say why nothing happens rather than doing nothing.
  final runningId = controller.runningCommandId;
  if (runningId != null) {
    final running = controller.commandById(runningId)?.label ?? 'A utility';
    showSnackBar('$running is still running — try again when it finishes.');
    return;
  }

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

  final run = controller.run(command, values: values);
  if (showResultInDialog && command.expectsOutput) {
    await showUtilityResultDialog(
      context,
      controller: controller,
      command: command,
      values: values,
      run: run,
    );
    return;
  }

  final result = await run;
  if (result == null || !context.mounted) return;

  if (!result.isSuccess && showResultInDialog) {
    await showUtilityResultDialog(
      context,
      controller: controller,
      command: command,
      values: values,
      run: Future.value(result),
    );
  } else if (!result.isSuccess) {
    showSnackBar(result.failure ?? '${command.label} failed.');
  } else if (!command.expectsOutput) {
    showSnackBar(command.successMessage ?? '${command.label} done.');
  }
}

Future<bool> _confirmUtility(
  BuildContext context,
  UtilityCommand command,
  String message,
) => showConfirmDialog(
  context,
  title: '${command.label}?',
  message: message,
  confirmLabel: command.label,
  destructive: true,
);
