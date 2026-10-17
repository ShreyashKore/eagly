import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../../../data/device.dart';
import '../../../session/device_session_controller.dart';

/// Floating card that slides in at the bottom of the device screen while an
/// app install runs, so a dropped or picked APK / IPA visibly *does*
/// something: the app's name, the target device, the time spent so far and
/// an indeterminate progress bar. The install tools report no percentage, so
/// the bar shows activity, not progress.
///
/// Rebuilds from [session] itself; place it in a [Stack] over the panes.
class InstallProgressBanner extends StatelessWidget {
  const InstallProgressBanner({super.key, required this.session});

  final DeviceSessionController session;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final installing = session.isInstallingApp;
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.4),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          ),
          child: installing
              ? _InstallCard(
                  key: const ValueKey('installing'),
                  appName: session.installingAppName,
                  deviceName: session.device.displayName,
                  platform: session.platform,
                  startedAt: session.installStartedAt ?? DateTime.now(),
                )
              : const SizedBox.shrink(key: ValueKey('idle')),
        );
      },
    );
  }
}

class _InstallCard extends StatefulWidget {
  const _InstallCard({
    super.key,
    required this.appName,
    required this.deviceName,
    required this.platform,
    required this.startedAt,
  });

  final String? appName;
  final String deviceName;
  final DevicePlatform platform;
  final DateTime startedAt;

  @override
  State<_InstallCard> createState() => _InstallCardState();
}

class _InstallCardState extends State<_InstallCard> {
  late final Timer _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(
      const Duration(seconds: 1),
      (_) => setState(() {}),
    );
  }

  @override
  void dispose() {
    _ticker.cancel();
    super.dispose();
  }

  static String _formatElapsed(Duration elapsed) {
    final minutes = elapsed.inMinutes;
    final seconds = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final elapsed = DateTime.now().difference(widget.startedAt);
    final platformIcon = widget.platform == DevicePlatform.android
        ? Icons.android_rounded
        : Icons.phone_iphone_rounded;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Material(
        color: cs.surfaceContainerHigh,
        elevation: 6,
        shadowColor: cs.shadow.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: Semantics(
          liveRegion: true,
          label:
              'Installing ${widget.appName ?? 'app'} on ${widget.deviceName}',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 16, 12),
                child: Row(
                  children: [
                    SizedBox.square(
                      dimension: 34,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Positioned.fill(
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: cs.primary,
                              backgroundColor: cs.primary.withValues(
                                alpha: 0.15,
                              ),
                            ),
                          ),
                          Icon(platformIcon, size: 18, color: cs.primary),
                        ],
                      ),
                    ),
                    const Gap(12),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Installing ${widget.appName ?? 'app'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Gap(2),
                          Text(
                            'on ${widget.deviceName}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Gap(16),
                    Text(
                      _formatElapsed(elapsed),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              LinearProgressIndicator(
                minHeight: 3,
                color: cs.primary,
                backgroundColor: cs.primary.withValues(alpha: 0.12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
