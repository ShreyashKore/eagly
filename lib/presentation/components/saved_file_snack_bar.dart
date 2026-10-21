import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../../utils/file_reveal.dart';

/// Confirms that a file was written and offers the two follow-ups people
/// actually want: open it, or reveal it in the OS file manager. A
/// [SnackBarAction] only fits one action, so both buttons live inside the
/// snack bar's content row.
///
/// With [preview] (the saved image's encoded bytes, or a still from a saved
/// video, marked by [previewIsVideo]) the snack bar leads with a thumbnail of
/// it. When [previewOrigin] is the widget the picture was taken from, the
/// picture flashes there and then flies into that thumbnail.
Future<void> showSavedFileSnackBar(
  ScaffoldMessengerState messenger, {
  required String message,
  required String path,
  Uint8List? preview,
  BuildContext? previewOrigin,
  bool previewIsVideo = false,
}) async {
  // Decoded up front: the thumbnail's width follows the picture's shape, and a
  // decoded picture paints on the flight's first frame.
  final image = preview == null ? null : MemoryImage(preview);
  final size = image == null ? null : await _decodedSize(image);
  if (!messenger.mounted) return;
  final thumbnail = image == null || size == null
      ? null
      : _Preview(image, size, isVideo: previewIsVideo);

  // The flight needs its target on screen right away, so it replaces the
  // current snack bar instead of waiting for it to animate out.
  if (thumbnail != null) {
    messenger.removeCurrentSnackBar();
  } else {
    messenger.hideCurrentSnackBar();
  }
  final shown = messenger.showSnackBar(
    SnackBar(
      duration: const Duration(seconds: 8),
      content: _SavedFileContent(
        message: message,
        path: path,
        preview: thumbnail,
      ),
    ),
  );
  if (image != null) unawaited(shown.closed.then((_) => image.evict()));

  if (thumbnail != null && previewOrigin != null && previewOrigin.mounted) {
    _flyIn(previewOrigin, thumbnail);
  }
}

/// The picture's size in pixels, or null when it can't be decoded. Leaves
/// the decoded picture in the image cache for the thumbnail and the flight.
Future<Size?> _decodedSize(ImageProvider image) {
  final completer = Completer<Size?>();
  final stream = image.resolve(ImageConfiguration.empty);
  late final ImageStreamListener listener;
  listener = ImageStreamListener(
    (info, _) {
      completer.complete(
        Size(info.image.width.toDouble(), info.image.height.toDouble()),
      );
      info.dispose();
      stream.removeListener(listener);
    },
    onError: (_, _) {
      completer.complete(null);
      stream.removeListener(listener);
    },
  );
  stream.addListener(listener);
  return completer.future;
}

/// A saved picture shown in the snack bar, and what its flight needs to find
/// the thumbnail.
class _Preview(
  final MemoryImage image,
  final Size size, {
  required final bool isVideo,
}) {
  final GlobalKey thumbnailKey = GlobalKey(debugLabel: 'SavedFileThumbnail');

  /// False while the flight is on its way; the thumbnail stays empty until
  /// the picture lands in it.
  final ValueNotifier<bool> landed = ValueNotifier(true);
}

/// Where [context]'s box sits in [ancestor]'s coordinates, or null when it
/// isn't laid out on screen.
Rect? _rectIn(RenderObject ancestor, BuildContext? context) {
  final box = context?.findRenderObject();
  if (box is! RenderBox || !box.attached || !box.hasSize) return null;
  return MatrixUtils.transformRect(
    box.getTransformTo(ancestor),
    Offset.zero & box.size,
  );
}

void _flyIn(BuildContext origin, _Preview preview) {
  if (MediaQuery.maybeDisableAnimationsOf(origin) ?? false) return;
  final overlay = Overlay.maybeOf(origin, rootOverlay: true);
  final overlayBox = overlay?.context.findRenderObject();
  if (overlay == null || overlayBox == null) return;
  final area = _rectIn(overlayBox, origin);
  if (area == null || area.isEmpty) return;
  // The surface letterboxes the picture; start from the picture itself.
  final fitted = applyBoxFit(BoxFit.contain, preview.size, area.size);
  final from = Alignment.center.inscribe(fitted.destination, area);

  preview.landed.value = false;
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _PreviewFlight(
      preview: preview,
      from: from,
      overlayBox: overlayBox,
      onDone: () {
        preview.landed.value = true;
        entry
          ..remove()
          ..dispose();
      },
    ),
  );
  overlay.insert(entry);
}

const _thumbnailRadius = 6.0;

