import 'package:flutter/material.dart';

import '../../utils/file_reveal.dart';

/// Confirms that a file was written and offers the two follow-ups people
/// actually want: open it, or reveal it in the OS file manager. A
/// [SnackBarAction] only fits one action, so both buttons live inside the
/// snack bar's content row.
void showSavedFileSnackBar(
  ScaffoldMessengerState messenger, {
  required String message,
  required String path,
}) {
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 8),
        content: _SavedFileContent(message: message, path: path),
      ),
    );
}

class _SavedFileContent extends StatelessWidget {
  const _SavedFileContent({required this.message, required this.path});

  final String message;
  final String path;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final buttonStyle = TextButton.styleFrom(
      foregroundColor: scheme.inversePrimary,
      minimumSize: const Size(0, 32),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );

    return Row(
      children: [
        Expanded(
          child: Tooltip(
            message: path,
            child: Text(message, maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
        ),
        TextButton(
          style: buttonStyle,
          onPressed: () => openPathExternally(path),
          child: const Text('Open'),
        ),
        TextButton(
          style: buttonStyle,
          onPressed: () => revealPathInFileManager(path),
          child: const Text('Show in folder'),
        ),
      ],
    );
  }
}
