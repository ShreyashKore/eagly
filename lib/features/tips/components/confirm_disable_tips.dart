import 'package:flutter/material.dart';

import '../../../presentation/components/confirm_dialog.dart';

/// Confirmation guard before tips are turned off for good. Returns true only
/// when the user explicitly confirms.
Future<bool> confirmDisableTips(BuildContext context) => showConfirmDialog(
  context,
  title: 'Turn off tips?',
  message:
      "You won't see feature tips in the header anymore. "
      'You can turn them back on any time from Settings.',
  confirmLabel: 'Turn off',
);
