import 'package:eagly/features/flutter_scrcpy/flutter_scrcpy.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  KeyEvent down(
    LogicalKeyboardKey key, {
    PhysicalKeyboardKey physical = PhysicalKeyboardKey.keyA,
    String? character,
  }) => KeyDownEvent(
    physicalKey: physical,
    logicalKey: key,
    character: character,
    timeStamp: Duration.zero,
  );

  KeyEvent up(
    LogicalKeyboardKey key, {
    PhysicalKeyboardKey physical = PhysicalKeyboardKey.keyA,
  }) => KeyUpEvent(
    physicalKey: physical,
    logicalKey: key,
    timeStamp: Duration.zero,
  );

  KeyEvent repeat(
    LogicalKeyboardKey key, {
    PhysicalKeyboardKey physical = PhysicalKeyboardKey.keyA,
    String? character,
  }) => KeyRepeatEvent(
    physicalKey: physical,
    logicalKey: key,
    character: character,
    timeStamp: Duration.zero,
  );

  const none = ScrcpyModifiers();

  test('printable keys are typed as text, not as a keycode', () {
    final translator = ScrcpyKeyboardTranslator();

    final command = translator.translate(
      down(LogicalKeyboardKey.keyA, character: 'a'),
      none,
    );

    expect(command, isA<ScrcpyInjectText>());
    expect((command! as ScrcpyInjectText).text, 'a');
  });

  test('the host layout decides the character, not the physical key', () {
    // An AZERTY host reports logical/physical "q" for the key labelled A.
    final translator = ScrcpyKeyboardTranslator();

    final command = translator.translate(
      down(
        LogicalKeyboardKey.keyQ,
        physical: PhysicalKeyboardKey.keyA,
        character: 'q',
      ),
      none,
    );

    expect((command! as ScrcpyInjectText).text, 'q');
  });

  test('shifted characters arrive already uppercased', () {
    final translator = ScrcpyKeyboardTranslator();

    final command = translator.translate(
      down(LogicalKeyboardKey.keyA, character: 'A'),
      const ScrcpyModifiers(shift: true),
    );

    expect((command! as ScrcpyInjectText).text, 'A');
  });

  test('a text key sends no stray key-up', () {
    final translator = ScrcpyKeyboardTranslator();

    translator.translate(down(LogicalKeyboardKey.keyA, character: 'a'), none);
    final release = translator.translate(up(LogicalKeyboardKey.keyA), none);

    expect(release, isA<ScrcpyIgnoreKey>());
  });

  test('enter and backspace go over as keycodes, down then up', () {
    final translator = ScrcpyKeyboardTranslator();

    final press =
        translator.translate(
              down(
                LogicalKeyboardKey.enter,
                physical: PhysicalKeyboardKey.enter,
                character: '\n',
              ),
              none,
            )!
            as ScrcpyInjectKeycode;
    final release =
        translator.translate(
              up(LogicalKeyboardKey.enter, physical: PhysicalKeyboardKey.enter),
              none,
            )!
            as ScrcpyInjectKeycode;

    expect(press.keycode, 66); // KEYCODE_ENTER
    expect(press.down, isTrue);
    expect(release.keycode, 66);
    expect(release.down, isFalse);

    expect(
      (translator.translate(
                down(
                  LogicalKeyboardKey.backspace,
                  physical: PhysicalKeyboardKey.backspace,
                ),
                none,
              )!
              as ScrcpyInjectKeycode)
          .keycode,
      67, // KEYCODE_DEL
    );
  });

  test('auto-repeat raises the repeat count', () {
    final translator = ScrcpyKeyboardTranslator();
    final key = LogicalKeyboardKey.arrowDown;
    const physical = PhysicalKeyboardKey.arrowDown;

    final first =
        translator.translate(down(key, physical: physical), none)!
            as ScrcpyInjectKeycode;
    final second =
        translator.translate(repeat(key, physical: physical), none)!
            as ScrcpyInjectKeycode;
    final third =
        translator.translate(repeat(key, physical: physical), none)!
            as ScrcpyInjectKeycode;

    expect([first.repeat, second.repeat, third.repeat], [0, 1, 2]);
  });

  test('bare modifiers are swallowed rather than forwarded', () {
    final translator = ScrcpyKeyboardTranslator();

    expect(
      translator.translate(
        down(
          LogicalKeyboardKey.shiftLeft,
          physical: PhysicalKeyboardKey.shiftLeft,
        ),
        const ScrcpyModifiers(shift: true),
      ),
      isA<ScrcpyIgnoreKey>(),
    );
  });

  test('Ctrl chords become keycodes carrying META_CTRL_ON', () {
    final translator = ScrcpyKeyboardTranslator();

    final command =
        translator.translate(
              down(LogicalKeyboardKey.keyA, character: 'a'),
              const ScrcpyModifiers(control: true),
            )!
            as ScrcpyInjectKeycode;

    expect(command.keycode, 29); // KEYCODE_A
    expect(command.metaState & AndroidMetaState.ctrlOn, isNonZero);
  });

  test('Ctrl+V pushes the desktop clipboard instead of a keycode', () {
    final translator = ScrcpyKeyboardTranslator();

    expect(
      translator.translate(
        down(
          LogicalKeyboardKey.keyV,
          physical: PhysicalKeyboardKey.keyV,
          character: 'v',
        ),
        const ScrcpyModifiers(control: true),
      ),
      isA<ScrcpyPasteClipboard>(),
    );
  });

  test('⌘V pastes when Meta stands in for Ctrl', () {
    final translator = ScrcpyKeyboardTranslator(metaIsControl: true);

    expect(
      translator.translate(
        down(
          LogicalKeyboardKey.keyV,
          physical: PhysicalKeyboardKey.keyV,
          character: 'v',
        ),
        const ScrcpyModifiers(meta: true),
      ),
      isA<ScrcpyPasteClipboard>(),
    );
  });

  test('non-editing ⌘ chords stay with the host app', () {
    final translator = ScrcpyKeyboardTranslator(metaIsControl: true);

    // ⌘Q must still quit the app, so the event has to keep bubbling.
    expect(
      translator.translate(
        down(
          LogicalKeyboardKey.keyQ,
          physical: PhysicalKeyboardKey.keyQ,
          character: 'q',
        ),
        const ScrcpyModifiers(meta: true),
      ),
      isNull,
    );
  });

  test('a key released while ⌘ is held still gets its key-up', () {
    final translator = ScrcpyKeyboardTranslator(metaIsControl: true);
    translator.translate(
      down(
        LogicalKeyboardKey.backspace,
        physical: PhysicalKeyboardKey.backspace,
      ),
      none,
    );

    // ⌘ went down after Backspace (reaching for ⌘Tab); the release must not
    // be swallowed as a host chord, or the device keeps deleting.
    final release = translator.translate(
      up(LogicalKeyboardKey.backspace, physical: PhysicalKeyboardKey.backspace),
      const ScrcpyModifiers(meta: true),
    );

    expect(release, isA<ScrcpyInjectKeycode>());
    final keycode = release! as ScrcpyInjectKeycode;
    expect(keycode.down, isFalse);
    expect(keycode.metaState, AndroidMetaState.none);
    expect(translator.releaseAll(), isEmpty);
  });

  test('the key-up of an unforwarded ⌘ chord stays with the host', () {
    final translator = ScrcpyKeyboardTranslator(metaIsControl: true);

    expect(
      translator.translate(
        up(LogicalKeyboardKey.keyQ, physical: PhysicalKeyboardKey.keyQ),
        const ScrcpyModifiers(meta: true),
      ),
      isNull,
    );
  });

  test('Meta chords are never forwarded where Meta is not Ctrl', () {
    final translator = ScrcpyKeyboardTranslator();

    expect(
      translator.translate(
        down(
          LogicalKeyboardKey.keyV,
          physical: PhysicalKeyboardKey.keyV,
          character: 'v',
        ),
        const ScrcpyModifiers(meta: true),
      ),
      isNull,
    );
  });

  test('releaseAll unsticks keys still held when focus is lost', () {
    final translator = ScrcpyKeyboardTranslator();
    translator.translate(
      down(LogicalKeyboardKey.arrowUp, physical: PhysicalKeyboardKey.arrowUp),
      none,
    );

    final ups = translator.releaseAll().cast<ScrcpyInjectKeycode>();

    expect(ups.single.keycode, 19); // KEYCODE_DPAD_UP
    expect(ups.single.down, isFalse);
    expect(translator.releaseAll(), isEmpty);
  });

  test('unmapped keys are swallowed so the host stops beeping', () {
    final translator = ScrcpyKeyboardTranslator();

    expect(
      translator.translate(
        down(
          LogicalKeyboardKey.mediaPlay,
          physical: PhysicalKeyboardKey.mediaPlay,
        ),
        none,
      ),
      isA<ScrcpyIgnoreKey>(),
    );
  });
}
