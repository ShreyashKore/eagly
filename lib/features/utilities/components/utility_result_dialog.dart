import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gap/gap.dart';

import '../../../presentation/components/app_icon_button.dart';
import '../../../presentation/components/eagly_dialog.dart';
import '../../../presentation/theme/app_theme.dart';
import '../data/utility_command.dart';
import '../utilities_controller.dart';
import 'utility_output_panel.dart';

/// Shows the outcome of a utility started outside the Utilities pane — from
/// the command palette or the Apps pane's right-click menu — so running one
/// never has to open the pane just to have somewhere to put the answer.
///
/// [run] is the run already in flight (or finished): the dialog shows a
/// spinner until it completes, then the same status, command line and output
/// the pane's [UtilityOutputPanel] would. "Run again" repeats [command] with
/// the same [values].
Future<void> showUtilityResultDialog(
  BuildContext context, {
  required UtilitiesController controller,
  required UtilityCommand command,
  required Map<String, String> values,
  required Future<UtilityRunResult?> run,
}) {
  return showEaglyDialog<void>(
    context: context,
    builder: (context) => _UtilityResultDialog(
      controller: controller,
      command: command,
      values: values,
      initialRun: run,
    ),
  );
}

class const _UtilityResultDialog({
  required final UtilitiesController controller,
  required final UtilityCommand command,
  required final Map<String, String> values,
  required final Future<UtilityRunResult?> initialRun,
}) extends StatefulWidget {
  @override
  State<_UtilityResultDialog> createState() => _UtilityResultDialogState();
}

class _UtilityResultDialogState extends State<_UtilityResultDialog> {
  late Future<UtilityRunResult?> _run = widget.initialRun;

  void _rerun() {
    setState(() {
      _run = widget.controller.run(widget.command, values: widget.values);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) => FutureBuilder<UtilityRunResult?>(
        future: _run,
        builder: (context, snapshot) {
          final done = snapshot.connectionState == ConnectionState.done;
          final result = snapshot.data;
          final controller = widget.controller;
          final canRerun =
              done && !controller.isRunning && controller.isConnected;

          return EaglyDialog(
            title: widget.command.label,
            icon: widget.command.icon,
            width: 680,
            contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            headerActions: [
              if (canRerun)
                AppIconButton(
                  tooltip: 'Run again',
                  onPressed: _rerun,
                  icon: Icons.refresh,
                ),
              if (done && result != null)
                AppIconButton(
                  tooltip: 'Copy output',
                  onPressed: () =>
                      Clipboard.setData(ClipboardData(text: result.copyText)),
                  icon: Icons.copy_all_outlined,
                ),
            ],
            child: !done
                ? _Running(
                    commandLine:
                        widget.command.previewWith(
                          controller.device,
                          widget.values,
                        ) ??
                        '',
                  )
                : result == null
                ? const _NotRun()
                : _Result(result: result),
          );
        },
      ),
    );
  }
}

class const _Result({required final UtilityRunResult result})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        UtilityStatusPill(result: result),
        const Gap(12),
        Flexible(
          child: SingleChildScrollView(
            child: SizedBox(
              width: double.infinity,
              child: UtilityOutputBody(result: result),
            ),
          ),
        ),
      ],
    );
  }
}

class const _Running({required final String commandLine})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final eaglyTheme = context.eaglyTheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SizedBox.square(
              dimension: context.scaled(16),
              child: const CircularProgressIndicator(strokeWidth: 2),
            ),
            const Gap(10),
            Text('Running…', style: theme.textTheme.bodyMedium),
          ],
        ),
        if (commandLine.isNotEmpty) ...[
          const Gap(12),
          SelectableText(
            '\$ $commandLine',
            style: eaglyTheme.monoStyle.copyWith(
              fontSize: 11,
              height: 1.35,
              color: eaglyTheme.tertiaryTextColor,
            ),
          ),
        ],
      ],
    );
  }
}

/// The controller refused the run — another utility got there first, or the
/// session went away underneath it.
class const _NotRun() extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Text(
      'This utility did not run. Another one may still be running — try '
      'again when it finishes.',
      style: Theme.of(context).textTheme.bodyMedium
          ?.copyWith(color: context.eaglyTheme.secondaryTextColor),
    );
  }
}
