import 'package:flutter/services.dart';

/// Android `KeyEvent` meta-state bits forwarded alongside injected keycodes.
abstract final class AndroidMetaState {
  static const int none = 0;
  static const int shiftOn = 0x00000001;
  static const int altOn = 0x00000002;
  static const int ctrlOn = 0x00001000;
}

/// Android `KeyEvent` keycodes referenced outside the lookup table.
abstract final class AndroidKeycode {
  static const int keyV = 50;
  static const int cut = 277;
  static const int copy = 278;
  static const int paste = 279;
}

/// The desktop modifiers held while a key event was produced. Kept separate
/// from [HardwareKeyboard] so the translator stays pure and testable.
class ScrcpyModifiers {
  const ScrcpyModifiers({
    this.shift = false,
    this.alt = false,
    this.control = false,
    this.meta = false,
  });

  ScrcpyModifiers.fromHardwareKeyboard()
    : shift = HardwareKeyboard.instance.isShiftPressed,
      alt = HardwareKeyboard.instance.isAltPressed,
      control = HardwareKeyboard.instance.isControlPressed,
      meta = HardwareKeyboard.instance.isMetaPressed;

  final bool shift;
  final bool alt;
  final bool control;
  final bool meta;
}

/// What a desktop key event translates into on the device. `null` from
/// [ScrcpyKeyboardTranslator.translate] means "not ours" — the event keeps
/// bubbling so app shortcuts still fire.
sealed class const ScrcpyKeyCommand();

/// Consume the key without sending anything (e.g. a bare modifier press).
/// Swallowing it is what stops the host beeping at an unhandled key.
class const ScrcpyIgnoreKey() extends ScrcpyKeyCommand;

/// Inject [text] as characters. Preferred over a keycode for anything
/// printable: the desktop keymap has already resolved the layout, so an
/// AZERTY or Dvorak host types what the user actually sees on their keys.
class const ScrcpyInjectText(this.text) extends ScrcpyKeyCommand {
  final String text;
}

/// Inject an Android keycode press or release.
class const ScrcpyInjectKeycode(
  this.keycode, {
  required this.down,
  this.metaState = AndroidMetaState.none,
  this.repeat = 0,
}) extends ScrcpyKeyCommand {
  final int keycode;
  final bool down;
  final int metaState;
  final int repeat;
}

/// Push the desktop clipboard onto the device and paste it (Ctrl/⌘+V).
class const ScrcpyPasteClipboard() extends ScrcpyKeyCommand;

/// Turns Flutter key events into scrcpy control commands.
///
/// Printable keys go over as text and everything else as an Android keycode,
/// which is how scrcpy's own SDK keyboard behaves. The translator is
/// stateful: it remembers which keycodes it pressed so a key-up is only
/// forwarded for a key-down it actually sent, and so [releaseAll] can unstick
/// held modifiers when the mirror loses focus.
class ScrcpyKeyboardTranslator({this.metaIsControl = false}) {
  /// Whether the platform's ⌘ key should act as the device's Ctrl (macOS), so
  /// ⌘C/⌘V/⌘A do on the device what they do on the desktop. When false the
  /// Meta key is left to the host app.
  final bool metaIsControl;

  final Map<int, int> _pressed = <int, int>{};
  final Map<int, int> _repeats = <int, int>{};

  /// Keys always sent as keycodes: their `character` is either absent or a
  /// control character, and apps expect the real keycode (an IME's "next" /
  /// "send" action keys off `KEYCODE_ENTER`, not a newline).
  static final Set<LogicalKeyboardKey> _alwaysKeycode = {
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter,
    LogicalKeyboardKey.tab,
    LogicalKeyboardKey.space,
    LogicalKeyboardKey.backspace,
    LogicalKeyboardKey.delete,
    LogicalKeyboardKey.escape,
  };

  static final Set<LogicalKeyboardKey> _modifierKeys = {
    LogicalKeyboardKey.shift,
    LogicalKeyboardKey.shiftLeft,
    LogicalKeyboardKey.shiftRight,
    LogicalKeyboardKey.control,
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.controlRight,
    LogicalKeyboardKey.alt,
    LogicalKeyboardKey.altLeft,
    LogicalKeyboardKey.altRight,
    LogicalKeyboardKey.meta,
    LogicalKeyboardKey.metaLeft,
    LogicalKeyboardKey.metaRight,
    LogicalKeyboardKey.capsLock,
    LogicalKeyboardKey.fn,
  };

