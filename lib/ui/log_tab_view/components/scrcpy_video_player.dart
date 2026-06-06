import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// Renders the embedded scrcpy stream into the mirror pane. The surrounding
/// pane already provides the header / start-stop / close controls, so this is
/// just the video surface.
class ScrcpyVideoPlayer extends StatelessWidget {
  const ScrcpyVideoPlayer({super.key, required this.controller});

  final VideoController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      child: Video(
        controller: controller,
        controls: NoVideoControls,
        fit: BoxFit.contain,
      ),
    );
  }
}