/// The picture flashing where it was taken, then shrinking into the
/// snack bar's thumbnail. Follows the thumbnail while the snack bar settles,
/// and fades out where it is if the snack bar goes away first.
class const _PreviewFlight({
  required final _Preview preview,
  required final Rect from,
  required final RenderObject overlayBox,
  required final VoidCallback onDone,
}) extends StatefulWidget {
  @override
  State<_PreviewFlight> createState() => _PreviewFlightState();
}

class _PreviewFlightState extends State<_PreviewFlight>
    with TickerProviderStateMixin {
  late final AnimationController _flash = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );
  late final AnimationController _move = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 480),
  );
  Rect? _to;

  @override
  void initState() {
    super.initState();
    _flash.forward().whenComplete(
      () => _move.forward().whenComplete(widget.onDone),
    );
  }

  @override
  void dispose() {
    _flash.dispose();
    _move.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: Listenable.merge([_flash, _move]),
        builder: (context, _) {
          final lift = Curves.easeOut.transform(_flash.value);
          final t = Curves.easeInOutCubic.transform(_move.value);
          _to =
              _rectIn(
                widget.overlayBox,
                widget.preview.thumbnailKey.currentContext,
              ) ??
              _to;
          final to = _to;
          // Picked up: a little smaller than the picture on the surface.
          final lifted = Rect.fromCenter(
            center: widget.from.center,
            width: widget.from.width * (1 - 0.04 * lift),
            height: widget.from.height * (1 - 0.04 * lift),
          );
          final rect = to == null ? lifted : Rect.lerp(lifted, to, t)!;
          final radius = BorderRadius.circular(
            lerpDouble(0, _thumbnailRadius, lift * 0.5 + t * 0.5)!,
          );

          return Stack(
            children: [
              Positioned.fromRect(
                rect: rect,
                child: Opacity(
                  opacity: to == null ? 1 - t : 1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: radius,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: 0.35 * lift * (1 - t),
                          ),
                          blurRadius: 24,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: radius,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image(
                            image: widget.preview.image,
                            fit: BoxFit.fill,
                            gaplessPlayback: true,
                            filterQuality: FilterQuality.medium,
                          ),
                          // The shutter: white over the picture, fading out.
                          ColoredBox(
                            color: Colors.white.withValues(
                              alpha: 0.7 * (1 - lift),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class const _SavedFileContent({
  required final String message,
  required final String path,
  final _Preview? preview,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final buttonStyle = TextButton.styleFrom(
      foregroundColor: scheme.inversePrimary,
      minimumSize: const Size(0, 32),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );

    return Row(
      children: [
        if (preview case final preview?) ...[
          _Thumbnail(preview: preview, onTap: () => openPathExternally(path)),
          const Gap(12),
        ],
        Expanded(
          child: Tooltip(
            message: path,
            child: Text(message, maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
        ),
        TextButton(
          style: buttonStyle,
          onPressed: () => openPathExternally(path),
          child: const Text('Open'),
        ),
        TextButton(
          style: buttonStyle,
          onPressed: () => revealPathInFileManager(path),
          child: const Text('Show in folder'),
        ),
      ],
    );
  }
}

/// The saved picture, fitted into a small box, with a play mark on a video's
/// still; clicking it opens the file.
class const _Thumbnail({
  required final _Preview preview,
  required final VoidCallback onTap,
}) extends StatelessWidget {
  static const _bounds = Size(112, 72);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final size = applyBoxFit(BoxFit.contain, preview.size, _bounds).destination;
    final radius = BorderRadius.circular(_thumbnailRadius);

    return Tooltip(
      message: 'Open',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: ValueListenableBuilder<bool>(
            valueListenable: preview.landed,
            builder: (context, landed, child) =>
                Opacity(opacity: landed ? 1 : 0, child: child),
            child: Container(
              key: preview.thumbnailKey,
              width: size.width,
              height: size.height,
              foregroundDecoration: BoxDecoration(
                borderRadius: radius,
                border: Border.all(
                  color: scheme.onInverseSurface.withValues(alpha: 0.24),
                ),
              ),
              child: ClipRRect(
                borderRadius: radius,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image(
                      image: preview.image,
                      fit: BoxFit.fill,
                      gaplessPlayback: true,
                      filterQuality: FilterQuality.medium,
                    ),
                    if (preview.isVideo)
                      const Center(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Color(0x99000000),
                            shape: BoxShape.circle,
                          ),
                          child: Padding(
                            padding: EdgeInsets.all(2),
                            child: Icon(
                              Icons.play_arrow_rounded,
                              size: 18,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
