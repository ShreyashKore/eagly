import 'package:flutter/material.dart';

/// Confirmation guard before tips are turned off for good. Returns true only
/// when the user explicitly confirms.
Future<bool> confirmDisableTips(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Turn off tips?'),
      content: const Text(
        "You won't see feature tips in the header anymore. "
        'You can turn them back on any time from Settings.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Turn off'),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
