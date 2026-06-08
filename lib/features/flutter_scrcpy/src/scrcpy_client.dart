import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

/// A live H.264 access unit produced by scrcpy-server.
///
/// [data] is raw Annex-B (start-code prefixed NAL units). The first packet of
/// a stream is a [isConfig] packet carrying SPS + PPS; subsequent [isKeyFrame]
/// packets are IDR frames and the rest are non-key slices.
class ScrcpyPacket {
  const ScrcpyPacket({
    required this.isConfig,
    required this.isKeyFrame,
    required this.ptsMicros,
    required this.data,
  });

  final bool isConfig;
  final bool isKeyFrame;

  /// Presentation timestamp in microseconds (0 for config packets).
  final int ptsMicros;

  /// Annex-B encoded payload.
  final Uint8List data;
}

/// Options controlling how scrcpy-server encodes the video stream.
class ScrcpyVideoOptions {
  const ScrcpyVideoOptions({
    this.codec = 'h264',
    this.maxSize,
    this.maxFps,
    this.videoBitRate,
    this.control = false,
    this.logLevel = 'info',
  });

  final String codec;
  final int? maxSize;
  final int? maxFps;
  final int? videoBitRate;
  final bool control;
  final String logLevel;
}

/// An active scrcpy video session: the parsed handshake metadata plus a stream
/// of [ScrcpyPacket]s. Call [stop] to tear everything down.
class ScrcpyStream {
  ScrcpyStream({
    required this.deviceName,
    required this.codecId,
    required this.width,
    required this.height,
    required this.packets,
    required this.control,
    required Future<int> serverExitCode,
    required Future<void> Function() onStop,
  }) : _serverExitCode = serverExitCode,
       _onStop = onStop;

  final String deviceName;
  final String codecId;

  /// Control channel for injecting input, or null if control was disabled.
  final ScrcpyControl? control;

  /// Dimensions reported in the video header. These are best-effort; the
  /// authoritative size comes from the SPS in the first config packet.
  final int width;
  final int height;

  final Stream<ScrcpyPacket> packets;
  final Future<int> _serverExitCode;
  final Future<void> Function() _onStop;

  Future<int> get serverExitCode => _serverExitCode;

  Future<void> stop() => _onStop();
}

class ScrcpyClientException implements Exception {
  const ScrcpyClientException(this.message);
  final String message;
  @override
  String toString() => 'ScrcpyClientException: $message';
}

enum ScrcpyTouchAction { down, move, up }

/// Hardware / navigation keys that can be injected into the device.
enum ScrcpyKey { back, home, appSwitch, power, volumeUp, volumeDown }

/// Encodes and sends scrcpy control messages on the control socket. Incoming
/// device→client messages (clipboard, etc.) are drained and ignored.
class ScrcpyControl {
  ScrcpyControl(this._socket) {
    _subscription = _socket.listen(
      (_) {},
      onError: (_) {},
      cancelOnError: false,
    );
  }

  final Socket _socket;
  late final StreamSubscription<Uint8List> _subscription;

  static const int _typeInjectKeycode = 0;
  static const int _typeInjectTouch = 2;
  static const int _typeBackOrScreenOn = 4;

  /// Android `KeyEvent` keycodes for the injectable [ScrcpyKey]s.
  static const Map<ScrcpyKey, int> _keycodes = {
    ScrcpyKey.home: 3, // KEYCODE_HOME
    ScrcpyKey.back: 4, // KEYCODE_BACK
    ScrcpyKey.volumeUp: 24, // KEYCODE_VOLUME_UP
    ScrcpyKey.volumeDown: 25, // KEYCODE_VOLUME_DOWN
    ScrcpyKey.power: 26, // KEYCODE_POWER
    ScrcpyKey.appSwitch: 187, // KEYCODE_APP_SWITCH (overview)
  };

  // AMOTION_EVENT_ACTION_* values.
  static const int _actionDown = 0;
  static const int _actionUp = 1;
  static const int _actionMove = 2;
  // AMOTION_EVENT_BUTTON_PRIMARY.
  static const int _buttonPrimary = 1;
  // POINTER_ID_MOUSE (-1 as u64).
  static const int _pointerIdMouse = -1;

