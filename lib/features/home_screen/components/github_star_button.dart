import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../constants/app_constants.dart';
import '../../../constants/local_assets.dart';
import '../../../utils/url_launcher.dart';
import '../../../presentation/components/hover_builder.dart';

/// A quiet "Star" pill linking to the GitHub repo. The word invites a star
/// without the loud styling of a promo banner — it sits among the other muted
/// header actions and only warms up on hover.
class const GitHubStarButton({super.key}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: 'Eagly on GitHub',
      child: HoverBuilder(
        cursor: SystemMouseCursors.click,
        builder: (context, hovered) => GestureDetector(
          onTap: () => openExternalUrl(AppConstants.repoUrl),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: hovered
                  ? theme.colorScheme.surfaceContainerHighest
                  : theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(
                  alpha: hovered ? 1 : 0.6,
                ),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SvgPicture.asset(
                  LocalAssets.githubIcon,
                  width: 15,
                  height: 15,
                  colorFilter: ColorFilter.mode(
                    hovered
                        ? theme.colorScheme.onSurface
                        : theme.colorScheme.onSurfaceVariant,
                    BlendMode.srcIn,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
