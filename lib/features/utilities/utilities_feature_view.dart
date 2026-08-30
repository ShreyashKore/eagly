import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../../presentation/components/centered_state_message.dart';
import '../../presentation/components/feature_view.dart';
import '../../presentation/theme/app_theme.dart';
import 'components/utility_output_panel.dart';
import 'components/utility_tile.dart';
import 'data/utility_command.dart';
import 'utilities_controller.dart';
import 'utility_runner.dart';

/// Utilities pane: the device-command catalog as a searchable, grouped list.
///
/// The view is entirely driven by the catalog — it renders whatever
/// [UtilitiesController.groups] hands it — so it never mentions a specific
/// command or platform. Clicking a tile collects parameters (if any), confirms
/// (if the command asks for it), runs, and shows the result in the output
/// panel or, for side-effect-only commands, a snackbar.
///
/// Because a click can lead to three different places, every tile carries a
/// chip saying which (see [UtilityTile]) and the pane keeps a one-line legend
/// under the search box explaining them.
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

  Future<void> _handleTap(UtilityCommand command) => runUtilityCommand(
    context,
    controller: controller,
    command: command,
    showSnackBar: showSnackBar,
  );

  void _clearSearch() {
    _searchController.clear();
    controller.setSearchText('');
  }

  /// The command behind the result panel, when it can be run again right now.
  UtilityCommand? _rerunnable(UtilityRunResult result) {
    if (controller.isRunning || !controller.isConnected) return null;
    return controller.commandById(result.commandId);
  }

  @override
  Widget buildContent(BuildContext context) {
    final result = controller.lastResult;
    final rerun = result == null ? null : _rerunnable(result);

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
            onClear: controller.searchText.isEmpty ? null : _clearSearch,
          ),
          if (controller.hasAnyUtility) const _Legend(),
          if (!controller.isConnected) const _DisconnectedNotice(),
          Expanded(child: _buildBody(context)),
          if (result != null)
            UtilityOutputPanel(
              result: result,
              onClose: controller.clearResult,
              onRerun: rerun == null ? null : () => _handleTap(rerun),
            ),
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
      return CenteredStateMessage(
        icon: Icons.search_off,
        title: 'No matching utilities',
        description: 'Try a different search.',
        footer: TextButton.icon(
          onPressed: _clearSearch,
          icon: const Icon(Icons.close, size: 16),
          label: const Text('Clear search'),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(top: 4, bottom: 16),
      itemCount: groups.length,
      itemBuilder: (context, index) {
        final group = groups[index];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _GroupHeader(
              title: group.title,
              icon: group.icon,
              count: group.commands.length,
              isFirst: index == 0,
            ),
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

/// One-line key to the tile chips. Cheap to read, and it is the difference
/// between "why did that just reboot my phone" and an informed click.
class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final eaglyTheme = context.eaglyTheme;
    final muted = theme.colorScheme.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 7, 12, 7),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Wrap(
        spacing: 14,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _LegendItem(
            icon: Icons.play_arrow_rounded,
            label: 'Runs at once',
            color: muted,
          ),
          _LegendItem(
            icon: Icons.tune,
            label: 'Asks for options',
            color: muted,
          ),
          _LegendItem(
            icon: Icons.warning_amber_rounded,
            label: 'Asks to confirm',
            color: eaglyTheme.warningColor,
          ),
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const Gap(4),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
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
  const _GroupHeader({
    required this.title,
    required this.icon,
    required this.count,
    required this.isFirst,
  });

  final String title;
  final IconData icon;
  final int count;
  final bool isFirst;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    return Padding(
      padding: EdgeInsets.fromLTRB(14, isFirst ? 12 : 20, 14, 6),
      child: Row(
        children: [
          Icon(icon, size: 14, color: muted),
          const Gap(8),
          Text(
            title.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: muted,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.6,
            ),
          ),
          const Gap(8),
          Text(
            '$count',
            style: theme.textTheme.labelSmall?.copyWith(
              color: muted.withValues(alpha: 0.7),
            ),
          ),
          const Gap(10),
          Expanded(
            child: Divider(
              height: 1,
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback? onClear;

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
            suffixIcon: onClear == null
                ? null
                : IconButton(
                    tooltip: 'Clear search',
                    iconSize: 15,
                    visualDensity: VisualDensity.compact,
                    onPressed: onClear,
                    icon: const Icon(Icons.close),
                  ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          ),
        ),
      ),
    );
  }
}