  /// Injects a touch event. [x]/[y] are in the coordinate space described by
  /// [videoWidth]/[videoHeight]; scrcpy scales them to the real device size.
  void touch(
    ScrcpyTouchAction action, {
    required int x,
    required int y,
    required int videoWidth,
    required int videoHeight,
  }) {
    final androidAction = switch (action) {
      ScrcpyTouchAction.down => _actionDown,
      ScrcpyTouchAction.move => _actionMove,
      ScrcpyTouchAction.up => _actionUp,
    };
    final pressure = action == ScrcpyTouchAction.up ? 0 : 0xFFFF;
    final actionButton = action == ScrcpyTouchAction.move ? 0 : _buttonPrimary;
    final buttons = action == ScrcpyTouchAction.up ? 0 : _buttonPrimary;

    final msg = ByteData(32);
    var o = 0;
    msg.setUint8(o, _typeInjectTouch);
    o += 1;
    msg.setUint8(o, androidAction);
    o += 1;
    msg.setInt64(o, _pointerIdMouse);
    o += 8;
    msg.setInt32(o, x);
    o += 4;
    msg.setInt32(o, y);
    o += 4;
    msg.setUint16(o, videoWidth.clamp(1, 0xFFFF));
    o += 2;
    msg.setUint16(o, videoHeight.clamp(1, 0xFFFF));
    o += 2;
    msg.setUint16(o, pressure);
    o += 2;
    msg.setInt32(o, actionButton);
    o += 4;
    msg.setInt32(o, buttons);
    _send(msg);
  }

  /// Taps a hardware / navigation [key] as a down-then-up keypress.
  void key(ScrcpyKey key) {
    final keycode = _keycodes[key];
    if (keycode == null) return;
    _injectKeycode(_actionDown, keycode);
    _injectKeycode(_actionUp, keycode);
  }

  void _injectKeycode(int action, int keycode) {
    final msg = ByteData(14);
    var o = 0;
    msg.setUint8(o, _typeInjectKeycode);
    o += 1;
    msg.setUint8(o, action);
    o += 1;
    msg.setInt32(o, keycode);
    o += 4;
    msg.setInt32(o, 0); // repeat
    o += 4;
    msg.setInt32(o, 0); // metaState
    _send(msg);
  }

  /// Presses/releases the BACK button (also wakes the screen).
  void backOrScreenOn(ScrcpyTouchAction action) {
    final msg = ByteData(2);
    msg.setUint8(0, _typeBackOrScreenOn);
    msg.setUint8(1, action == ScrcpyTouchAction.up ? _actionUp : _actionDown);
    _send(msg);
  }

  void _send(ByteData data) {
    try {
      _socket.add(data.buffer.asUint8List(0, data.lengthInBytes));
    } catch (_) {}
  }

  Future<void> close() async {
    await _subscription.cancel();
    try {
      _socket.destroy();
    } catch (_) {}
  }
}

/// A minimal, from-scratch scrcpy client. It deploys the bundled
/// `scrcpy-server` jar, opens an adb forward tunnel, launches the server via
/// `app_process`, and parses the raw video socket into [ScrcpyPacket]s.
///
/// This deliberately bypasses the `scrcpy` desktop binary (which muxes into a
/// container and renders in its own SDL window). We want the raw encoded
/// frames so a native decoder can render them into a Flutter texture.
class ScrcpyClient {
  ScrcpyClient({
    String adbExecutablePath = 'adb',
    required String serverJarPath,
    this.onLog,
  }) : _adb = adbExecutablePath,
       _serverJar = serverJarPath;

  /// Path to the `adb` executable. Defaults to `adb` on the host PATH; pass an
  /// absolute path to use a bundled adb instead.
  final String _adb;

  /// Host-side path to the `scrcpy-server` jar to deploy to the device. The
  /// bundled jar must match [serverVersion] exactly.
  final String _serverJar;

  /// Optional sink for diagnostic + server log lines.
  final void Function(String message)? onLog;

  /// Must match the bundled `scrcpy-server` version exactly or the server
  /// aborts with a version-mismatch error.
  static const String serverVersion = '4.0';
  static const String _deviceJarPath =
      '/data/local/tmp/flutter-scrcpy-server.jar';
  static const String _serverClass = 'com.genymobile.scrcpy.Server';
  static const int _deviceNameFieldLength = 64;