  /// Editing shortcuts we translate when ⌘ is the modifier. Anything else with
  /// ⌘ down (⌘Q, ⌘W, ⌘,) belongs to the desktop app, not the device.
  static final Set<LogicalKeyboardKey> _metaShortcuts = {
    LogicalKeyboardKey.keyA,
    LogicalKeyboardKey.keyC,
    LogicalKeyboardKey.keyV,
    LogicalKeyboardKey.keyX,
    LogicalKeyboardKey.keyZ,
  };

  ScrcpyKeyCommand? translate(KeyEvent event, ScrcpyModifiers modifiers) {
    final key = event.logicalKey;
    final metaShortcut = modifiers.meta && metaIsControl;

    // A Meta chord we don't translate stays with the host app.
    final hostChord =
        modifiers.meta && !(metaShortcut && _metaShortcuts.contains(key));

    // Checked before [hostChord]: a key pressed before ⌘ went down still needs
    // its key-up, or the device keeps it held.
    if (event is KeyUpEvent) {
      _repeats.remove(key.keyId);
      final keycode = _pressed.remove(key.keyId);
      if (keycode == null) return hostChord ? null : const ScrcpyIgnoreKey();
      return ScrcpyInjectKeycode(
        keycode,
        down: false,
        metaState: _metaStateFor(modifiers, metaShortcut && !hostChord),
      );
    }

    if (hostChord) return null;

    // Bare modifier presses aren't forwarded: the meta state rides along with
    // the keycode they modify, and injecting them standalone makes the device
    // think a physical keyboard is attached (it hides the soft keyboard).
    if (_modifierKeys.contains(key)) return const ScrcpyIgnoreKey();

    final control = modifiers.control || metaShortcut;
    if (control && key == LogicalKeyboardKey.keyV) {
      return const ScrcpyPasteClipboard();
    }

    final keycode = androidKeycodeFor(key);
    final metaState = _metaStateFor(modifiers, metaShortcut);

    // Text injection resolves the host layout for us, but only when no
    // command modifier is held — Ctrl+A must stay "select all", not "a".
    if (!control && !modifiers.alt && !_alwaysKeycode.contains(key)) {
      final character = event.character;
      if (character != null &&
          character.isNotEmpty &&
          _isPrintable(character)) {
        return ScrcpyInjectText(character);
      }
    }

    if (keycode == null) return const ScrcpyIgnoreKey();

    final repeat = event is KeyRepeatEvent ? (_repeats[key.keyId] ?? 0) + 1 : 0;
    _repeats[key.keyId] = repeat;
    _pressed[key.keyId] = keycode;
    return ScrcpyInjectKeycode(
      keycode,
      down: true,
      metaState: metaState,
      repeat: repeat,
    );
  }

  /// Key-ups for everything still held, for when the mirror loses focus.
  List<ScrcpyKeyCommand> releaseAll() {
    final ups = [
      for (final keycode in _pressed.values)
        ScrcpyInjectKeycode(keycode, down: false),
    ];
    _pressed.clear();
    _repeats.clear();
    return ups;
  }

  static int _metaStateFor(ScrcpyModifiers modifiers, bool metaShortcut) {
    var state = AndroidMetaState.none;
    if (modifiers.shift) state |= AndroidMetaState.shiftOn;
    if (modifiers.alt) state |= AndroidMetaState.altOn;
    if (modifiers.control || metaShortcut) state |= AndroidMetaState.ctrlOn;
    return state;
  }

  static bool _isPrintable(String character) {
    final code = character.codeUnitAt(0);
    return code >= 0x20 && code != 0x7F;
  }
}

/// Android `KeyEvent` keycode for a desktop [key], or null when the device has
/// no equivalent.
int? androidKeycodeFor(LogicalKeyboardKey key) => _keycodes[key];

