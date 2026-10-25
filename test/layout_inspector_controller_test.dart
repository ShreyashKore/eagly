import 'dart:ui';

import 'package:eagly/data/device.dart';
import 'package:eagly/features/layout_inspector/data/layout_parsers.dart';
import 'package:eagly/features/layout_inspector/data/layout_snapshot.dart';
import 'package:eagly/features/layout_inspector/data/view_hierarchy.dart';
import 'package:eagly/features/layout_inspector/layout_inspector_controller.dart';
import 'package:eagly/features/layout_inspector/services/inspector_helper.dart';
import 'package:eagly/services/preferences_service.dart';
import 'package:eagly/session/device_session_controller.dart';
import 'package:eagly/session/workspace_layout.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/layout_inspector_test_support.dart';
import 'support/session_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  DeviceSessionController? session;
  late FakeSessionService service;
  late List<FakeHelperProcess> helpers;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesService.init();
  });

  Device android() => Device(
    'emulator-5554',
    'device',
    platform: DevicePlatform.android,
    model: 'Pixel 8',
  );

  /// A controller whose helper starts unless [helper] is false, answering
  /// snapshots with [helperSnapshotResult].
  LayoutInspectorController create({bool helper = true}) {
    helpers = [];
    service = FakeSessionService(android())
      ..viewHierarchy = ViewHierarchy.parse(dumpsysActivityTop)
      ..uiAutomatorLayout = () => parseUiAutomatorDump(
        uiautomatorDumpOutput,
        displaySize: const Size(2400, 1080),
        capturedAt: DateTime.now(),
      );
    if (helper) {
      service.startHelper = () {
        final process = FakeHelperProcess(
          respond: (method, params) =>
              method == 'snapshot' ? helperSnapshotResult() : null,
        );
        helpers.add(process);
        return InspectorHelper.attach(process);
      };
    }
    session = DeviceSessionController(device: android(), service: service);
    return session!.layoutInspectorController;
  }

  /// Opens the pane, which captures, and waits for that capture.
  Future<void> open(LayoutInspectorController controller) async {
    session!.openPane(WorkspacePane.layoutInspector);
    await settle(controller);
  }

  setUp(
    () => LayoutInspectorController.helperLinger = const Duration(seconds: 20),
  );

  tearDown(() {
    session?.dispose();
    session = null;
    LayoutInspectorController.helperLinger = const Duration(seconds: 20);
  });

  test(
    'opening the pane captures through the helper, with View classes',
    () async {
      final controller = create();
      await open(controller);

      final snapshot = controller.snapshot!;
      expect(snapshot.source, LayoutSource.helper);
      expect(snapshot.nodeByKey('1.1')!.view?.shortClassName, 'MaterialButton');
      expect(controller.error, isNull);
      expect(helpers.single.methods, ['snapshot']);
    },
  );

  test('the helper is reused within the linger, then let go', () async {
    LayoutInspectorController.helperLinger = const Duration(milliseconds: 40);
    final controller = create();
    await open(controller);
    await controller.capture();
    expect(service.helperStarts, 1);
    expect(helpers.single.methods, ['snapshot', 'snapshot']);
    expect(helpers.single.hasExited, isFalse);

    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(
      helpers.single.hasExited,
      isTrue,
      reason: 'an idle helper holds UI Automation from tests and Appium',
    );
  });

  test(
    'a helper that can\'t start falls back to uiautomator, and says so',
    () async {
      final controller = create(helper: false);
      await open(controller);

      expect(controller.snapshot!.source, LayoutSource.uiautomator);
      expect(controller.notice, contains('Using uiautomator'));
      expect(controller.canGoLive, isFalse);

      await controller.capture();
      expect(service.helperStarts, 1, reason: 'not retried every capture');
      expect(service.uiAutomatorCaptures, 2);
    },
  );

  test('UI Automation in use elsewhere is an error, not a fallback', () async {
    final controller = create(helper: false);
    service.startHelper = () => InspectorHelper.attach(
      FakeHelperProcess(sayHello: false)..send({
        'event': 'error',
        'code': 'busy',
        'message': 'UiAutomationService … already registered!',
      }),
    );
    await open(controller);

    expect(controller.snapshot, isNull);
    expect(controller.error, contains('Another tool is using UI Automation'));
    expect(service.uiAutomatorCaptures, 0);

    // Once the other tool is done, the next capture works.
    service.startHelper = () {
      final process = FakeHelperProcess(
        respond: (method, _) =>
            method == 'snapshot' ? helperSnapshotResult() : null,
      );
      helpers.add(process);
      return InspectorHelper.attach(process);
    };
    await controller.capture();
    expect(controller.snapshot?.source, LayoutSource.helper);
    expect(controller.error, isNull);
  });

  test('closing the pane lets the helper go at once', () async {
    final controller = create();
    await open(controller);
    session!.closePane(WorkspacePane.layoutInspector);
    await pumpEventQueue();
    expect(helpers.single.hasExited, isTrue);
  });

  test('a device that drops lets the helper go', () async {
    final controller = create();
    await open(controller);
    session!.updateDevice(
      android().copyWith(connectionState: DeviceConnectionState.disconnected),
    );
    await pumpEventQueue();
    expect(helpers.single.hasExited, isTrue);
    expect(controller.canGoLive, isFalse);
  });

  group('live', () {
    test('a change on the device is followed by a capture', () async {
      final controller = create();
      await open(controller);
      await controller.setLive(true);
      await settle(controller);
      final helper = helpers.single;
      expect(helper.methods, ['snapshot', 'watch', 'snapshot']);
      expect(helper.requests[1]['params'], {'enabled': true});

      helper.sendChanged();
      await pumpEventQueue();
      await settle(controller);
      expect(helper.methods.where((m) => m == 'snapshot'), hasLength(3));

      await controller.setLive(false);
      await pumpEventQueue();
      expect(helper.methods.last, 'watch');
      expect(helper.requests.last['params'], {'enabled': false});
      helper.sendChanged();
      await pumpEventQueue();
      expect(helper.methods.where((m) => m == 'snapshot'), hasLength(3));
    });

    test('a helper that dies stops live updates and says why', () async {
      final controller = create();
      await open(controller);
      await controller.setLive(true);
      await settle(controller);

      helpers.single
        ..writeStderr('java.lang.RuntimeException: boom')
        ..exit(1);
      await pumpEventQueue();
      expect(controller.live, isFalse);
      expect(controller.notice, contains('Live updates stopped'));
    });
  });

  group('selection and the tree', () {
    test('a selection survives a refresh', () async {
      final controller = create();
      await open(controller);
      final button = controller.nodeAt(const Offset(500, 2200))!;
      controller.select(button);
      await controller.capture();

      expect(controller.selected, isNot(same(button)));
      expect(controller.selected?.key, button.key);
    });

    test(
      'system windows start folded; selecting unfolds the way down',
      () async {
        final controller = create();
        await open(controller);
        List<String> keys() => [
          for (final row in controller.treeRows)
            if (row is LayoutNodeRow) row.node.key,
        ];
        expect(keys(), ['0', '1', '1.0', '1.1']);

        controller.toggleCollapsed(controller.snapshot!.nodeByKey('1')!);
        expect(keys(), ['0', '1']);
        controller.select(controller.snapshot!.nodeByKey('1.1'));
        expect(keys(), ['0', '1', '1.0', '1.1']);
      },
    );

    test('a search keeps matches and the nodes above them', () async {
      final controller = create();
      await open(controller);
      controller.setQuery('materialbutton');
      final rows = controller.treeRows;
      expect(
        rows.whereType<LayoutWindowRow>().single.window.type,
        'application',
      );
      expect(
        [for (final row in rows.whereType<LayoutNodeRow>()) row.node.key],
        ['1', '1.1'],
      );
    });
  });
}

/// Waits for the capture in flight, if any.
Future<void> settle(LayoutInspectorController controller) async {
  for (var i = 0; i < 100 && controller.isCapturing; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  await pumpEventQueue();
}
