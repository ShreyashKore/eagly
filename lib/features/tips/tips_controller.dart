import 'package:flutter/foundation.dart';

import '../../services/preferences_service.dart';
import 'tip.dart';
import 'tips_data.dart';

/// Owns the header tips panel state: which tip is shown this launch, whether the
/// user hid it for the session, and whether tips are enabled at all.
///
/// Created once per app launch (in `HomeScreen`). Constructing it advances the
/// persisted rotation counter, so a different tip surfaces on the next launch —
/// this is what makes "a new tip every time the app is opened" work without any
/// timers or per-frame logic.
class TipsController extends ChangeNotifier {
  TipsController({List<Tip> tips = kTips}) : _tips = tips {
    _enabled = PreferencesService.tipsEnabled;
    if (_tips.isEmpty) {
      _index = 0;
    } else {
      final counter = PreferencesService.tipRotationIndex;
      _index = counter % _tips.length;
      // Advance now so the *next* launch shows the following tip.
      PreferencesService.tipRotationIndex = (counter + 1) % _tips.length;
    }
    // Stay in sync with the Settings toggle so re-enabling there takes effect
    // immediately rather than only on the next launch.
    PreferencesService.tipsEnabledListenable.addListener(_onEnabledChanged);
  }

  final List<Tip> _tips;
  late int _index;
  late bool _enabled;
  bool _dismissed = false;

  void _onEnabledChanged() {
    final value = PreferencesService.tipsEnabledListenable.value;
    if (value == _enabled) return;
    _enabled = value;
    // A fresh enable should bring the panel back even if it was dismissed
    // earlier this session.
    if (value) _dismissed = false;
    notifyListeners();
  }

  @override
  void dispose() {
    PreferencesService.tipsEnabledListenable.removeListener(_onEnabledChanged);
    super.dispose();
  }

  /// The tip surfaced for this launch, or null when there are none.
  Tip? get currentTip => _tips.isEmpty ? null : _tips[_index];

  /// Whether the panel should render: enabled, not dismissed this session, and
  /// a tip exists to show.
  bool get visible => _enabled && !_dismissed && currentTip != null;

  /// Whether tips are enabled at all (the persisted preference).
  bool get enabled => _enabled;

  /// Cycles to the next tip in the pool without persisting — used by the
  /// "Show another tip" affordance so a curious user can browse in place.
  void showNextTip() {
    if (_tips.length < 2) return;
    _index = (_index + 1) % _tips.length;
    notifyListeners();
  }

  /// Hides the panel for the rest of this session only; it returns next launch.
  void dismissForSession() {
    if (_dismissed) return;
    _dismissed = true;
    notifyListeners();
  }

  /// Turns tips off permanently (persisted). Re-enable from Settings.
  void disablePermanently() {
    if (!_enabled) return;
    _enabled = false;
    PreferencesService.tipsEnabled = false;
    notifyListeners();
  }
}
