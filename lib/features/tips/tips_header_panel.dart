import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../../presentation/components/eagly_dialog.dart';
import '../../presentation/theme/app_theme.dart';
import 'components/action_hint.dart';
import 'components/confirm_disable_tips.dart';
import 'components/pill_icon_button.dart';
import 'components/tips_menu_button.dart';
import 'tip.dart';
import 'tips_controller.dart';

/// Largest width the inline pill is allowed to claim in the header. It shrinks
/// to fit shorter tips and ellipsizes anything longer.
const double _maxPanelWidth = 340;

/// Below this window width the header is too cramped to spare room for tips, so
/// the panel steps aside entirely (tabs and actions take priority).
const double _minWindowWidthForTips = 820;

/// A quiet, dismissible tip pill that lives in the empty space of the app
/// header. Tapping the body opens a fuller explanation; the close button hides
/// it for the session; the ⋮ menu can turn tips off for good (behind a
/// confirmation). It deliberately mirrors the muted styling of the other header
/// actions so it never reads as a banner or nag.
class TipsHeaderPanel extends StatefulWidget {
  const TipsHeaderPanel({super.key, required this.controller});

  final TipsController controller;

  @override
  State<TipsHeaderPanel> createState() => _TipsHeaderPanelState();
}

class _TipsHeaderPanelState extends State<TipsHeaderPanel> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final tip = widget.controller.currentTip;
        final tooNarrow =
            MediaQuery.sizeOf(context).width < _minWindowWidthForTips;
        if (!widget.controller.visible || tip == null || tooNarrow) {
          return const SizedBox.shrink();
        }

        final theme = Theme.of(context);
        final accent = context.eaglyTheme.warningColor;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _maxPanelWidth),
            child: MouseRegion(
              onEnter: (_) => setState(() => _hovered = true),
              onExit: (_) => setState(() => _hovered = false),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                padding: const EdgeInsets.only(left: 10, right: 2),
                decoration: BoxDecoration(
                  color: _hovered
                      ? theme.colorScheme.surfaceContainerHighest
                      : theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: theme.colorScheme.outlineVariant.withValues(
                      alpha: _hovered ? 1 : 0.6,
                    ),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: GestureDetector(
                        onTap: () => _openDetail(context, tip),
                        behavior: HitTestBehavior.opaque,
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.lightbulb_outline_rounded,
                                size: 15,
                                color: accent,
                              ),
                              const Gap(8),
                              Flexible(
                                child: Text(
                                  tip.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const Gap(6),
                    PillIconButton(
                      icon: Icons.close_rounded,
                      tooltip: 'Hide tip',
                      onTap: widget.controller.dismissForSession,
                    ),
                    TipsMenuButton(controller: widget.controller),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _openDetail(BuildContext context, Tip tip) {
    return showTipDetailDialog(context, tip, widget.controller);
  }
}

/// Opens the fuller explanation for [tip]. The ‹ › chevrons browse the rest of
/// the pool in place — the dialog follows the controller, so it updates live
/// as the user cycles. Offers a low-key way to turn tips off from within, so a
/// user reading the detail can opt out without hunting.
Future<void> showTipDetailDialog(
  BuildContext context,
  Tip tip,
  TipsController controller,
) {
  return showEaglyDialog<void>(
    context: context,
    builder: (context) {
      return ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final current = controller.currentTip ?? tip;
          final theme = Theme.of(context);
          return EaglyDialog(
            title: current.title,
            icon: current.icon,
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  current.detail,
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
                ),
                if (current.actionHint != null) ...[
                  const Gap(16),
                  ActionHint(text: current.actionHint!),
                ],
                const Gap(24),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: () async {
                        final confirmed = await confirmDisableTips(context);
                        if (!confirmed || !context.mounted) return;
                        controller.disablePermanently();
                        Navigator.of(context).pop();
                      },
                      icon: const Icon(Icons.visibility_off_outlined, size: 16),
                      label: const Text('Turn off tips'),
                      style: TextButton.styleFrom(
                        foregroundColor: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const Spacer(),
                    if (controller.hasMultipleTips) ...[
                      IconButton(
                        tooltip: 'Previous tip',
                        onPressed: controller.showPreviousTip,
                        icon: const Icon(Icons.chevron_left_rounded),
                        iconSize: 20,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 36,
                          minHeight: 36,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Next tip',
                        onPressed: controller.showNextTip,
                        icon: const Icon(Icons.chevron_right_rounded),
                        iconSize: 20,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 36,
                          minHeight: 36,
                        ),
                      ),
                      const Gap(8),
                    ],
                    FilledButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Got it'),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      );
    },
  );
}