  void _log(String message) => onLog?.call(message);

  Future<ScrcpyStream> connect(
    String deviceId, {
    ScrcpyVideoOptions options = const ScrcpyVideoOptions(),
  }) async {
    final jar = _serverJar;
    if (!File(jar).existsSync()) {
      throw ScrcpyClientException('scrcpy-server jar not found (path: $jar)');
    }

    // 1. Deploy the server jar (idempotent; push is fast even when present).
    final push = await Process.run(_adb, [
      '-s',
      deviceId,
      'push',
      jar,
      _deviceJarPath,
    ]);
    if (push.exitCode != 0) {
      throw ScrcpyClientException('adb push failed: ${push.stderr}');
    }

    // 2. Session id → abstract socket name (scrcpy_%08x).
    final scid = Random.secure().nextInt(0x7FFFFFFF) + 1;
    final scidHex = scid.toRadixString(16).padLeft(8, '0');
    final localName = 'scrcpy_$scidHex';

    // 3. Forward tunnel: adb picks a local TCP port (tcp:0) bound to the
    //    device-side abstract socket the server will listen on.
    final port = await _adbForward(deviceId, localName);
    _log('forward 127.0.0.1:$port -> localabstract:$localName');

    Process? server;
    Socket? videoSocket;
    Socket? controlSocket;

    Future<void> cleanup() async {
      try {
        videoSocket?.destroy();
      } catch (_) {}
      try {
        controlSocket?.destroy();
      } catch (_) {}
      try {
        server?.kill();
      } catch (_) {}
      await _adbForwardRemove(deviceId, port);
    }

    try {
      // 4. Launch the server. tunnel_forward=true → server listens on the
      //    abstract socket and we dial in; audio off; control per options.
      final args = <String>[
        '-s',
        deviceId,
        'shell',
        'CLASSPATH=$_deviceJarPath',
        'app_process',
        '/',
        _serverClass,
        serverVersion,
        'scid=$scidHex',
        'log_level=${options.logLevel}',
        'tunnel_forward=true',
        'audio=false',
        'control=${options.control}',
        'video=true',
        'video_codec=${options.codec}',
        'send_frame_meta=true',
        if (options.maxSize != null) 'max_size=${options.maxSize}',
        if (options.maxFps != null) 'max_fps=${options.maxFps}',
        if (options.videoBitRate != null)
          'video_bit_rate=${options.videoBitRate}',
      ];
      server = await Process.start(_adb, args);

      var serverExited = false;
      final serverExitCode = server.exitCode.then((code) {
        serverExited = true;
        return code;
      });
      // Drain server logs so its pipes never fill (which would stall it).
      server.stdout
          .transform(const SystemEncoding().decoder)
          .transform(const LineSplitter())
          .listen((line) => _log('[server] $line'));
      server.stderr
          .transform(const SystemEncoding().decoder)
          .transform(const LineSplitter())
          .listen((line) => _log('[server] $line'));

      // 5. Dial the tunnel. The server accepts sockets in order (video, then
      //    control) and only starts streaming once all expected sockets are
      //    connected, so when control is enabled we must connect both before
      //    reading the forward "dummy byte" the server emits on the first one.
      final reader = await _establishSockets(
        port: port,
        needControl: options.control,
        isServerDead: () => serverExited,
        assignVideo: (s) => videoSocket = s,
        assignControl: (s) => controlSocket = s,
      );
      final control = controlSocket == null
          ? null
          : ScrcpyControl(controlSocket!);

      // 6. Handshake: device name (64B) then codec id (4B).
      final nameBytes = await reader.readExactly(_deviceNameFieldLength);
      final deviceName = _cString(nameBytes);
      final codecId = String.fromCharCodes(await reader.readExactly(4));
      _log('handshake: name="$deviceName" codec="$codecId"');

      // 7. Consume the video header and align to the first packet. The header
      //    layout has bytes we don't fully attribute and may drift between
      //    scrcpy versions, so we resync to the first 12-byte frame meta whose
      //    payload begins with an Annex-B start code.
      final size = await _resyncToFirstPacket(reader);
      final dims = size.dimensions;
      _log('video header: ${dims.$1}x${dims.$2}');

      final controller = StreamController<ScrcpyPacket>(
        onCancel: () {}, // teardown is via ScrcpyStream.stop()
      );

      // 8. Pump packets. First packet is already buffered as [size.firstPacket].
      unawaited(
        _pump(reader, controller, firstPacket: size.firstPacket),
      );

      var stopped = false;
      Future<void> stop() async {
        if (stopped) return;
        stopped = true;
        await reader.cancel();
        await control?.close();
        if (!controller.isClosed) await controller.close();
        await cleanup();
      }

      return ScrcpyStream(
        deviceName: deviceName,
        codecId: codecId,
        width: dims.$1,
        height: dims.$2,
        packets: controller.stream,
        control: control,
        serverExitCode: serverExitCode,
        onStop: stop,
      );
    } catch (error) {
      await cleanup();
      if (error is ScrcpyClientException) rethrow;
      throw ScrcpyClientException('scrcpy connect failed: $error');
    }
  }

