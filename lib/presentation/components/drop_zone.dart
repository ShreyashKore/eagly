import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// A region inside the device screen that handles files dropped onto it
/// itself, instead of the screen-wide install-or-copy.
///
/// There is deliberately still only one `DropTarget` (on the device screen):
/// desktop_drop broadcasts every drag event to every mounted target whose
/// bounds contain the pointer, so a nested target would receive the same drop
/// as its ancestor and both would act on it. The screen's target asks
/// [DropZone.at] which zone — if any — is under the pointer and hands the
/// drop to it.
class const DropZone({
  super.key,

  /// Receives the dropped local paths (never empty).
  required final Future<void> Function(List<String> paths) onDrop,

  /// Builds the zone; [isHovered] is true while files are dragged over it.
  required final Widget Function(BuildContext context, bool isHovered) builder,
}) extends StatefulWidget {
  /// The zone under [globalPosition], found by hit-testing the view the way a
  /// pointer event would — so a zone hidden offstage or covered by something
  /// opaque doesn't claim the drop.
  static DropZoneHandle? at(BuildContext context, Offset globalPosition) {
    final result = HitTestResult();
    WidgetsBinding.instance.hitTestInView(
      result,
      globalPosition,
      View.of(context).viewId,
    );
    for (final entry in result.path) {
      final target = entry.target;
      if (target is RenderMetaData) {
        final zone = target.metaData;
        if (zone is DropZoneHandle) return zone;
      }
    }
    return null;
  }

  @override
  State<DropZone> createState() => _DropZoneState();
}

/// What the device screen's drop target drives on the zone under the pointer.
abstract interface class DropZoneHandle {
  set isHovered(bool value);

  Future<void> drop(List<String> paths);
}

class _DropZoneState extends State<DropZone> implements DropZoneHandle {
  bool _isHovered = false;

  @override
  set isHovered(bool value) {
    if (value == _isHovered || !mounted) return;
    setState(() => _isHovered = value);
  }

  @override
  Future<void> drop(List<String> paths) {
    isHovered = false;
    return widget.onDrop(paths);
  }

  @override
  Widget build(BuildContext context) {
    return MetaData(
      metaData: this,
      // Translucent: the zone must be found over empty space too, not only
      // where one of its descendants happens to paint.
      behavior: HitTestBehavior.translucent,
      child: widget.builder(context, _isHovered),
    );
  }
}
