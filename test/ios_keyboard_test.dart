import 'package:eagly/features/flutter_scrcpy/flutter_scrcpy.dart';
import 'package:eagly/features/mirror/ios/ios_keyboard.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  KeyEvent down(PhysicalKeyboardKey physical) => KeyDownEvent(
    physicalKey: physical,
    logicalKey: LogicalKeyboardKey.keyA,
    timeStamp: Duration.zero,
  );

  KeyEvent up(PhysicalKeyboardKey physical) => KeyUpEvent(
    physicalKey: physical,
    logicalKey: LogicalKeyboardKey.keyA,
    timeStamp: Duration.zero,
  );

  KeyEvent repeat(PhysicalKeyboardKey physical) => KeyRepeatEvent(
    physicalKey: physical,
    logicalKey: LogicalKeyboardKey.keyA,
    timeStamp: Duration.zero,
  );

  const none = ScrcpyModifiers();
  const command = ScrcpyModifiers(meta: true);

  Matcher press(int usage, {required bool down, int page = 0x07}) =>
      isA<IosPressKey>()
          .having((key) => key.page, 'page', page)
          .having((key) => key.usage, 'usage', usage)
          .having((key) => key.down, 'down', down);

  test('a key goes over as its HID usage, down then up', () {
    final translator = IosKeyboardTranslator();

    expect(
      translator.translate(down(PhysicalKeyboardKey.keyA), none),
      press(0x04, down: true),
    );
    expect(
      translator.translate(up(PhysicalKeyboardKey.keyA), none),
      press(0x04, down: false),
    );
  });

  test('modifiers go over as keys of their own', () {
    final translator = IosKeyboardTranslator();

    expect(
      translator.translate(
        down(PhysicalKeyboardKey.shiftLeft),
        const ScrcpyModifiers(shift: true),
      ),
      press(0xE1, down: true),
    );
  });

  test('the phone repeats a held key itself', () {
    final translator = IosKeyboardTranslator();
    translator.translate(down(PhysicalKeyboardKey.keyA), none);

    expect(
      translator.translate(repeat(PhysicalKeyboardKey.keyA), none),
      isA<IosIgnoreKey>(),
    );
  });

  test('a key-up goes out only for a key-down that did', () {
    final translator = IosKeyboardTranslator();

    expect(
      translator.translate(up(PhysicalKeyboardKey.keyB), none),
      isA<IosIgnoreKey>(),
    );
  });

  group('on macOS', () {
    test('⌘ editing chords reach the phone as ⌘', () {
      final translator = IosKeyboardTranslator();

      expect(
        translator.translate(down(PhysicalKeyboardKey.metaLeft), command),
        press(0xE3, down: true),
      );
      expect(
        translator.translate(down(PhysicalKeyboardKey.keyC), command),
        press(0x06, down: true),
      );
      expect(translator.isCommandHeld, isTrue);
    });

    test('other ⌘ chords stay with the app', () {
      final translator = IosKeyboardTranslator();

      expect(
        translator.translate(down(PhysicalKeyboardKey.keyQ), command),
        isNull,
      );
      expect(
        translator.translate(up(PhysicalKeyboardKey.keyQ), command),
        isNull,
      );
    });

    test('a key pressed before ⌘ still gets its key-up', () {
      final translator = IosKeyboardTranslator();
      translator.translate(down(PhysicalKeyboardKey.keyQ), none);

      expect(
        translator.translate(up(PhysicalKeyboardKey.keyQ), command),
        press(0x14, down: false),
      );
    });

    test('⌘V pastes the desktop clipboard', () {
      final translator = IosKeyboardTranslator();

      expect(
        translator.translate(down(PhysicalKeyboardKey.keyV), command),
        isA<IosPasteClipboard>(),
      );
    });
  });

  group('on Windows and Linux', () {
    test('Ctrl becomes the phone\'s ⌘, and the Windows key its Control', () {
      final translator = IosKeyboardTranslator(controlIsCommand: true);

      expect(
        translator.translate(
          down(PhysicalKeyboardKey.controlLeft),
          const ScrcpyModifiers(control: true),
        ),
        press(0xE3, down: true),
      );
      expect(
        translator.translate(down(PhysicalKeyboardKey.metaRight), command),
        press(0xE4, down: true),
      );
      expect(translator.isCommandHeld, isTrue);
    });

    test('Ctrl+V pastes the desktop clipboard', () {
      final translator = IosKeyboardTranslator(controlIsCommand: true);

      expect(
        translator.translate(
          down(PhysicalKeyboardKey.keyV),
          const ScrcpyModifiers(control: true),
        ),
        isA<IosPasteClipboard>(),
      );
    });

    test('every Windows-key chord stays with the host', () {
      final translator = IosKeyboardTranslator(controlIsCommand: true);

      expect(
        translator.translate(down(PhysicalKeyboardKey.keyC), command),
        isNull,
      );
    });
  });

  test('media keys go over as the phone\'s buttons', () {
    final translator = IosKeyboardTranslator();

    expect(
      translator.translate(down(PhysicalKeyboardKey.audioVolumeUp), none),
      press(0xE9, down: true, page: 0x0C),
    );
    expect(
      translator.translate(down(PhysicalKeyboardKey.mediaPlayPause), none),
      press(0xCD, down: true, page: 0x0C),
    );
  });

  test('keys a phone has no use for are swallowed', () {
    final translator = IosKeyboardTranslator();

    expect(
      translator.translate(down(PhysicalKeyboardKey.fn), none),
      isA<IosIgnoreKey>(),
    );
  });

  test('releaseAll lets go of every key still held', () {
    final translator = IosKeyboardTranslator();
    translator.translate(down(PhysicalKeyboardKey.shiftLeft), none);
    translator.translate(down(PhysicalKeyboardKey.keyA), none);

    expect(translator.releaseAll(), [
      press(0xE1, down: false),
      press(0x04, down: false),
    ]);
    expect(translator.releaseAll(), isEmpty);
  });
}
