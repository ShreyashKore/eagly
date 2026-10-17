import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../../../presentation/components/centered_state_message.dart';
import '../../../presentation/theme/app_theme.dart';
import '../../../utils/android_sdk_path.dart';

/// What the emulator list shows instead of AVDs when the SDK cannot be used.
///
/// The two ways an SDK comes up short need opposite advice, so they are two
/// different screens rather than one message with a conditional clause: a
/// missing SDK sends the user looking for one, while a missing `emulator`
/// package sends them back to the SDK they already have.
class SdkNotice extends StatelessWidget {
  const SdkNotice({super.key, required this.sdk, required this.onLocate});

  final AndroidSdkLocation sdk;

  /// Opens the folder picker. Offered from both states — a wrong-but-plausible
  /// SDK is exactly as likely as no SDK at all.
  final VoidCallback onLocate;

  @override
  Widget build(BuildContext context) {
    return switch (sdk.status) {
      AndroidSdkStatus.emulatorMissing => CenteredStateMessage(
        icon: Icons.extension_off_outlined,
        title: 'The emulator package is not installed',
        description:
            'An Android SDK is at ${sdk.sdkPath}, but it has no emulator. '
            'Install it from Android Studio’s SDK Manager, under SDK Tools.',
        footer: _LocateButton(
          onPressed: onLocate,
          label: 'Use a different SDK…',
        ),
      ),
      AndroidSdkStatus.sdkMissing => _NoSdkFound(onLocate: onLocate),
      AndroidSdkStatus.ready => const SizedBox.shrink(),
    };
  }
}

/// Names every place that was searched, rather than leaving the user to guess
/// where Eagly looked — which is the whole difficulty of a path that is only
/// wrong by one directory.
class _NoSdkFound extends StatelessWidget {
  const _NoSdkFound({required this.onLocate});

  final VoidCallback onLocate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final candidates = AndroidSdkPath.candidateSdkRoots();

    return CenteredStateMessage(
      icon: Icons.folder_off_outlined,
      title: 'No Android SDK found',
      description:
          'Eagly bundles adb, but the emulator ships with your own Android '
          'SDK. Install one through Android Studio, or point Eagly at it.',
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (candidates.isNotEmpty) ...[
            Text(
              candidates.length == 1 ? 'Looked in:' : 'Looked in, in order:',
              style: theme.textTheme.labelMedium?.copyWith(
                color: context.eaglyTheme.secondaryTextColor,
              ),
            ),
            const Gap(6),
            Container(
              constraints: const BoxConstraints(maxWidth: 420),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final candidate in candidates)
                    Tooltip(
                      message: candidate,
                      child: Text(
                        candidate,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.eaglyTheme.monoStyle.copyWith(
                          fontSize: theme.textTheme.bodySmall?.fontSize,
                          color: context.eaglyTheme.tertiaryTextColor,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const Gap(16),
          ],
          _LocateButton(onPressed: onLocate, label: 'Locate SDK…'),
        ],
      ),
    );
  }
}

class _LocateButton extends StatelessWidget {
  const _LocateButton({required this.onPressed, required this.label});

  final VoidCallback onPressed;
  final String label;

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonalIcon(
      onPressed: onPressed,
      icon: const Icon(Icons.folder_open_outlined, size: 18),
      label: Text(label),
    );
  }
}
