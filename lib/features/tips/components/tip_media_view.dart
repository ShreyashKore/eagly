import 'package:flutter/material.dart';

import '../tip.dart';

/// The clip at the top of the tip dialog.
///
/// Holds the clip's box with a quiet placeholder while it downloads, fades it
/// in once the first frame decodes, and disappears entirely if it can't load
/// (offline, CDN down) — the tip still reads fine as text. Nothing is fetched
/// until the dialog opens.
class const TipMediaView({super.key, required final TipMedia media})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final radius = BorderRadius.circular(10);

    Widget framed(Widget child) => Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: AspectRatio(
        aspectRatio: media.aspectRatio,
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: ClipRRect(borderRadius: radius, child: child),
        ),
      ),
    );

    return Image.network(
      media.url,
      key: ValueKey(media.url),
      fit: BoxFit.cover,
      filterQuality: FilterQuality.medium,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        return framed(
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: frame == null && !wasSynchronouslyLoaded
                ? ColoredBox(
                    key: const ValueKey('placeholder'),
                    color: theme.colorScheme.surfaceContainerHighest,
                    child: const SizedBox.expand(),
                  )
                : KeyedSubtree(key: const ValueKey('clip'), child: child),
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
    );
  }
}