final Map<LogicalKeyboardKey, int> _keycodes = {
  // Digits and letters.
  LogicalKeyboardKey.digit0: 7,
  LogicalKeyboardKey.digit1: 8,
  LogicalKeyboardKey.digit2: 9,
  LogicalKeyboardKey.digit3: 10,
  LogicalKeyboardKey.digit4: 11,
  LogicalKeyboardKey.digit5: 12,
  LogicalKeyboardKey.digit6: 13,
  LogicalKeyboardKey.digit7: 14,
  LogicalKeyboardKey.digit8: 15,
  LogicalKeyboardKey.digit9: 16,
  LogicalKeyboardKey.keyA: 29,
  LogicalKeyboardKey.keyB: 30,
  LogicalKeyboardKey.keyC: 31,
  LogicalKeyboardKey.keyD: 32,
  LogicalKeyboardKey.keyE: 33,
  LogicalKeyboardKey.keyF: 34,
  LogicalKeyboardKey.keyG: 35,
  LogicalKeyboardKey.keyH: 36,
  LogicalKeyboardKey.keyI: 37,
  LogicalKeyboardKey.keyJ: 38,
  LogicalKeyboardKey.keyK: 39,
  LogicalKeyboardKey.keyL: 40,
  LogicalKeyboardKey.keyM: 41,
  LogicalKeyboardKey.keyN: 42,
  LogicalKeyboardKey.keyO: 43,
  LogicalKeyboardKey.keyP: 44,
  LogicalKeyboardKey.keyQ: 45,
  LogicalKeyboardKey.keyR: 46,
  LogicalKeyboardKey.keyS: 47,
  LogicalKeyboardKey.keyT: 48,
  LogicalKeyboardKey.keyU: 49,
  LogicalKeyboardKey.keyV: 50,
  LogicalKeyboardKey.keyW: 51,
  LogicalKeyboardKey.keyX: 52,
  LogicalKeyboardKey.keyY: 53,
  LogicalKeyboardKey.keyZ: 54,

  // Navigation and editing.
  LogicalKeyboardKey.arrowUp: 19,
  LogicalKeyboardKey.arrowDown: 20,
  LogicalKeyboardKey.arrowLeft: 21,
  LogicalKeyboardKey.arrowRight: 22,
  LogicalKeyboardKey.tab: 61,
  LogicalKeyboardKey.space: 62,
  LogicalKeyboardKey.enter: 66,
  LogicalKeyboardKey.backspace: 67,
  LogicalKeyboardKey.pageUp: 92,
  LogicalKeyboardKey.pageDown: 93,
  LogicalKeyboardKey.escape: 111,
  LogicalKeyboardKey.delete: 112,
  LogicalKeyboardKey.home: 122,
  LogicalKeyboardKey.end: 123,
  LogicalKeyboardKey.insert: 124,
  LogicalKeyboardKey.contextMenu: 82,

  // Punctuation (US layout fallbacks; printable keys normally go as text).
  LogicalKeyboardKey.comma: 55,
  LogicalKeyboardKey.period: 56,
  LogicalKeyboardKey.backquote: 68,
  LogicalKeyboardKey.minus: 69,
  LogicalKeyboardKey.equal: 70,
  LogicalKeyboardKey.bracketLeft: 71,
  LogicalKeyboardKey.bracketRight: 72,
  LogicalKeyboardKey.backslash: 73,
  LogicalKeyboardKey.semicolon: 74,
  LogicalKeyboardKey.quote: 75,
  LogicalKeyboardKey.slash: 76,

  // Modifiers (only reached through an explicit keycode request).
  LogicalKeyboardKey.altLeft: 57,
  LogicalKeyboardKey.altRight: 58,
  LogicalKeyboardKey.shiftLeft: 59,
  LogicalKeyboardKey.shiftRight: 60,
  LogicalKeyboardKey.controlLeft: 113,
  LogicalKeyboardKey.controlRight: 114,
  LogicalKeyboardKey.capsLock: 115,
  LogicalKeyboardKey.metaLeft: 117,
  LogicalKeyboardKey.metaRight: 118,

  // Function row.
  LogicalKeyboardKey.f1: 131,
  LogicalKeyboardKey.f2: 132,
  LogicalKeyboardKey.f3: 133,
  LogicalKeyboardKey.f4: 134,
  LogicalKeyboardKey.f5: 135,
  LogicalKeyboardKey.f6: 136,
  LogicalKeyboardKey.f7: 137,
  LogicalKeyboardKey.f8: 138,
  LogicalKeyboardKey.f9: 139,
  LogicalKeyboardKey.f10: 140,
  LogicalKeyboardKey.f11: 141,
  LogicalKeyboardKey.f12: 142,

  // Numeric keypad.
  LogicalKeyboardKey.numLock: 143,
  LogicalKeyboardKey.numpad0: 144,
  LogicalKeyboardKey.numpad1: 145,
  LogicalKeyboardKey.numpad2: 146,
  LogicalKeyboardKey.numpad3: 147,
  LogicalKeyboardKey.numpad4: 148,
  LogicalKeyboardKey.numpad5: 149,
  LogicalKeyboardKey.numpad6: 150,
  LogicalKeyboardKey.numpad7: 151,
  LogicalKeyboardKey.numpad8: 152,
  LogicalKeyboardKey.numpad9: 153,
  LogicalKeyboardKey.numpadDivide: 154,
  LogicalKeyboardKey.numpadMultiply: 155,
  LogicalKeyboardKey.numpadSubtract: 156,
  LogicalKeyboardKey.numpadAdd: 157,
  LogicalKeyboardKey.numpadDecimal: 158,
  LogicalKeyboardKey.numpadComma: 159,
  LogicalKeyboardKey.numpadEnter: 160,
  LogicalKeyboardKey.numpadEqual: 161,
};
