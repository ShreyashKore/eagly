import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../../../presentation/theme/app_theme.dart';

/// The emphasized "how to get there" line shown inside the detail dialog.
class ActionHint extends StatelessWidget {
  const ActionHint({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final eagly = context.eaglyTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: eagly.inlineNoticeBackground,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            Icons.arrow_forward_rounded,
            size: 16,
            color: eagly.inlineNoticeForeground,
          ),
          const Gap(10),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: eagly.inlineNoticeForeground,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
