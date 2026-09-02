import 'package:flutter/material.dart';

/// Applies the app-wide zoom to [child].
///
/// Zoom is a **text scale**, never a layer transform. Scaling the app with a
/// `Transform` above [MaterialApp] leaves every global coordinate scaled while
/// scroll offsets, menu anchors and drag positions stay in unscaled logical
/// pixels. Flutter mixes the two — `Scrollable`'s selection delegate adds the
/// scroll offset to a position it then maps through the layer transform — so a
/// selection drag inside a scroll view is off by `scrollOffset * (zoom - 1)`:
/// harmless at the top of a list, thousands of pixels down a long log buffer,
/// where it makes the viewport auto-scroll away under the pointer. Popup and
/// menu placement is wrong for the same reason.
///
/// A text scale keeps one coordinate space. Text scales, icons follow it
/// through `IconThemeData.applyTextScaling`, and fixed chrome dimensions
/// follow via `BuildContext.scaled`.
class AppZoom extends StatelessWidget {
  const AppZoom({super.key, required this.zoomLevel, required this.child});

  /// 1.0 is unzoomed; see `PreferencesService.zoomLevel` for the range.
  final double zoomLevel;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(zoomLevel)),
      child: child,
    );
  }
}
