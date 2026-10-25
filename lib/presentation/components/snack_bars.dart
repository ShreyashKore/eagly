import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Shows [message] in a snackbar, replacing the current one. Takes any
/// [BuildContext] under the app's [ScaffoldMessenger], so deeply-nested
/// content can use it.
void showMessageSnackBar(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Copies [text] and says so in a snackbar.
Future<void> copyWithToast(
  BuildContext context,
  String text,
  String message,
) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) showMessageSnackBar(context, message);
}
