import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../../presentation/components/centered_state_message.dart';
import '../../presentation/components/feature_view.dart';
import '../../presentation/theme/app_theme.dart';
import 'components/utility_output_panel.dart';
import 'components/utility_params_dialog.dart';
import 'components/utility_tile.dart';
import 'data/utility_command.dart';
import 'utilities_controller.dart';

/// Utilities pane: the device-command catalog as a searchable, grouped list.
///
/// The view is entirely driven by the catalog — it renders whatever
/// [UtilitiesController.groups] hands it — so it never mentions a specific
/// command or platform. Clicking a tile collects parameters (if any), confirms
/// (if the command asks for it), runs, and shows the result in the output
/// panel or, for side-effect-only commands, a snackbar.
class UtilitiesFeatureView extends FeatureView {
  const UtilitiesFeatureView({
    super.key,
    required this.controller,
    required super.onClose,
  });

  final UtilitiesController controller;

  @override
  State<UtilitiesFeatureView> createState() => _UtilitiesFeatureViewState();
}

class _UtilitiesFeatureViewState
    extends FeatureViewState<UtilitiesFeatureView> {
  final TextEditingController _searchController = TextEditingController();

  UtilitiesController get controller => widget.controller;

  @override
  Listenable get listenable => controller;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _handleTap(UtilityCommand command) async {
    var values = command.defaultValues;

    if (command.needsInput) {
      final collected = await showUtilityParamsDialog(
        context,
        command: command,
      );
      if (collected == null || !mounted) return;
      values = collected;
    }

    final confirmation = command.confirmation;
    if (confirmation != null) {
      final confirmed = await _confirm(command, confirmation);
      if (!confirmed || !mounted) return;
    }

    final result = await controller.run(command, values: values);
    if (result == null || !mounted) return;

    if (!result.isSuccess) {
      showSnackBar(result.failure ?? '${command.label} failed.');
    } else if (!command.expectsOutput) {
      showSnackBar(command.successMessage ?? '${command.label} done.');
    }
  }

  Future<bool> _confirm(UtilityCommand command, String message) async {
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

  @override
  Widget buildContent(BuildContext context) {
    final result = controller.lastResult;

    return FeaturePane(
      header: FeatureViewHeader(
        title: 'Utilities',
        onClose: widget.onClose,
        closeTooltip: 'Close utilities pane',
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SearchField(
            controller: _searchController,
            onChanged: controller.setSearchText,
          ),
          if (!controller.isConnected) const _DisconnectedNotice(),
          Expanded(child: _buildBody(context)),
          if (result != null)
            UtilityOutputPanel(result: result, onClose: controller.clearResult),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (!controller.hasAnyUtility) {
      return const CenteredStateMessage(
        icon: Icons.handyman_outlined,
        title: 'No utilities here',
        description: 'This session is not backed by a real device.',
      );
    }

    final groups = controller.groups;
    if (groups.isEmpty) {
      return const CenteredStateMessage(
        icon: Icons.search_off,
        title: 'No matching utilities',
        description: 'Try a different search.',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: groups.length,
      itemBuilder: (context, index) {
        final group = groups[index];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _GroupHeader(title: group.title, icon: group.icon),
            for (final command in group.commands)
              UtilityTile(
                key: ValueKey(command.id),
                command: command,
                preview: command.previewFor(controller.device),
                isRunning: controller.runningCommandId == command.id,
                enabled: controller.isConnected && !controller.isRunning,
                onTap: () => _handleTap(command),
              ),
          ],
        );
      },
    );
  }
}

/// Inline strip explaining why every tile is dimmed.
class _DisconnectedNotice extends StatelessWidget {
  const _DisconnectedNotice();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final eaglyTheme = context.eaglyTheme;

    return Container(
      width: double.infinity,
      color: eaglyTheme.inlineNoticeBackground,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          Icon(
            Icons.link_off,
            size: 14,
            color: eaglyTheme.inlineNoticeForeground,
          ),
          const Gap(8),
          Expanded(
            child: Text(
              'Device disconnected — reconnect it to run these.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: eaglyTheme.inlineNoticeForeground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.title, required this.icon});

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 18, 12, 6),
      child: Row(
        children: [
          Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
          const Gap(8),
          Text(
            title.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: SizedBox(
        height: 34,
        child: TextField(
          controller: controller,
          onChanged: onChanged,
          style: theme.textTheme.bodySmall,
          decoration: InputDecoration(
            isDense: true,
            hintText: 'Search utilities…',
            prefixIcon: const Icon(Icons.search, size: 18),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          ),
        ),
      ),
    );
  }
}
