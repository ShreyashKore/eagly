import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:eagly/features/layout_inspector/data/layout_parsers.dart';
import 'package:eagly/features/layout_inspector/data/layout_selectors.dart';
import 'package:eagly/features/layout_inspector/data/layout_snapshot.dart';
import 'package:eagly/features/layout_inspector/data/view_hierarchy.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/layout_inspector_test_support.dart';

LayoutSnapshot _helperSnapshot({String buttonText = 'Sign in'}) =>
    parseHelperSnapshot(
      helperSnapshotResult(buttonText: buttonText),
      capturedAt: DateTime(2026, 10, 25),
    );

void main() {
  group('uiautomator dump', () {
    test('reads nodes, ids, text and flags, and drops the trailer', () {
      final snapshot = parseUiAutomatorDump(
        uiautomatorDumpOutput,
        displaySize: const Size(2400, 1080),
        capturedAt: DateTime(2026, 10, 25),
      );
      expect(snapshot.source, LayoutSource.uiautomator);
      expect(snapshot.rotation, 1);
      expect(snapshot.windows, hasLength(1));
      final root = snapshot.windows.single.root!;
      expect(root.key, '0');
      final greeting = root.children.first;
      expect(greeting.key, '0.0');
      expect(greeting.parent, root);
      expect(greeting.text, 'Say "hi"');
      expect(greeting.resourceEntry, 'greeting');
      expect(greeting.bounds, const Rect.fromLTRB(100, 100, 700, 200));
      expect(greeting.flags, containsAll(['clickable', 'focusable']));
      expect(greeting.hasFlag('checked'), isFalse);
      expect(root.children.last.contentDescription, 'Profile');
    });

    test('a dump that failed is a FormatException carrying its message', () {
      expect(
        () => parseUiAutomatorDump(
          'ERROR: could not get idle state.\n',
          displaySize: const Size(1080, 2400),
          capturedAt: DateTime(2026, 10, 25),
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('could not get idle state'),
          ),
        ),
      );
    });
  });

  group('helper snapshot', () {
    test('windows top-most first, keyed by position, with the display', () {
      final snapshot = _helperSnapshot();
      expect(snapshot.source, LayoutSource.helper);
      expect(snapshot.windows.map((window) => window.type), [
        'system',
        'application',
      ]);
      expect(snapshot.windows.last.label, 'Example (application)');
      expect(snapshot.displaySize, const Size(1080, 2400));
      expect(snapshot.densityDpi, 420);
      expect(snapshot.nodeByKey('1.1')?.text, 'Sign in');
      expect(snapshot.nodeCount, 4);
    });

    test('decodes the screenshot', () {
      final result = helperSnapshotResult()
        ..['screenshot'] = base64Encode([1, 2, 3]);
      final snapshot = parseHelperSnapshot(
        result,
        capturedAt: DateTime(2026, 10, 25),
      );
      expect(snapshot.screenshot, [1, 2, 3]);
    });
  });

  group('hit testing', () {
    test('the smallest visible node under the point wins', () {
      final snapshot = parseUiAutomatorDump(
        uiautomatorDumpOutput,
        displaySize: const Size(2400, 1080),
        capturedAt: DateTime(2026, 10, 25),
      );
      // The image covers the whole window, after the text: the text is
      // still the one picked, being smaller.
      expect(
        snapshot.hitTest(const Offset(150, 150))?.resourceEntry,
        'greeting',
      );
      expect(
        snapshot.hitTest(const Offset(1500, 900))?.contentDescription,
        'Profile',
      );
    });

    test('a window on top takes the point first', () {
      final snapshot = _helperSnapshot();
      expect(
        snapshot.hitTest(const Offset(10, 10))?.packageName,
        'com.android.systemui',
      );
      expect(snapshot.hitTest(const Offset(500, 2200))?.text, 'Sign in');
    });

    test('a node found again in the next snapshot', () {
      final before = _helperSnapshot();
      final after = _helperSnapshot(buttonText: 'Signing in…');
      final button = before.nodeByKey('1.1')!;
      expect(after.find(button)?.text, 'Signing in…');
    });
  });

  group('dumpsys activity top', () {
    test('parses the resumed activity, not the task behind it', () {
      final views = ViewHierarchy.parse(dumpsysActivityTop)!;
      expect(views.activity, 'com.example.app/.MainActivity');
      expect(views.packageName, 'com.example.app');
      final all = views.roots.single.descendantsAndSelf.toList();
      // A drawable holder line between views is skipped.
      expect(all.map((view) => view.shortClassName), [
        'DecorView',
        'LinearLayout',
        'ViewStub',
        'HeaderView',
        'MaterialButton',
      ]);
      final button = all.last;
      expect(button.resourceName, 'app:id/sign_in');
      expect(button.resourceEntry, 'sign_in');
      expect(button.bounds, const Rect.fromLTRB(48, 2100, 1032, 2244));
      expect(button.flagNames, containsAll(['focusable', 'clickable']));
      expect(button.flagNames, contains('pressed'));
      expect(all[2].visibility, 'gone');
      expect(all.first.bounds, const Rect.fromLTRB(0, 0, 1080, 2400));
    });

    test('bounds add up from parent-relative ones', () {
      const dump = '''
  ACTIVITY com.example.app/.MainActivity 1 pid=1
      mResumed=true mStopped=false mFinished=false
    View Hierarchy:
      DecorView@1[MainActivity]
        android.widget.FrameLayout{1 V.E...... ........ 0,100-1080,2400}
          android.widget.LinearLayout{2 V.E...... ........ 20,30-500,600}
            android.widget.TextView{3 V.ED..... ........ 5,5-105,55 #7f01 app:id/label}
''';
      final views = ViewHierarchy.parse(dump)!;
      final label = views.roots.single.descendantsAndSelf.last;
      expect(label.bounds, const Rect.fromLTRB(25, 135, 125, 185));
    });

    test('no View tree at all is null', () {
      expect(ViewHierarchy.parse('nothing here'), isNull);
    });

    test('annotate pairs nodes with the Views they came from', () {
      final snapshot = _helperSnapshot();
      ViewHierarchy.parse(dumpsysActivityTop)!.annotate(snapshot);
      final title = snapshot.nodeByKey('1.0')!;
      final button = snapshot.nodeByKey('1.1')!;
      expect(title.view?.className, 'com.example.app.ui.HeaderView');
      expect(button.view?.shortClassName, 'MaterialButton');
      expect(button.label, 'MaterialButton #sign_in "Sign in"');
      // Another app's window is left alone.
      expect(snapshot.nodeByKey('0')!.view, isNull);
    });

    test('annotate refuses a pair whose ids disagree', () {
      final snapshot = _helperSnapshot();
      final dump = dumpsysActivityTop.replaceFirst(
        'app:id/sign_in',
        'app:id/register',
      );
      ViewHierarchy.parse(dump)!.annotate(snapshot);
      expect(snapshot.nodeByKey('1.1')!.view, isNull);
    });
  });

  group('selectors', () {
    test('an Android resource id leads, with each framework\'s form', () {
      final snapshot = _helperSnapshot();
      final button = snapshot.nodeByKey('1.1')!;
      final selectors = {
        for (final selector in selectorsFor(button, snapshot))
          selector.label: selector.value,
      };
      expect(selectors['Resource id'], 'com.example.app:id/sign_in');
      expect(
        selectors['XPath'],
        '//*[@resource-id="com.example.app:id/sign_in"]',
      );
      expect(selectors['UiAutomator'], 'By.res("com.example.app:id/sign_in")');
      expect(selectors['Espresso'], 'onView(withId(R.id.sign_in))');
      expect(selectors['Maestro'], 'id: "com.example.app:id/sign_in"');
      expect(selectors.containsKey('Compose test'), isFalse);
    });

    test('a bare id is a testID or testTag, not an R.id', () {
      final result = helperSnapshotResult();
      final app = (result['windows'] as List)[1] as Map;
      final children = (app['root'] as Map)['children'] as List;
      (children[1] as Map)['resourceId'] = 'signInButton';
      final snapshot = parseHelperSnapshot(
        result,
        capturedAt: DateTime(2026, 10, 25),
      );
      final labels = {
        for (final selector in selectorsFor(
          snapshot.nodeByKey('1.1')!,
          snapshot,
        ))
          selector.label: selector.value,
      };
      expect(
        labels['Compose test'],
        'composeTestRule.onNodeWithTag("signInButton")',
      );
      expect(labels['Espresso'], 'onView(withText("Sign in"))');
    });

    test('XPath quotes a value holding double quotes with single ones', () {
      final snapshot = parseUiAutomatorDump(
        uiautomatorDumpOutput.replaceFirst(
          'content-desc="Profile"',
          'content-desc="Say &quot;hi&quot;"',
        ),
        displaySize: const Size(2400, 1080),
        capturedAt: DateTime(2026, 10, 25),
      );
      expect(
        xpathFor(snapshot.nodeByKey('0.1')!, snapshot),
        '//android.widget.ImageView[@content-desc=\'Say "hi"\']',
      );
    });

    test('XPath numbers a handle that isn\'t unique', () {
      final result = helperSnapshotResult();
      final app = (result['windows'] as List)[1] as Map;
      final children = (app['root'] as Map)['children'] as List;
      (children[0] as Map)['resourceId'] = 'com.example.app:id/sign_in';
      final snapshot = parseHelperSnapshot(
        result,
        capturedAt: DateTime(2026, 10, 25),
      );
      expect(
        xpathFor(snapshot.nodeByKey('1.1')!, snapshot),
        '(//*[@resource-id="com.example.app:id/sign_in"])[2]',
      );
    });

    test('XPath falls back to the position', () {
      final snapshot = _helperSnapshot();
      final root = snapshot.nodeByKey('1')!;
      expect(xpathFor(root, snapshot), '/hierarchy/android.widget.FrameLayout');
    });
  });

  test('pngSize reads the IHDR chunk', () {
    final png = Uint8List.fromList([
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
      0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52, //
      0, 0, 0x04, 0x38, 0, 0, 0x09, 0x60,
    ]);
    expect(pngSize(png), const Size(1080, 2400));
    expect(pngSize(Uint8List.fromList([1, 2, 3])), isNull);
  });
}
