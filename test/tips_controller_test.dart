import 'package:eagly/features/tips/tip.dart';
import 'package:eagly/features/tips/tips_controller.dart';
import 'package:eagly/features/tips/tips_data.dart';
import 'package:eagly/services/preferences_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _tips = [
  Tip(id: 'a', icon: Icons.abc, title: 'A', detail: 'detail a'),
  Tip(id: 'b', icon: Icons.abc, title: 'B', detail: 'detail b'),
  Tip(id: 'c', icon: Icons.abc, title: 'C', detail: 'detail c'),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesService.init();
  });

  test('shows the first tip and is visible by default', () {
    final controller = TipsController(tips: _tips);
    addTearDown(controller.dispose);

    expect(controller.currentTip?.id, 'a');
    expect(controller.visible, isTrue);
    expect(controller.enabled, isTrue);
  });

  test('rotates to a new tip on each construction (per app launch)', () {
    TipsController(tips: _tips).dispose();
    expect(TipsController(tips: _tips).currentTip?.id, 'b');
    expect(TipsController(tips: _tips).currentTip?.id, 'c');
    // Wraps back around to the start.
    expect(TipsController(tips: _tips).currentTip?.id, 'a');
  });

  test('dismissForSession hides the panel without persisting', () {
    final controller = TipsController(tips: _tips);
    addTearDown(controller.dispose);

    controller.dismissForSession();

    expect(controller.visible, isFalse);
    // Still enabled — it should come back next launch.
    expect(controller.enabled, isTrue);
    expect(PreferencesService.tipsEnabled, isTrue);
  });

  test('showNextTip cycles through the pool in session', () {
    final controller = TipsController(tips: _tips);
    addTearDown(controller.dispose);

    final first = controller.currentTip?.id;
    controller.showNextTip();
    final second = controller.currentTip?.id;

    expect(second, isNot(first));
  });

  test('showPreviousTip cycles backwards and wraps around', () {
    final controller = TipsController(tips: _tips);
    addTearDown(controller.dispose);

    expect(controller.currentTip?.id, 'a');
    // Wraps to the end of the pool.
    controller.showPreviousTip();
    expect(controller.currentTip?.id, 'c');
    controller.showPreviousTip();
    expect(controller.currentTip?.id, 'b');
    // ...and back forwards again.
    controller.showNextTip();
    expect(controller.currentTip?.id, 'c');
  });

  test('navigation is inert and hidden with fewer than two tips', () {
    final single = TipsController(tips: [_tips.first]);
    addTearDown(single.dispose);

    expect(single.hasMultipleTips, isFalse);
    single.showNextTip();
    single.showPreviousTip();
    expect(single.currentTip?.id, 'a');

    final multi = TipsController(tips: _tips);
    addTearDown(multi.dispose);
    expect(multi.hasMultipleTips, isTrue);
  });

  test('disablePermanently persists and hides for good', () {
    final controller = TipsController(tips: _tips);
    addTearDown(controller.dispose);

    controller.disablePermanently();

    expect(controller.enabled, isFalse);
    expect(controller.visible, isFalse);
    expect(PreferencesService.tipsEnabled, isFalse);

    // A fresh controller (next launch) also stays hidden.
    final next = TipsController(tips: _tips);
    addTearDown(next.dispose);
    expect(next.enabled, isFalse);
    expect(next.visible, isFalse);
  });

  test('re-enabling via the preference brings the panel back live', () {
    final controller = TipsController(tips: _tips);
    addTearDown(controller.dispose);

    controller.dismissForSession();
    controller.disablePermanently();
    expect(controller.visible, isFalse);

    // Simulate the Settings toggle flipping it back on.
    PreferencesService.tipsEnabled = true;

    expect(controller.enabled, isTrue);
    expect(controller.visible, isTrue);
  });

  test('notifies listeners on state changes', () {
    final controller = TipsController(tips: _tips);
    addTearDown(controller.dispose);

    var notifications = 0;
    controller.addListener(() => notifications++);

    controller.showNextTip();
    controller.dismissForSession();
    controller.disablePermanently();

    expect(notifications, greaterThanOrEqualTo(3));
  });

  test('the shipped tip pool is non-empty and uniquely keyed', () {
    expect(kTips, isNotEmpty);
    final ids = kTips.map((t) => t.id).toSet();
    expect(ids.length, kTips.length);
  });
}
