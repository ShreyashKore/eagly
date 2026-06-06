import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

class ScrcpyVideoPlayer extends StatefulWidget {
  const ScrcpyVideoPlayer({
    super.key,
    required this.player,
    required this.deviceName,
    required this.onClose,
  });

  final Player player;
  final String deviceName;
  final VoidCallback onClose;

  @override
  State<ScrcpyVideoPlayer> createState() => _ScrcpyVideoPlayerState();
}

class _ScrcpyVideoPlayerState extends State<ScrcpyVideoPlayer> {
  late VideoController _videoController;

  @override
  void initState() {
    super.initState();
    _videoController = VideoController(widget.player);
  }

  @override
  void dispose() {
    // VideoController is managed by Player, no explicit dispose needed
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header
        Container(
          height: 48,
          padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            border: Border(
              bottom: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.videocam, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Screen mirror - ${widget.deviceName}',
                  style: theme.textTheme.titleSmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                tooltip: 'Close',
                onPressed: widget.onClose,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        // Video player
        Expanded(
          child: Container(
            color: Colors.black,
            child: Video(
              controller: _videoController,
              controls: MaterialVideoControls,
            ),
          ),
        ),
      ],
    );
  }
}
