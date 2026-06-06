import 'dart:async';

import 'package:flutter/material.dart';

import '../../../services/tools/screen_mirror_stream_service.dart';

class ScreenMirrorVideoWidget extends StatefulWidget {
  const ScreenMirrorVideoWidget({
    super.key,
    required this.frameStream,
    required this.onInput,
  });

  final Stream<ScreenMirrorFrame> frameStream;
  final Function(double x, double y, {bool isDown}) onInput;

  @override
  State<ScreenMirrorVideoWidget> createState() =>
      _ScreenMirrorVideoWidgetState();
}

class _ScreenMirrorVideoWidgetState extends State<ScreenMirrorVideoWidget> {
  late StreamSubscription<ScreenMirrorFrame> _subscription;
  ScreenMirrorFrame? _currentFrame;

  @override
  void initState() {
    super.initState();
    _subscription = widget.frameStream.listen(
      (frame) {
        setState(() => _currentFrame = frame);
      },
      onError: (error) {
        // Stream ended or error occurred
      },
    );
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_currentFrame == null) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    return GestureDetector(
      onTapDown: (details) {
        widget.onInput(details.localPosition.dx, details.localPosition.dy,
            isDown: true);
      },
      onTapUp: (details) {
        widget.onInput(details.localPosition.dx, details.localPosition.dy,
            isDown: false);
      },
      child: Container(
        color: Colors.black,
        child: _buildFrame(_currentFrame!),
      ),
    );
  }

  Widget _buildFrame(ScreenMirrorFrame frame) {
    return CustomPaint(
      painter: _FramePainter(frame),
      size: Size.infinite,
    );
  }
}

class _FramePainter extends CustomPainter {
  _FramePainter(this.frame);

  final ScreenMirrorFrame frame;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = Colors.black87,
    );

    final textPainter = TextPainter(
      text: TextSpan(
        text: 'Video: ${frame.width}x${frame.height}',
        style: const TextStyle(color: Colors.white, fontSize: 16),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, const Offset(20, 20));
  }

  @override
  bool shouldRepaint(_FramePainter oldDelegate) {
    return frame != oldDelegate.frame;
  }
}
