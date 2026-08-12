import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

/// Header-styled accent pill mirroring the other header actions, tinted with the
/// primary color so an available update reads as a gentle call to action.
class UpdatePill extends StatefulWidget {
  const UpdatePill({
    super.key,
    required this.label,
    required this.tooltip,
    this.icon,
    this.busy = false,
    this.onTap,
  });

  final String label;
  final String tooltip;
  final IconData? icon;
  final bool busy;
  final VoidCallback? onTap;

  @override
  State<UpdatePill> createState() => _UpdatePillState();
}

class _UpdatePillState extends State<UpdatePill> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = scheme.onPrimaryContainer;

    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: widget.onTap == null
            ? MouseCursor.defer
            : SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(
                alpha: _hovered && widget.onTap != null ? 1 : 0.75,
              ),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: scheme.primary.withValues(alpha: 0.4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.busy)
                  SizedBox.square(
                    dimension: 13,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: foreground,
                    ),
                  )
                else if (widget.icon != null)
                  Icon(widget.icon, size: 15, color: foreground),
                const Gap(6),
                Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: foreground,
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
