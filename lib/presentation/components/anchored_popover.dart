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
/// Popovers are not nested: a click inside a second popover would count as
/// outside the first. Choices inside a card are shown inline instead.
class AnchoredPopover extends StatefulWidget {
  const AnchoredPopover({
    super.key,
    required this.controller,
    required this.popoverBuilder,
    required this.child,
    this.width = 300,
    this.onClosed,
  });

  final PopoverController controller;
  final WidgetBuilder popoverBuilder;
  final Widget child;
  final double width;
  final VoidCallback? onClosed;

  @override
  State<AnchoredPopover> createState() => _AnchoredPopoverState();
}

class _AnchoredPopoverState extends State<AnchoredPopover> {
  final OverlayPortalController _portal = OverlayPortalController();
  final LayerLink _link = LayerLink();
  final Object _tapGroup = Object();
  bool _alignRight = false;

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
      final box = context.findRenderObject() as RenderBox?;
      final left = box != null && box.hasSize
          ? box.localToGlobal(Offset.zero).dx
          : 0.0;
      _alignRight = left + widget.width > MediaQuery.sizeOf(context).width - 8;
      _portal.show();
    } else {
      _portal.hide();
      widget.onClosed?.call();
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _link,
      child: TapRegion(
        groupId: _tapGroup,
        child: OverlayPortal(
          controller: _portal,
          overlayChildBuilder: _buildPopover,
          child: widget.child,
        ),
      ),
    );
  }

  Widget _buildPopover(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Positioned(
      width: widget.width,
      child: CompositedTransformFollower(
        link: _link,
        showWhenUnlinked: false,
        targetAnchor: _alignRight
            ? Alignment.bottomRight
            : Alignment.bottomLeft,
        followerAnchor: _alignRight ? Alignment.topRight : Alignment.topLeft,
        offset: const Offset(0, 6),
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
                  child: widget.popoverBuilder(context),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
