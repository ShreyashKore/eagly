import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// Renders the embedded scrcpy stream into the mirror pane. The surrounding
/// pane already provides the header / start-stop / close controls, so this is
/// just the video surface.
class ScrcpyVideoPlayer extends StatelessWidget {
  const ScrcpyVideoPlayer({super.key, required this.controller});

  final VideoPlayerController controller;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final aspectRatio = value.aspectRatio > 0 ? value.aspectRatio : 9 / 16;
        return Container(
          color: Colors.black,
          alignment: Alignment.center,
          child: AspectRatio(
            aspectRatio: aspectRatio,
            child: VideoPlayer(controller),
          ),
        );
      },
    );
  }
}
