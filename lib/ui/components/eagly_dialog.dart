import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

/// Standard dialog shell for Eagly's desktop UI.
///
/// Provides a consistent header (optional leading icon, title, optional
/// header actions and a close button on the top right), a divider and a
/// content area that is sized for a desktop window rather than a full screen.
///
/// Use [showEaglyDialog] to present one.
class EaglyDialog extends StatelessWidget {
  const EaglyDialog({
    super.key,
    required this.title,
    required this.child,
    this.icon,
    this.headerActions = const [],
    this.width = 720,
    this.height,
    this.contentPadding = const EdgeInsets.fromLTRB(24, 20, 24, 24),
  });

  /// Title shown in the header.
  final String title;

  /// Main dialog body. Sized to fill the available content area, so it should
  /// manage its own scrolling when it can overflow.
  final Widget child;

  /// Optional leading icon shown before the [title].
  final IconData? icon;

  /// Optional widgets placed in the header before the close button.
  final List<Widget> headerActions;

  /// Preferred dialog width. Clamped to the available screen width.
  final double width;

  /// Optional fixed content height. When null the dialog shrinks to fit its
  /// content (clamped to the available screen height).
  final double? height;

  /// Padding around [child].
  final EdgeInsetsGeometry contentPadding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);
    final maxWidth = media.size.width - 48;
    final maxHeight = media.size.height - 48;

    return Dialog(
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: width < maxWidth ? width : maxWidth,
          maxHeight: maxHeight,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 12, 16),
              child: Row(
                children: [
                  if (icon != null) ...[
                    Icon(icon, color: theme.colorScheme.primary),
                    const Gap(12),
                  ],
                  Expanded(
                    child: Text(title, style: theme.textTheme.titleLarge),
                  ),
                  ...headerActions,
                  if (headerActions.isNotEmpty) const Gap(4),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: theme.colorScheme.outlineVariant),
            Flexible(
              child: SizedBox(
                width: double.infinity,
                height: height,
                child: Padding(padding: contentPadding, child: child),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Presents [builder] inside an [EaglyDialog]-friendly [showDialog] call.
Future<T?> showEaglyDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: builder,
  );
}
