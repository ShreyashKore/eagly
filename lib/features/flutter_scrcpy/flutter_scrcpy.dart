/// flutter_scrcpy — an embedded Android screen mirror for Flutter desktop.
///
/// A from-scratch scrcpy client parses scrcpy-server's raw H.264 socket and
/// feeds Annex-B access units to a native decoder (macOS VideoToolbox, Windows
/// & Linux FFmpeg) that composites frames into a Flutter [Texture] rendered
/// in-tree by [ScrcpyView].
///
/// This module is self-contained: it depends only on the Flutter/Dart SDK and
/// expects the host to supply an `adb` path and the bundled `scrcpy-server`
/// jar. It is structured so it can later be lifted into a standalone pub
/// package with no source changes.
library;

export 'src/scrcpy_mirror.dart'
    show ScrcpyMirror, ScrcpyMirrorSession, ScrcpyMirrorException;
export 'src/scrcpy_client.dart'
    show ScrcpyVideoOptions, ScrcpyControl, ScrcpyTouchAction, ScrcpyKey;
export 'src/scrcpy_view.dart' show ScrcpyView;
