import 'package:flutter/material.dart';

import '../../../../presentation/theme/app_theme.dart';

/// Centered notice shown when logs are flowing but the active filter hides
/// all of them. Offers a one-tap filter reset.
class NoFilteredLogsNotice extends StatelessWidget {
  const NoFilteredLogsNotice({super.key, required this.onClearFilter});

  final VoidCallback onClearFilter;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.center,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Material(
          color: context.eaglyTheme.inlineNoticeBackground,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'No logs match your filter, but logs are being generated.',
                  style: TextStyle(
                    color: context.eaglyTheme.inlineNoticeForeground,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: onClearFilter,
                  style: TextButton.styleFrom(
                    foregroundColor:
                        context.eaglyTheme.inlineNoticeForeground,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    textStyle: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  child: const Text('Clear filter'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
