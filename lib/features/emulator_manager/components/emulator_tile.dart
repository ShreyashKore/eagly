import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../data/emulator_entry.dart';

/// What the user picked from a tile's menu.
enum EmulatorTileAction {
  /// Resume the saved snapshot if there is one — the plain Start button.
  start,

  /// Boot from scratch. The usual fix for an AVD that resumes broken.
  coldBoot,

  /// Factory reset, then boot. Destructive, so it is confirmed first.
  wipeData,

  /// Delete the AVD outright. Also confirmed, and only offered when the SDK
  /// has the cmdline-tools that can do it.
  delete,
}

/// One AVD in the emulator list: what it is, and the one action it can take
/// right now.
///
/// Exactly one action is offered per state rather than showing Start and Stop
/// together with one greyed out — a mid-boot emulator has nothing useful to
/// press, and a disabled Stop invites clicking at it repeatedly.
class EmulatorTile extends StatelessWidget {
  const EmulatorTile({
    super.key,
    required this.entry,
    required this.onAction,
    required this.onStop,
    this.enabled = true,
    this.canDelete = false,
  });

  final EmulatorEntry entry;
  final ValueChanged<EmulatorTileAction> onAction;
  final VoidCallback onStop;

  /// False while another emulator action is in flight.
  final bool enabled;

  /// Whether this SDK has the cmdline-tools that can delete an AVD. Hidden
  /// rather than disabled: an action that can never work here is noise.
  final bool canDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final details = _details;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant),
        color: theme.colorScheme.surface,
      ),
      child: Row(
        children: [
          Icon(
            entry.emulator.hasPlayStore
                ? Icons.shop_outlined
                : Icons.phone_android_outlined,
            size: 22,
            color: entry.isRunning
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant,
          ),
          const Gap(12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        entry.label,
                        style: theme.textTheme.titleSmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (entry.serial != null) ...[
                      const Gap(8),
                      Text(
                        entry.serial!,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
                if (details != null) ...[
                  const Gap(2),
                  Text(
                    details,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          const Gap(12),
          _buildAction(context),
        ],
      ),
    );
  }

  /// `API 36.1 · Google Play · arm64-v8a · 1080 × 2400 · 2 GB`, minus whatever
  /// this AVD's config did not say. Null when nothing could be read at all,
  /// which is the cue to show one line rather than a row of blanks.
  String? get _details {
    if (entry.emulator.isMetadataMissing) return null;
    final resolution = entry.emulator.resolution;
    final ram = _formatRam(entry.emulator.ramMb);
    final parts = [
      entry.emulator.summary,
      if (resolution != null) resolution,
      if (ram != null) ram,
    ].where((part) => part.isNotEmpty);
    return parts.isEmpty ? null : parts.join(' · ');
  }

  static String? _formatRam(int? megabytes) {
    if (megabytes == null || megabytes <= 0) return null;
    if (megabytes % 1024 == 0) return '${megabytes ~/ 1024} GB';
    return '$megabytes MB';
  }

  Widget _buildAction(BuildContext context) {
    switch (entry.runState) {
      case EmulatorRunState.stopped:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FilledButton.tonalIcon(
              onPressed: enabled
                  ? () => onAction(EmulatorTileAction.start)
                  : null,
              icon: const Icon(Icons.play_arrow_rounded, size: 18),
              label: const Text('Start'),
            ),
            PopupMenuButton<EmulatorTileAction>(
              enabled: enabled,
              tooltip: 'More options',
              icon: const Icon(Icons.more_vert, size: 18),
              onSelected: onAction,
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: EmulatorTileAction.coldBoot,
                  child: _MenuRow(
                    Icons.restart_alt,
                    'Cold boot',
                    'Ignore the saved snapshot',
                  ),
                ),
                const PopupMenuItem(
                  value: EmulatorTileAction.wipeData,
                  child: _MenuRow(
                    Icons.delete_sweep_outlined,
                    'Wipe data and start',
                    'Factory reset — cannot be undone',
                  ),
                ),
                if (canDelete) ...[
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                    value: EmulatorTileAction.delete,
                    child: _MenuRow(
                      Icons.delete_outline,
                      'Delete',
                      'Removes the emulator and its data',
                    ),
                  ),
                ],
              ],
            ),
          ],
        );

      case EmulatorRunState.starting:
        return const _PendingAction(label: 'Starting…');

      case EmulatorRunState.stopping:
        return const _PendingAction(label: 'Stopping…');

      case EmulatorRunState.running:
        return OutlinedButton.icon(
          onPressed: enabled ? onStop : null,
          icon: const Icon(Icons.stop_rounded, size: 18),
          label: const Text('Stop'),
        );
    }
  }
}

class _PendingAction extends StatelessWidget {
  const _PendingAction({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox.square(
          dimension: 13,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: theme.colorScheme.primary,
          ),
        ),
        const Gap(10),
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow(this.icon, this.label, this.subtitle);

  final IconData icon;
  final String label;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 16),
        const Gap(10),
        // Expanded, not bare: a popup menu is laid out at 256px, which the
        // subtitle does not fit on one line.
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
