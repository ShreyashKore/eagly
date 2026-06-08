import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';

import '../../intents/intents.dart';

const homePageShortcuts = <ShortcutActivator, Intent>{
  SingleActivator(LogicalKeyboardKey.keyF, control: true):
      ActivateSearchIntent(),
  SingleActivator(LogicalKeyboardKey.keyF, meta: true): ActivateSearchIntent(),
  SingleActivator(LogicalKeyboardKey.minus, control: true):
      DecreaseFontIntent(),
  SingleActivator(LogicalKeyboardKey.minus, meta: true): DecreaseFontIntent(),
  SingleActivator(LogicalKeyboardKey.equal, control: true):
      IncreaseFontIntent(),
  SingleActivator(LogicalKeyboardKey.equal, meta: true): IncreaseFontIntent(),
  SingleActivator(LogicalKeyboardKey.numpadAdd, control: true):
      IncreaseFontIntent(),
  SingleActivator(LogicalKeyboardKey.numpadAdd, meta: true):
      IncreaseFontIntent(),
};
