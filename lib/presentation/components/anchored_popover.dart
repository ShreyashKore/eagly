import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Opens and closes an [AnchoredPopover].
class PopoverController extends ChangeNotifier {
  bool _isOpen = false;
  bool get isOpen => _isOpen;

  void open() {
    if (_isOpen) return;
    _isOpen = true;
    notifyListeners();
  }

  void close() {
    if (!_isOpen) return;
    _isOpen = false;
    notifyListeners();
  }

  void toggle() => _isOpen ? close() : open();
}

/// A rounded card that floats below [child] while [controller] is open — the
/// Notion-style popover the log filter bar is built from.
///
/// It closes on Escape or on a click outside both the card and [child] (a
/// click on [child] is left to [child], so a toggle button can toggle), and
/// reports every close through [onClosed]. When the card would run off the
/// right edge of the window it is anchored to [child]'s right edge instead.
///
/// The card is placed with [OverlayPortal.overlayChildLayoutBuilder], not a
/// [CompositedTransformFollower]: tooltips (and anything else built on the
/// layout builder) assert when they sit under a follower.
///
/// Popovers are not nested: a click inside a second popover would count as
/// outside the first. Choices inside a card are shown inline instead.
///
/// Text fields in the card or the anchor take [textContextMenuBuilder] as
/// their `contextMenuBuilder`, or a click in their right-click menu closes the
/// card.
class const AnchoredPopover({
  super.key,
  required final PopoverController controller,
  required final WidgetBuilder popoverBuilder,
  required final Widget child,
  final double width = 300,
  final VoidCallback? onClosed,

  /// The [TapRegion] group the anchor and card share. Pass the same object as
  /// a text field's `groupId` inside the anchor so a click in the card doesn't
  /// take the field's focus.
  final Object? tapGroupId,
}) extends StatefulWidget {
  /// A text field `contextMenuBuilder` for fields in a card or its anchor.
  ///
  /// The default right-click menu sits in the root overlay, outside every
  /// [TapRegion] but the text field one, so choosing Paste in it counted as a
  /// click outside the card and closed it. This puts the menu in the field's
  /// group and the enclosing card's group too.
  static Widget textContextMenuBuilder(
    BuildContext context,
    EditableTextState editableTextState,
  ) {
    Widget menu = AdaptiveTextSelectionToolbar.editableText(
      editableTextState: editableTextState,
    );
    final groups = {
      editableTextState.widget.groupId,
      ?editableTextState.context
          .getInheritedWidgetOfExactType<_PopoverTapGroup>()
          ?.groupId,
    };
    for (final group in groups) {
      menu = TapRegion(groupId: group, child: menu);
    }
    return menu;
  }

  @override
  State<AnchoredPopover> createState() => _AnchoredPopoverState();
}

/// Tells [AnchoredPopover.textContextMenuBuilder] which card a field is in.
class const _PopoverTapGroup({
  required final Object groupId,
  required super.child,
}) extends InheritedWidget {
  @override
  bool updateShouldNotify(_PopoverTapGroup oldWidget) =>
      groupId != oldWidget.groupId;
}

class _AnchoredPopoverState extends State<AnchoredPopover> {
  final OverlayPortalController _portal = OverlayPortalController();
  late final Object _ownTapGroup = Object();
  Object get _tapGroup => widget.tapGroupId ?? _ownTapGroup;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_sync);
    if (widget.controller.isOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
    }
  }

  @override
  void didUpdateWidget(covariant AnchoredPopover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_sync);
      widget.controller.addListener(_sync);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_sync);
    super.dispose();
  }

  void _sync() {
    if (!mounted) return;
    final open = widget.controller.isOpen;
    if (open == _portal.isShowing) return;
    if (open) {
      _portal.show();
    } else {
      _portal.hide();
      widget.onClosed?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    return TapRegion(
      groupId: _tapGroup,
      child: OverlayPortal.overlayChildLayoutBuilder(
        controller: _portal,
        overlayChildBuilder: _buildPopover,
        child: widget.child,
      ),
    );
  }

  Widget _buildPopover(BuildContext context, OverlayChildLayoutInfo info) {
    if (info.childPaintTransform.determinant() == 0) {
      return const SizedBox.shrink(); // The anchor isn't visible.
    }
    final colorScheme = Theme.of(context).colorScheme;
    return CustomSingleChildLayout(
      delegate: _PopoverLayout(
        anchor: MatrixUtils.transformRect(
          info.childPaintTransform,
          Offset.zero & info.childSize,
        ),
        width: widget.width,
      ),
      child: TapRegion(
        groupId: _tapGroup,
        onTapOutside: (_) => widget.controller.close(),
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape):
                widget.controller.close,
          },
          child: FocusScope(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOutCubic,
              builder: (context, t, child) => Opacity(
                opacity: t,
                child: Transform.translate(
                  offset: Offset(0, (1 - t) * -4),
                  child: child,
                ),
              ),
              child: Material(
                color: colorScheme.surfaceContainerLow,
                elevation: 8,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: _PopoverTapGroup(
                  groupId: _tapGroup,
                  child: Builder(builder: widget.popoverBuilder),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Puts the card [gap] below [anchor], left-aligned with it — or right-aligned
/// when that would run off the overlay — and caps its height to the room left
/// below.
class const _PopoverLayout({
  required final Rect anchor,
  required final double width,
}) extends SingleChildLayoutDelegate {
  static const double gap = 6;
  static const double margin = 8;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final cardWidth = math.min(width, constraints.maxWidth - 2 * margin);
    return BoxConstraints(
      minWidth: math.max(0, cardWidth),
      maxWidth: math.max(0, cardWidth),
      maxHeight: math.max(
        0,
        constraints.maxHeight - anchor.bottom - gap - margin,
      ),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final fitsLeftAligned =
        anchor.left + childSize.width <= size.width - margin;
    final left = fitsLeftAligned
        ? anchor.left
        : math.max(margin, anchor.right - childSize.width);
    return Offset(left, anchor.bottom + gap);
  }

  @override
  bool shouldRelayout(_PopoverLayout oldDelegate) =>
      anchor != oldDelegate.anchor || width != oldDelegate.width;
}
