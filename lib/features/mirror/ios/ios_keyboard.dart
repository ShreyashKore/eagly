import 'package:flutter/services.dart';

import '../../flutter_scrcpy/flutter_scrcpy.dart' show ScrcpyModifiers;

/// The HID usages the iPhone mirror sends by name.
abstract final class IosHid {
  static const int keyboardPage = 0x07;
  static const int consumerPage = 0x0C;

  // Keyboard/Keypad page.
  static const int keyV = 0x19;
  static const int leftControl = 0xE0;
  static const int leftGui = 0xE3;
  static const int rightControl = 0xE4;
  static const int rightGui = 0xE7;

  // Consumer page: the phone's hardware buttons.
  static const int home = 0x40;
  static const int power = 0x30;
  static const int volumeUp = 0xE9;
  static const int volumeDown = 0xEA;
}

/// What a desktop key event becomes on an iPhone. `null` from
/// [IosKeyboardTranslator.translate] means "not ours": the event keeps
/// bubbling so the app's shortcuts still fire.
sealed class const IosKeyCommand();

/// Consume the key without sending anything.
class const IosIgnoreKey() extends IosKeyCommand;

/// A key going down or up: a keyboard key on [IosHid.keyboardPage], or a
/// media key on [IosHid.consumerPage].
class const IosPressKey(
  final int page,
  final int usage, {
  required final bool down,
}) extends IosKeyCommand;

/// Push the desktop clipboard onto the phone and paste it (⌘V / Ctrl+V).
class const IosPasteClipboard() extends IosKeyCommand;

/// Turns Flutter key events into HID key presses for an iPhone.
///
/// An iPhone only takes keys as a hardware keyboard sends them, and Flutter's
/// physical keys already carry their HID usage (`usbHidUsage`), so a key goes
/// over as itself — modifiers too, as keys of their own — and the phone types
/// through its own hardware-keyboard layout setting. That differs from
/// Android, where printable keys travel as text in the host's layout.
///
/// Stateful like [ScrcpyKeyboardTranslator]: a key-up only goes out for a
/// key-down that did, and [releaseAll] unsticks keys still held when the
/// mirror loses focus.
class IosKeyboardTranslator({
  /// Whether the host's Ctrl stands in for the phone's ⌘ (Windows / Linux),
  /// since copy and paste on iOS are ⌘ shortcuts those keyboards spell Ctrl.
  /// The Windows / Super key then becomes the phone's Control. On macOS ⌘ is
  /// ⌘ on both sides.
  final bool controlIsCommand = false,
}) {
  /// Physical key's `usbHidUsage` → the `page << 16 | usage` pressed for it.
  final Map<int, int> _pressed = {};

  /// The ⌘ chords that go to the phone on macOS. Every other one belongs to
  /// the app (⌘Q, ⌘W, ⌘,); elsewhere the Windows / Super key's chords all do.
  static final Set<PhysicalKeyboardKey> _commandShortcuts = {
    PhysicalKeyboardKey.keyA,
    PhysicalKeyboardKey.keyC,
    PhysicalKeyboardKey.keyV,
    PhysicalKeyboardKey.keyX,
    PhysicalKeyboardKey.keyZ,
  };

  static final Set<PhysicalKeyboardKey> _modifierKeys = {
    PhysicalKeyboardKey.shiftLeft,
    PhysicalKeyboardKey.shiftRight,
    PhysicalKeyboardKey.controlLeft,
    PhysicalKeyboardKey.controlRight,
    PhysicalKeyboardKey.altLeft,
    PhysicalKeyboardKey.altRight,
    PhysicalKeyboardKey.metaLeft,
    PhysicalKeyboardKey.metaRight,
    PhysicalKeyboardKey.capsLock,
  };

  /// Whether the phone currently holds ⌘ down for us.
  bool get isCommandHeld => _pressed.values.any(
    (code) =>
        code == _code(IosHid.keyboardPage, IosHid.leftGui) ||
        code == _code(IosHid.keyboardPage, IosHid.rightGui),
  );

  IosKeyCommand? translate(KeyEvent event, ScrcpyModifiers modifiers) {
    final physical = event.physicalKey;
    final modifier = _modifierKeys.contains(physical);
    final hostChord =
        modifiers.meta &&
        !modifier &&
        (controlIsCommand || !_commandShortcuts.contains(physical));

    // Before [hostChord]: a key pressed before the chord began still needs
    // its key-up, or the phone keeps it held.
    if (event is KeyUpEvent) {
      final code = _pressed.remove(physical.usbHidUsage);
      if (code == null) return hostChord ? null : const IosIgnoreKey();
      return IosPressKey(code >> 16, code & 0xFFFF, down: false);
    }
    if (hostChord) return null;
    // The phone repeats a held key itself, as it would for a real keyboard.
    if (event is KeyRepeatEvent) return const IosIgnoreKey();

    final command = controlIsCommand ? modifiers.control : modifiers.meta;
    if (command && physical == PhysicalKeyboardKey.keyV) {
      return const IosPasteClipboard();
    }

    final code = _deviceCode(physical);
    if (code == null) return const IosIgnoreKey();
    _pressed[physical.usbHidUsage] = code;
    return IosPressKey(code >> 16, code & 0xFFFF, down: true);
  }

  /// Key-ups for everything still held.
  List<IosPressKey> releaseAll() {
    final ups = [
      for (final code in _pressed.values)
        IosPressKey(code >> 16, code & 0xFFFF, down: false),
    ];
    _pressed.clear();
    return ups;
  }

  /// The phone's usage for [physical], with Ctrl and the Windows key swapped
  /// when [controlIsCommand]; null for keys a phone has no use for.
  int? _deviceCode(PhysicalKeyboardKey physical) {
    final hid = physical.usbHidUsage;
    final page = hid >> 16;
    final usage = hid & 0xFFFF;
    return switch ((page, usage)) {
      // Flutter files the volume keys under the keyboard page; the phone's
      // own buttons are Consumer usages.
      (IosHid.keyboardPage, _keyboardMute) => _code(IosHid.consumerPage, 0xE2),
      (IosHid.keyboardPage, _keyboardVolumeUp) => _code(
        IosHid.consumerPage,
        IosHid.volumeUp,
      ),
      (IosHid.keyboardPage, _keyboardVolumeDown) => _code(
        IosHid.consumerPage,
        IosHid.volumeDown,
      ),
      (IosHid.keyboardPage, _) => _code(page, _swapped(usage)),
      // Play/pause and the other media keys.
      (IosHid.consumerPage, _) => hid,
      _ => null,
    };
  }

  static const int _keyboardMute = 0x7F;
  static const int _keyboardVolumeUp = 0x80;
  static const int _keyboardVolumeDown = 0x81;

  int _swapped(int usage) {
    if (!controlIsCommand) return usage;
    return switch (usage) {
      IosHid.leftControl => IosHid.leftGui,
      IosHid.rightControl => IosHid.rightGui,
      IosHid.leftGui => IosHid.leftControl,
      IosHid.rightGui => IosHid.rightControl,
      _ => usage,
    };
  }

  static int _code(int page, int usage) => page << 16 | usage;
}
