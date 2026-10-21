/// Checks, against a real iPhone, the CoreDevice half of the screen mirror:
/// what the phone offers, screenshots, and touch and buttons through
/// `api/ios_mirror.rs`. Opt-in, so skipped in CI. The QuickTime picture lives
/// in the macOS runner and is only exercised by running the app.
///
/// Needs Developer Mode, Xcode 27's developer disk image mounted (open Xcode
/// with the phone connected once), and the phone unlocked on a home-screen
/// page. The test pages the home screen and puts it back where it was.
///
/// ```bash
/// cd rust && cargo build --release && cd ..
/// EAGLY_TEST_IOS_UDID=<udid> fvm flutter test test/device/ios_mirror_device_test.dart
/// ```
///
/// Set `EAGLY_TEST_ARTIFACTS=<dir>` to keep every screenshot it takes.
library;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:eagly/features/mirror/ios/ios_mirror_session.dart';
import 'package:eagly/services/ios/ios_mirror_service.dart';
import 'package:eagly/services/ios/rust_ios_mirror_service.dart';
import 'package:eagly/src/rust/frb_generated.dart';
import 'package:flutter_test/flutter_test.dart';

final _udid = Platform.environment['EAGLY_TEST_IOS_UDID'];
final _artifacts = Platform.environment['EAGLY_TEST_ARTIFACTS'];

const _step = Duration(milliseconds: 16);

/// Mean per-pixel brightness difference, 0–255, over the screen between the
/// status bar and the dock, sampled on a 40×80 grid.
Future<double> _difference(Uint8List a, Uint8List b) async {
  Future<(ByteData, int, int)> decode(Uint8List png) async {
    final codec = await ui.instantiateImageCodec(png);
    final image = (await codec.getNextFrame()).image;
    final pixels = await image.toByteData();
    return (pixels!, image.width, image.height);
  }

  final (first, width, height) = await decode(a);
  final (second, _, _) = await decode(b);
  var total = 0.0;
  var samples = 0;
  for (var gy = 0; gy < 80; gy++) {
    final y = (height * (0.1 + 0.7 * gy / 80)).floor();
    for (var gx = 0; gx < 40; gx++) {
      final offset = (y * width + (width * gx / 40).floor()) * 4;
      for (var channel = 0; channel < 3; channel++) {
        total +=
            (first.getUint8(offset + channel) -
                    second.getUint8(offset + channel))
                .abs();
      }
      samples += 3;
    }
  }
  return total / samples;
}

/// A screenshot, kept as `<name>.png` when `EAGLY_TEST_ARTIFACTS` is set.
Future<Uint8List> _shot(RustIosMirrorService service, String name) async {
  final png = await service.captureScreenshot(_udid!);
  if (_artifacts case final dir?) File('$dir/$name.png').writeAsBytesSync(png);
  return png;
}

/// Slides a finger from [fromX] to [toX] across the middle of the screen.
/// [settle] holds it still at the end, as a user who stops before letting
/// go; without it the finger lifts while moving, which is a flick.
Future<void> _drag(
  IosInputSession input,
  double fromX,
  double toX, {
  Duration settle = Duration.zero,
}) async {
  const y = 0.72;
  expect(input.touch(IosTouchPhase.down, fromX, y), isTrue);
  for (var i = 1; i <= 8; i++) {
    await Future<void>.delayed(_step);
    input.touch(IosTouchPhase.move, fromX + (toX - fromX) * i / 8, y);
  }
  await Future<void>.delayed(settle);
  input.touch(IosTouchPhase.up, toX, y);
  await Future<void>.delayed(const Duration(milliseconds: 900));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'iOS: CoreDevice screenshots, touch and buttons reach the phone',
    () async {
      await RustLib.init();
      final service = RustIosMirrorService();
      final udid = _udid!;

      var clock = Stopwatch()..start();
      final support = await service.probe(udid);
      // ignore: avoid_print
      print(
        'probe ${clock.elapsedMilliseconds} ms: screenshots '
        '${support.screenshots}, input ${support.input}, pasteboard '
        '${support.pasteboard}, rotation ${support.rotation}, display stream '
        '${support.displayStream}',
      );
      expect(support.screenshots, isTrue, reason: 'is the DDI mounted?');
      expect(support.input, isTrue);

      clock = Stopwatch()..start();
      final before = await _shot(service, 'before');
      final size = pngSize(before)!;
      // ignore: avoid_print
      print(
        'screenshot ${clock.elapsedMilliseconds} ms, '
        '${size.width.toInt()}×${size.height.toInt()}',
      );
      expect(size.height, greaterThan(size.width));
      expect(
        await service.interfaceOrientation(udid),
        IosInterfaceOrientation.portrait,
      );

      clock = Stopwatch()..start();
      final frames = await service.screenshots(udid).take(3).toList();
      // ignore: avoid_print
      print('screenshot stream: 3 frames in ${clock.elapsedMilliseconds} ms');
      expect(frames, hasLength(3));

      final input = await service.startInput(udid);
      try {
        // Stopping before letting go must not fling to the next page: the
        // worker keeps a still finger wobbling a pixel so its speed decays.
        await _drag(
          input,
          0.5,
          0.38,
          settle: const Duration(milliseconds: 300),
        );
        await _shot(service, 'dragged');
        await _drag(
          input,
          0.38,
          0.5,
          settle: const Duration(milliseconds: 300),
        );
        final settled = await _shot(service, 'settled');
        expect(
          await _difference(before, settled),
          lessThan(4),
          reason: 'a settled drag flung the home screen',
        );

        // A flick right pages (or opens the Today View); a flick left
        // comes back.
        await _drag(input, 0.2, 0.8);
        final paged = await _shot(service, 'paged');
        expect(
          await _difference(settled, paged),
          greaterThan(10),
          reason: 'the flick did not land',
        );
        await _drag(input, 0.8, 0.2);
        final back = await _shot(service, 'back');
        expect(await _difference(before, back), lessThan(4));

        expect(input.button(0x0C, 0x40, down: true), isTrue);
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(input.button(0x0C, 0x40, down: false), isTrue);
      } finally {
        await input.close();
      }
      expect(input.touch(IosTouchPhase.down, 0.5, 0.5), isFalse);
    },
    skip: _udid == null
        ? 'Set EAGLY_TEST_IOS_UDID to run against an iPhone'
        : false,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
