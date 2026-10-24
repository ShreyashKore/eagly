import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../../../services/preferences_service.dart';

/// Says, before an iPhone mirror starts on macOS, why macOS has Eagly
/// ask for camera access, and that nothing leaves the Mac.
/// Pops true to start the mirror. Ticking "Don't show this again" sets
/// [PreferencesService.skipIosCaptureNotice] when the mirror is started.
class const IosCaptureNoticeDialog({super.key}) extends StatefulWidget {
  @override
  State<IosCaptureNoticeDialog> createState() => _IosCaptureNoticeDialogState();
}

class _IosCaptureNoticeDialogState extends State<IosCaptureNoticeDialog> {
  bool _dontShowAgain = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      scrollable: true,
      icon: Icon(Icons.privacy_tip_outlined, color: theme.colorScheme.primary),
      title: const Text('Why Eagly asks for camera access'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "macOS hands over a USB iPhone's screen the way QuickTime "
              'Player gets it: as a capture device that carries the '
              "phone's picture and sound, like a camera. That is why:",
              style: theme.textTheme.bodyMedium,
            ),
            const Gap(16),
            const _Point(
              icon: Icons.videocam_outlined,
              text:
                  'The first time, macOS asks to let Eagly use the camera. '
                  'Eagly asks for no other permission.',
            ),
            const _Point(
              icon: Icons.mic_none_rounded,
              text:
                  'While mirroring, the iPhone may show its microphone '
                  'indicator. It goes off when the mirror stops.',
            ),
            Text(
              "Eagly reads only the iPhone's screen. It never turns on this "
              "Mac's camera or microphone, and takes no sound from the "
              'iPhone.',
              style: theme.textTheme.bodyMedium,
            ),
            const Gap(12),
            Text(
              'Everything stays on this Mac: the picture goes from the cable '
              'to this window, is sent nowhere, and is saved only when you '
              'take a screenshot or a recording.',
              style: theme.textTheme.bodyMedium,
            ),
            const Gap(12),
            CheckboxListTile(
              value: _dontShowAgain,
              onChanged: (value) =>
                  setState(() => _dontShowAgain = value ?? false),
              title: const Text("Don't show this again"),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (_dontShowAgain) PreferencesService.skipIosCaptureNotice = true;
            Navigator.of(context).pop(true);
          },
          child: const Text('Start mirror'),
        ),
      ],
    );
  }
}

class const _Point({required final IconData icon, required final String text})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
          const Gap(10),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
