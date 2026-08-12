import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../../../session/device_session_controller.dart';
import '../../../presentation/components/device_presentation.dart';
import 'connection_dot.dart';
import 'context_menu_helper.dart';
import 'entrance_reveal.dart';
import 'workspace_label.dart';

class DeviceTab extends StatefulWidget {
  const DeviceTab({
    super.key,
    required this.session,
    required this.selected,
    required this.animateIn,
    required this.onSelect,
    required this.onClose,
  });

  final DeviceSessionController session;
  final bool selected;

  /// When true the tab plays a snappy entrance and, shortly after, a one-shot
  /// highlight wave to draw attention to the freshly-connected device.
  final bool animateIn;
  final VoidCallback onSelect;
  final VoidCallback? onClose;

  @override
  State<DeviceTab> createState() => _DeviceTabState();
}

class _DeviceTabState extends State<DeviceTab> with TickerProviderStateMixin {
  late final AnimationController _enter;
  late final AnimationController _wave;
  Timer? _waveTimer;

  @override
  void initState() {
    super.initState();
    _enter = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 340),
    );
    _wave = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );

    if (widget.animateIn) {
      _enter.forward();
      // Let the entrance settle, then sweep the highlight wave across the tab.
      _waveTimer = Timer(const Duration(milliseconds: 480), () {
        if (mounted) _wave.forward(from: 0);
      });
    } else {
      _enter.value = 1;
    }
  }

  @override
  void dispose() {
    _waveTimer?.cancel();
    _enter.dispose();
    _wave.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListenableBuilder(
      listenable: widget.session,
      builder: (context, _) {
        final session = widget.session;
        final selected = widget.selected;
        final onClose = widget.onClose;
        final device = session.device;
        final isWorkspace = session.isImportedWorkspace;
        final background = selected
            ? theme.colorScheme.surface
            : Colors.transparent;

        final label = device.displayLabel;
        final tooltipMessage = isWorkspace
            ? 'Imported log files'
            : [
                label.primary,
                label.secondary,
              ].whereType<String>().join('  ·  ');

        final tab = GestureDetector(
          onSecondaryTapUp: (details) => showTabContextMenu(
            context,
            details.globalPosition,
            onClose: onClose,
          ),
          child: Tooltip(
            message: tooltipMessage,
            waitDuration: const Duration(milliseconds: 600),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 7),
              child: Stack(
                children: [
                  Material(
                    color: background,
                    borderRadius: BorderRadius.circular(8),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: widget.onSelect,
                      mouseCursor: SystemMouseCursors.click,
                      child: Container(
                        padding: const EdgeInsets.only(
                          left: 12,
                          right: 6,
                          top: 8,
                          bottom: 8,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: selected
                                ? theme.colorScheme.outlineVariant
                                : Colors.transparent,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isWorkspace)
                              WorkspaceLabel(theme: theme)
                            else ...[
                              ConnectionDot(connected: device.isConnected),
                              const Gap(6),
                              DeviceSelectionLabel(
                                device: device,
                                maxWidth: 160,
                                textStyle: theme.textTheme.bodyMedium,
                                secondaryTextStyle: theme.textTheme.labelSmall,
                                iconSize: 16,
                              ),
                            ],
                            if (onClose != null) ...[
                              const Gap(4),
                              IconButton(
                                tooltip: 'Close tab',
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                mouseCursor: SystemMouseCursors.click,
                                constraints: const BoxConstraints(
                                  minWidth: 28,
                                  minHeight: 28,
                                ),
                                iconSize: 16,
                                onPressed: onClose,
                                icon: const Icon(Icons.close),
                              ),
                            ] else
                              const Gap(6),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: AnimatedBuilder(
                        animation: _wave,
                        builder: (context, _) {
                          if (_wave.value == 0 || _wave.value == 1) {
                            return const SizedBox.shrink();
                          }
                          return CustomPaint(
                            painter: _HighlightWavePainter(
                              progress: _wave.value,
                              color: theme.colorScheme.primary,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );

        return EntranceReveal(animation: _enter, child: tab);
      },
    );
  }
}

/// Paints a one-shot shimmer band that sweeps across the tab plus a soft glow
/// border that pulses in and out — the "highlight wave" for a new device.
class _HighlightWavePainter extends CustomPainter {
  _HighlightWavePainter({required this.progress, required this.color});

  /// 0 → 1 over the life of the wave.
  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(8),
    );

    // Fade the whole effect in then out so it never pops on/off.
    final envelope = math.sin(progress * math.pi);

    // Sweeping shimmer band, clipped to the tab's rounded rect.
    canvas.save();
    canvas.clipRRect(rrect);
    final bandWidth = size.width * 0.55;
    final travel = size.width + bandWidth * 2;
    final centerX = travel * progress - bandWidth;
    final bandRect = Rect.fromLTWH(
      centerX - bandWidth / 2,
      0,
      bandWidth,
      size.height,
    );
    final shader = LinearGradient(
      colors: [
        color.withValues(alpha: 0),
        color.withValues(alpha: 0.30 * envelope),
        color.withValues(alpha: 0),
      ],
    ).createShader(bandRect);
    canvas.drawRect(bandRect, Paint()..shader = shader);
    canvas.restore();

    // Glow border pulse.
    canvas.drawRRect(
      rrect.deflate(0.75),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = color.withValues(alpha: 0.55 * envelope),
    );
  }

  @override
  bool shouldRepaint(_HighlightWavePainter old) =>
      old.progress != progress || old.color != color;
}