  Future<_ByteReader> _establishSockets({
    required int port,
    required bool needControl,
    required bool Function() isServerDead,
    required void Function(Socket) assignVideo,
    required void Function(Socket) assignControl,
  }) async {
    for (var attempt = 0; attempt < 50; attempt++) {
      if (isServerDead()) {
        throw const ScrcpyClientException(
          'scrcpy-server exited during startup (see server logs).',
        );
      }
      Socket? video;
      Socket? control;
      try {
        // Order matters: the first connection becomes the video socket, the
        // second the control socket.
        video = await Socket.connect(
          '127.0.0.1',
          port,
          timeout: const Duration(milliseconds: 300),
        );
        if (needControl) {
          control = await Socket.connect(
            '127.0.0.1',
            port,
            timeout: const Duration(milliseconds: 300),
          );
        }
        final reader = _ByteReader(video);
        // Forward tunnel: the server writes one dummy byte on the first socket
        // once all expected sockets are connected.
        await reader.readExactly(1).timeout(const Duration(milliseconds: 800));
        assignVideo(video);
        if (control != null) assignControl(control);
        return reader;
      } catch (_) {
        try {
          video?.destroy();
        } catch (_) {}
        try {
          control?.destroy();
        } catch (_) {}
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
    throw const ScrcpyClientException(
      'Timed out connecting to scrcpy-server tunnel.',
    );
  }

  /// Reads forward from just after the codec id until it finds the first valid
  /// packet: a 12-byte meta whose declared size points at a payload starting
  /// with an Annex-B start code. Returns that first packet plus the width and
  /// height parsed from the skipped video header bytes (best effort).
  Future<_FirstPacket> _resyncToFirstPacket(_ByteReader reader) async {
    // Empirically (scrcpy 4.0) the video header after the codec id is 12 bytes:
    // <4 reserved/flags> <width u32> <height u32>. We tolerate ±a few bytes of
    // drift by scanning candidate offsets.
    const candidateHeaderSizes = [12, 8, 0, 4, 16];
    final maxPeek = 16 + 12 + 8; // largest header + meta + start-code peek
    final peek = await reader.readExactly(maxPeek);

    for (final headerSize in candidateHeaderSizes) {
      if (headerSize + 12 + 4 > peek.length) continue;
      final meta = ByteData.sublistView(peek, headerSize, headerSize + 12);
      final raw = meta.getUint64(0);
      final pktSize = meta.getUint32(8);
      if (pktSize == 0 || pktSize > 64 * 1024 * 1024) continue;
      final payloadStart = headerSize + 12;
      if (!_startsWithNalStartCode(peek, payloadStart)) continue;

      // Parse a plausible width/height from the header (reserved-first layout).
      var width = 0;
      var height = 0;
      if (headerSize >= 12) {
        final hdr = ByteData.sublistView(peek, 0, 12);
        width = hdr.getUint32(4);
        height = hdr.getUint32(8);
      }

      final pts = raw & _ptsMask;
      final alreadyHave = peek.length - payloadStart;
      final builder = BytesBuilder(copy: false);
      builder.add(Uint8List.sublistView(peek, payloadStart));
      if (alreadyHave < pktSize) {
        builder.add(await reader.readExactly(pktSize - alreadyHave));
      }
      final full = builder.toBytes();
      // If we over-read past this packet, push the remainder back.
      if (alreadyHave > pktSize) {
        reader.unread(Uint8List.sublistView(full, pktSize));
      }
      final payload = Uint8List.sublistView(
        full,
        0,
        pktSize > full.length ? full.length : pktSize,
      );
      final kind = _classify(payload);

      return _FirstPacket(
        dimensions: (width, height),
        firstPacket: ScrcpyPacket(
          isConfig: kind.isConfig,
          isKeyFrame: kind.isKeyFrame,
          ptsMicros: pts,
          data: payload,
        ),
      );
    }
    throw const ScrcpyClientException(
      'Could not locate first video packet (stream desync).',
    );
  }

  Future<void> _pump(
    _ByteReader reader,
    StreamController<ScrcpyPacket> controller, {
    ScrcpyPacket? firstPacket,
  }) async {
    try {
      if (firstPacket != null && !controller.isClosed) {
        controller.add(firstPacket);
      }
      while (!controller.isClosed) {
        final header = await reader.readExactly(12);
        final meta = ByteData.sublistView(header);
        final raw = meta.getUint64(0);
        final size = meta.getUint32(8);
        // An encoder reset (device rotation) perturbs the stream framing on this
        // scrcpy build, throwing off alignment. We can't recover cleanly in
        // place — resyncing mid-stream feeds the decoder reference-less frames
        // (visible corruption) and there's no way to request a fresh keyframe.
        // So we surface the desync; the mirror layer restarts for a clean
        // handshake + keyframe.
        if (size == 0 || size > 64 * 1024 * 1024) {
          throw ScrcpyClientException('Implausible packet size $size (desync).');
        }
        final data = await reader.readExactly(size);
        if (controller.isClosed) break;
        final kind = _classify(data);
        controller.add(
          ScrcpyPacket(
            isConfig: kind.isConfig,
            isKeyFrame: kind.isKeyFrame,
            ptsMicros: raw & _ptsMask,
            data: data,
          ),
        );
      }
    } catch (error) {
      _log('[pump] stream ended/errored: $error');
      if (!controller.isClosed) controller.addError(error);
    } finally {
      if (!controller.isClosed) await controller.close();
    }
  }

  Future<int> _adbForward(String deviceId, String localName) async {
    final result = await Process.run(_adb, [
      '-s',
      deviceId,
      'forward',
      'tcp:0',
      'localabstract:$localName',
    ]);
    if (result.exitCode != 0) {
      throw ScrcpyClientException('adb forward failed: ${result.stderr}');
    }
    final port = int.tryParse((result.stdout as String).trim());
    if (port == null) {
      throw ScrcpyClientException('adb forward returned no port: "${result.stdout}"');
    }
    return port;
  }

  Future<void> _adbForwardRemove(String deviceId, int port) async {
    try {
      await Process.run(_adb, [
        '-s',
        deviceId,
        'forward',
        '--remove',
        'tcp:$port',
      ]);
    } catch (_) {}
  }

  static bool _startsWithNalStartCode(Uint8List data, int offset) {
    if (offset + 4 <= data.length &&
        data[offset] == 0 &&
        data[offset + 1] == 0 &&
        data[offset + 2] == 0 &&
        data[offset + 3] == 1) {
      return true;
    }
    if (offset + 3 <= data.length &&
        data[offset] == 0 &&
        data[offset + 1] == 0 &&
        data[offset + 2] == 1) {
      return true;
    }
    return false;
  }

  static String _cString(Uint8List bytes) {
    final end = bytes.indexOf(0);
    return String.fromCharCodes(bytes, 0, end == -1 ? bytes.length : end).trim();
  }

  /// Top 3 bits of the 64-bit PTS field are reserved for scrcpy packet flags
  /// (the exact bit assignment varies by build), so mask them off.
  static const int _ptsMask = 0x1FFFFFFFFFFFFFFF;

  /// Classifies an Annex-B payload by inspecting NAL unit types, which is more
  /// reliable than the server's flag bits: SPS(7)/PPS(8) without a slice means
  /// a codec-config packet; an IDR slice(5) means a key frame.
  static ({bool isConfig, bool isKeyFrame}) _classify(Uint8List data) {
    var hasParameterSet = false;
    var hasVcl = false;
    var hasIdr = false;
    var i = 0;
    while (i + 3 < data.length) {
      final isLong = data[i] == 0 &&
          data[i + 1] == 0 &&
          data[i + 2] == 0 &&
          data[i + 3] == 1;
      final isShort = data[i] == 0 && data[i + 1] == 0 && data[i + 2] == 1;
      if (!isLong && !isShort) {
        i++;
        continue;
      }
      final nalPos = i + (isLong ? 4 : 3);
      if (nalPos >= data.length) break;
      switch (data[nalPos] & 0x1F) {
        case 7: // SPS
        case 8: // PPS
          hasParameterSet = true;
        case 5: // IDR slice
          hasIdr = true;
          hasVcl = true;
        case 1: // non-IDR slice
          hasVcl = true;
      }
      i = nalPos + 1;
    }
    return (isConfig: hasParameterSet && !hasVcl, isKeyFrame: hasIdr);
  }
}

class _FirstPacket {
  const _FirstPacket({required this.dimensions, required this.firstPacket});
  final (int, int) dimensions;
  final ScrcpyPacket firstPacket;
}

/// Pull-based reader that yields exactly N bytes from a byte stream, buffering
/// chunks and completing reads as data arrives.
class _ByteReader {
  _ByteReader(Stream<Uint8List> source) {
    _sub = source.listen(
      _onData,
      onError: _onError,
      onDone: _onDone,
      cancelOnError: false,
    );
  }

  late final StreamSubscription<Uint8List> _sub;
  final List<Uint8List> _chunks = <Uint8List>[];
  int _head = 0;
  int _available = 0;
  int _need = 0;
  Completer<Uint8List>? _pending;
  Object? _error;
  bool _done = false;

  void _onData(Uint8List data) {
    if (data.isEmpty) return;
    _chunks.add(data);
    _available += data.length;
    _tryComplete();
  }

  void _onError(Object error, StackTrace stackTrace) {
    _error = error;
    _failPending();
  }

  void _onDone() {
    _done = true;
    _failPending();
  }

  /// Returns the next [n] bytes, completing once enough have arrived.
  Future<Uint8List> readExactly(int n) {
    assert(_pending == null, 'Concurrent readExactly is not supported');
    if (n == 0) return Future<Uint8List>.value(Uint8List(0));
    if (_error != null) return Future<Uint8List>.error(_error!);
    final completer = Completer<Uint8List>();
    _pending = completer;
    _need = n;
    _tryComplete();
    return completer.future;
  }

  /// Pushes bytes back to the front of the buffer (used after over-reading).
  void unread(Uint8List bytes) {
    if (bytes.isEmpty) return;
    // Compact the current head chunk so the pushed-back bytes can sit at index
    // 0 with _head reset to 0.
    if (_head > 0 && _chunks.isNotEmpty) {
      _chunks[0] = Uint8List.sublistView(_chunks[0], _head);
      _head = 0;
    }
    _chunks.insert(0, bytes);
    _available += bytes.length;
  }

  void _tryComplete() {
    final completer = _pending;
    if (completer == null) return;
    if (_available < _need) {
      if (_done || _error != null) _failPending();
      return;
    }
    final out = Uint8List(_need);
    var written = 0;
    while (written < _need) {
      final chunk = _chunks.first;
      final take = min(chunk.length - _head, _need - written);
      out.setRange(written, written + take, chunk, _head);
      written += take;
      _head += take;
      if (_head >= chunk.length) {
        _chunks.removeAt(0);
        _head = 0;
      }
    }
    _available -= _need;
    _pending = null;
    completer.complete(out);
  }

  void _failPending() {
    final completer = _pending;
    if (completer == null) return;
    _pending = null;
    completer.completeError(
      _error ?? const SocketException('scrcpy video stream closed'),
    );
  }

  Future<void> cancel() => _sub.cancel();
}
