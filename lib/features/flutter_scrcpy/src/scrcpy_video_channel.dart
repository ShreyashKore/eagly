import 'dart:typed_data';

import 'package:flutter/services.dart';

/// Dart side of the native scrcpy video decoder (macOS VideoToolbox →
/// Flutter texture). See `macos/Runner/ScrcpyVideoPlugin.swift`.
class ScrcpyVideoChannel {
  const ScrcpyVideoChannel();

  static const MethodChannel _method = MethodChannel('flutter_scrcpy/video');
  static const BasicMessageChannel<ByteData?> _feed =
      BasicMessageChannel<ByteData?>(
        'flutter_scrcpy/video/feed',
        BinaryCodec(),
      );

  /// Registers a new decoder + texture natively and returns its texture id.
  Future<int> createTexture() async {
    final id = await _method.invokeMethod<int>('create');
    if (id == null) {
      throw StateError('Native side returned no scrcpy texture id.');
    }
    return id;
  }

  Future<void> disposeTexture(int textureId) {
    return _method.invokeMethod<void>('dispose', {'textureId': textureId});
  }

  /// Feeds one Annex-B access unit to the decoder for [textureId]. Fire and
  /// forget: messages stay ordered on the channel, and we never want to block
  /// the producer waiting on decode.
  void feed(int textureId, Uint8List payload) {
    final message = ByteData(8 + payload.length);
    message.setInt64(0, textureId, Endian.little);
    message.buffer.asUint8List().setRange(8, 8 + payload.length, payload);
    _feed.send(message);
  }
}
