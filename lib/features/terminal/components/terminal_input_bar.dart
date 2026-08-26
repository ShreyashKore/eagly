import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../data/device.dart';
import '../../../presentation/theme/app_theme.dart';
import '../terminal_controller.dart';

/// The prompt: the target-device label, the command editor, and the run/stop
/// button.
///
/// The editor is multi-line (Enter runs, Shift+Enter adds a line) so a pasted
/// shell one-liner is readable rather than scrolling past a single row. While a
/// command is running the field feeds that process' stdin instead of starting a
/// new command, which is what makes interactive tools (`adb shell` with no
/// arguments) usable. ↑/↓ walk the history, Ctrl+C stops the running command
/// and Ctrl+L clears the scrollback.
class TerminalInputBar extends StatefulWidget {
  const TerminalInputBar({
    super.key,
    required this.controller,
    required this.fontSize,
  });

  final TerminalController controller;
  final double fontSize;

  @override
  State<TerminalInputBar> createState() => _TerminalInputBarState();
}

class _TerminalInputBarState extends State<TerminalInputBar> {
  /// Lines of text the editor shows before it starts scrolling.
  static const int _minLines = 3;
  static const int _maxLines = 10;

  final TextEditingController _input = TextEditingController();
  late final FocusNode _focusNode = FocusNode(onKeyEvent: _onKeyEvent);

  TerminalController get controller => widget.controller;

  @override
  void dispose() {
    _input.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final isControlPressed = HardwareKeyboard.instance.isControlPressed;

    if (isControlPressed && event.logicalKey == LogicalKeyboardKey.keyC) {
      if (!controller.isRunning) return KeyEventResult.ignored;
      unawaited(controller.cancel());
      return KeyEventResult.handled;
    }
    if (isControlPressed && event.logicalKey == LogicalKeyboardKey.keyL) {
      controller.clear();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      // Shift+Enter falls through to the editor so it inserts a line break;
      // a bare Enter is claimed here, which also stops the multi-line field
      // from turning it into one.
      if (HardwareKeyboard.instance.isShiftPressed) {
        return KeyEventResult.ignored;
      }
      _submit();
      return KeyEventResult.handled;
    }
    // ↑/↓ recall history only while the draft is a single line; once it has
    // line breaks they belong to the editor for moving the caret.
    if (!_input.text.contains('\n')) {
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        return _applyHistory(controller.historyPrevious());
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        return _applyHistory(controller.historyNext());
      }
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _applyHistory(String? entry) {
    if (entry == null) return KeyEventResult.ignored;
    _input.value = TextEditingValue(
      text: entry,
      selection: TextSelection.collapsed(offset: entry.length),
    );
    return KeyEventResult.handled;
  }

  void _submit() {
    final text = _input.text;
    if (text.trim().isEmpty) return;
    _input.clear();
    unawaited(controller.submit(text));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final eaglyTheme = context.eaglyTheme;
    final target = controller.targetDevice;
    final isRunning = controller.isRunning;

    final mono = eaglyTheme.monoStyle.copyWith(
      fontSize: widget.fontSize,
      height: 1.45,
      color: theme.colorScheme.onSurface,
    );

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 8),
            child: _PromptLabel(
              device: target,
              isPinned: controller.isPinnedElsewhere,
              isRunning: isRunning,
              style: mono,
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  focusNode: _focusNode,
                  autofocus: true,
                  minLines: _minLines,
                  maxLines: _maxLines,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  // Enter is claimed by [_onKeyEvent]; this covers the platforms
                  // that report submission as an action instead of a key.
                  onSubmitted: (_) => _submit(),
                  style: mono,
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: isRunning
                        ? 'Sending to ${controller.runningCommand} — Ctrl+C to stop'
                        : target.isConnected
                        ? 'adb shell …  ·  help\nEnter runs · Shift+Enter adds a line'
                        : '${target.displayName} is disconnected',
                    hintMaxLines: 2,
                    hintStyle: mono.copyWith(
                      color: theme.colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.7,
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              if (isRunning)
                IconButton(
                  tooltip: 'Stop (Ctrl+C)',
                  onPressed: () => unawaited(controller.cancel()),
                  icon: Icon(
                    Icons.stop_circle_outlined,
                    color: eaglyTheme.errorColor,
                  ),
                )
              else
                IconButton(
                  tooltip: 'Run (Enter)',
                  onPressed: _submit,
                  icon: const Icon(Icons.keyboard_return),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The `<device> $` prefix, dimmed while the device is unreachable.
class _PromptLabel extends StatelessWidget {
  const _PromptLabel({
    required this.device,
    required this.isPinned,
    required this.isRunning,
    required this.style,
  });

  final Device device;
  final bool isPinned;
  final bool isRunning;

  /// The editor's own mono style, so the prompt sits on its baseline.
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = device.isConnected
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;

    return Tooltip(
      message: isPinned
          ? 'Pinned to ${device.displayName} (${device.id}) — `use auto` to '
                'follow this tab\'s device'
          : '${device.displayName} (${device.id})',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isPinned) ...[
            Icon(Icons.push_pin_outlined, size: 13, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            device.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style.copyWith(fontWeight: FontWeight.w600, color: color),
          ),
          const SizedBox(width: 6),
          Text(
            isRunning ? '»' : r'$',
            style: style.copyWith(
              fontWeight: FontWeight.w600,
              color: color.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}
