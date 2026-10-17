import 'package:eagly/data/device.dart';
import 'package:eagly/features/file_manager/components/file_manager_toolbar.dart';
import 'package:eagly/features/home_screen/components/device_screen_content.dart';
import 'package:eagly/features/home_screen/components/workspace_chrome.dart';
import 'package:eagly/features/home_screen/components/workspace_view.dart';
import 'package:eagly/features/logs/presentation/components/toolbar.dart';
import 'package:eagly/presentation/components/feature_view.dart';
import 'package:eagly/presentation/components/overflow_toolbar.dart';
import 'package:eagly/presentation/components/workspace_pane_scope.dart';
import 'package:eagly/presentation/theme/app_theme.dart';
import 'package:eagly/services/preferences_service.dart';
import 'package:eagly/session/device_session_controller.dart';
import 'package:eagly/session/workspace_layout.dart';
import 'package:fl_panel/fl_panel.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/session_test_support.dart';
import 'support/workspace_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesService.init();
  });

  void useWindow(WidgetTester tester, [Size size = const Size(1200, 800)]) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  WorkspaceLayout createLayout(List<WorkspacePane> open) {
    final layout = WorkspaceLayout();
    addTearDown(layout.dispose);
    open.forEach(layout.show);
    return layout;
  }

  Future<void> pumpWorkspace(WidgetTester tester, WorkspaceLayout layout) =>
      tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: WorkspaceView(
              layout: layout,
              paneBuilder: (context, pane) =>
                  _TestPane(pane: pane, onClose: () => layout.hide(pane)),
            ),
          ),
        ),
      );

  Finder paneOf(WorkspacePane pane) =>
      find.byKey(ValueKey('pane.${pane.id}'), skipOffstage: false);

  Finder gripOf(WorkspacePane pane) => find.descendant(
    of: paneOf(pane),
    matching: find.byIcon(Icons.drag_indicator),
  );

  /// Drags [pane] by its grip to [to], pausing over it so the drop target
  /// resolves. Returns the gesture still held, for checks before the drop.
  Future<TestGesture> dragGripTo(
    WidgetTester tester,
    WorkspacePane pane,
    Offset to,
  ) async {
    final gesture = await tester.startGesture(
      tester.getCenter(gripOf(pane)),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(24, 0));
    await tester.pump();
    await gesture.moveTo(to);
    await tester.pump();
    return gesture;
  }

  group('WorkspaceView', () {
    testWidgets('panes sit side by side, each with a grip once there are two', (
      tester,
    ) async {
      useWindow(tester);
      final layout = createLayout([WorkspacePane.logs]);
      await pumpWorkspace(tester, layout);

      // Alone, a pane has nowhere to go: no grip, its header as before.
      expect(gripOf(WorkspacePane.logs), findsNothing);

      layout.show(WorkspacePane.mirror);
      await tester.pump();

      expect(gripOf(WorkspacePane.logs), findsOneWidget);
      expect(gripOf(WorkspacePane.mirror), findsOneWidget);
      final logs = tester.getRect(paneOf(WorkspacePane.logs));
      final mirror = tester.getRect(paneOf(WorkspacePane.mirror));
      expect(logs.right, lessThan(mirror.left));
      expect(logs.top, mirror.top);
    });

    testWidgets(
      'dropping a pane on the lower edge of another stacks it below',
      (tester) async {
        useWindow(tester);
        final layout = createLayout([WorkspacePane.logs, WorkspacePane.mirror]);
        await pumpWorkspace(tester, layout);

        final logs = tester.getRect(paneOf(WorkspacePane.logs));
        final gesture = await dragGripTo(
          tester,
          WorkspacePane.mirror,
          Offset(logs.center.dx, logs.bottom - 100),
        );

        // The label under the pointer says what the drop will do.
        expect(find.text('Place below Logs'), findsOneWidget);
        expect(describe(layout.root), 'row(logs, mirror)');

        await gesture.up();
        await tester.pump();

        expect(describe(layout.root), 'column(logs, mirror)');
        expect(find.text('Place below Logs'), findsNothing);
        expect(
          tester.getRect(paneOf(WorkspacePane.mirror)).top,
          greaterThan(tester.getRect(paneOf(WorkspacePane.logs)).bottom),
        );
      },
    );

    testWidgets('dropping on the middle of a pane groups them as tabs, '
        'and the moved pane keeps its state', (tester) async {
      useWindow(tester);
      final layout = createLayout([WorkspacePane.logs, WorkspacePane.mirror]);
      await pumpWorkspace(tester, layout);
      await tester.enterText(
        find.descendant(
          of: paneOf(WorkspacePane.mirror),
          matching: find.byType(TextField),
        ),
        'typed before the move',
      );

      final logs = tester.getRect(paneOf(WorkspacePane.logs));
      final gesture = await dragGripTo(
        tester,
        WorkspacePane.mirror,
        logs.center,
      );
      expect(find.text('Group as tabs with Logs'), findsOneWidget);
      await gesture.up();
      await tester.pump();

      expect(describe(layout.root), 'tabs(logs, *mirror)');
      // The chips show the titles and close buttons, so the headers don't.
      final chips = find.byType(TabChip);
      expect(chips, findsNWidgets(2));
      expect(
        find.descendant(
          of: paneOf(WorkspacePane.mirror),
          matching: find.text('Mirror'),
        ),
        findsNothing,
      );
      expect(find.text('typed before the move'), findsOneWidget);

      await tester.tap(find.descendant(of: chips, matching: find.text('Logs')));
      await tester.pump();
      expect(layout.isShown(WorkspacePane.logs), isTrue);
      // Behind the Logs tab, still mounted with its state.
      expect(
        find.text('typed before the move', skipOffstage: false),
        findsOneWidget,
      );
    });

    testWidgets('Escape abandons a drag', (tester) async {
      useWindow(tester);
      final layout = createLayout([WorkspacePane.logs, WorkspacePane.mirror]);
      await pumpWorkspace(tester, layout);

      final logs = tester.getRect(paneOf(WorkspacePane.logs));
      final gesture = await dragGripTo(
        tester,
        WorkspacePane.mirror,
        logs.center,
      );
      expect(layout.panels.drag, isNotNull);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(layout.panels.drag, isNull);
      expect(find.byKey(const ValueKey('workspace.dragLabel')), findsNothing);

      await gesture.moveBy(const Offset(5, 5));
      await gesture.up();
      await tester.pump();
      expect(describe(layout.root), 'row(logs, mirror)');
    });

    testWidgets('a short wobble on the grip is a click, opening its menu', (
      tester,
    ) async {
      useWindow(tester);
      final layout = createLayout([WorkspacePane.logs, WorkspacePane.mirror]);
      await pumpWorkspace(tester, layout);

      final gesture = await tester.startGesture(
        tester.getCenter(gripOf(WorkspacePane.logs)),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(12, 8));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(layout.panels.drag, isNull);
      expect(find.text('Move to'), findsOneWidget);
    });

    testWidgets('the grip menu moves a pane without dragging', (tester) async {
      useWindow(tester);
      final layout = createLayout([WorkspacePane.logs, WorkspacePane.mirror]);
      await pumpWorkspace(tester, layout);

      await tester.tap(gripOf(WorkspacePane.logs));
      await tester.pumpAndSettle();
      expect(find.text('Reset layout'), findsOneWidget);

      await tester.tap(find.text('Move to'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bottom'));
      await tester.pumpAndSettle();
      expect(describe(layout.root), 'column(mirror, logs)');

      await tester.tap(gripOf(WorkspacePane.logs));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Group as tabs with'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(MenuItemButton, 'Mirror'));
      await tester.pumpAndSettle();
      expect(describe(layout.root), 'tabs(mirror, *logs)');

      // In a group the chip is the handle; its right-click menu has the
      // way back too.
      expect(gripOf(WorkspacePane.logs), findsNothing);
      await tester.tap(
        find.descendant(of: find.byType(TabChip), matching: find.text('Logs')),
        buttons: kSecondaryButton,
      );
      await tester.pumpAndSettle();
      expect(find.text('Equal sizes'), findsNothing, reason: 'chips only');
      await tester.tap(find.text('Reset layout'));
      await tester.pumpAndSettle();
      expect(describe(layout.root), 'row(logs, mirror)');
    });

    testWidgets('dragging a divider resizes the panes either side', (
      tester,
    ) async {
      useWindow(tester);
      final layout = createLayout([WorkspacePane.logs, WorkspacePane.mirror]);
      await pumpWorkspace(tester, layout);
      final before = tester.getRect(paneOf(WorkspacePane.logs)).width;

      await tester.drag(
        find.byType(WorkspaceDivider),
        const Offset(-120, 0),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();

      expect(
        tester.getRect(paneOf(WorkspacePane.logs)).width,
        closeTo(before - 120, 0.5),
      );
    });

    testWidgets('closing a tab from its chip closes the pane', (tester) async {
      useWindow(tester);
      final layout = createLayout([WorkspacePane.logs, WorkspacePane.mirror]);
      layout.stackWith(WorkspacePane.mirror, WorkspacePane.logs);
      await pumpWorkspace(tester, layout);

      await tester.tap(
        find.descendant(
          of: find.ancestor(
            of: find.text('Mirror'),
            matching: find.byType(TabChip),
          ),
          matching: find.byIcon(Icons.close),
        ),
      );
      await tester.pump();

      expect(layout.openPanes, {WorkspacePane.logs});
      expect(find.byType(TabChip), findsNothing);
      expect(gripOf(WorkspacePane.logs), findsNothing);
    });
  });

  group('pane headers', () {
    Widget hosted(Widget header, {required bool isTabbed}) => MaterialApp(
      theme: AppTheme.darkTheme,
      home: Scaffold(
        body: WorkspacePaneScope(
          controls: _NoControls(),
          isTabbed: isTabbed,
          canMove: true,
          child: Align(alignment: Alignment.topCenter, child: header),
        ),
      ),
    );

    testWidgets('outside a workspace a header looks as it always did', (
      tester,
    ) async {
      useWindow(tester);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: FeatureViewHeader(title: 'Mirror', onClose: () {}),
          ),
        ),
      );

      expect(find.byIcon(Icons.drag_indicator), findsNothing);
      expect(find.text('Mirror'), findsOneWidget);
      expect(find.byIcon(Icons.close), findsOneWidget);
    });

    testWidgets('a header leads with the grip, and leaves the title bar to '
        'the tab chip while tabbed', (tester) async {
      useWindow(tester);
      Widget header({List<ToolbarAction> actions = const []}) =>
          FeatureViewHeader(title: 'Mirror', actions: actions, onClose: () {});

      await tester.pumpWidget(hosted(header(), isTabbed: false));
      expect(find.byIcon(Icons.drag_indicator), findsOneWidget);
      expect(find.text('Mirror'), findsOneWidget);
      expect(find.byIcon(Icons.close), findsOneWidget);

      // Tabbed, with actions: only the actions are left.
      await tester.pumpWidget(
        hosted(
          header(
            actions: [
              ToolbarAction(
                icon: Icons.refresh,
                label: 'Refresh',
                onPressed: () {},
              ),
            ],
          ),
          isTabbed: true,
        ),
      );
      expect(find.byIcon(Icons.refresh), findsOneWidget);
      expect(find.byIcon(Icons.drag_indicator), findsNothing);
      expect(find.text('Mirror'), findsNothing);
      expect(find.byIcon(Icons.close), findsNothing);

      // Tabbed, with nothing of its own to show: no header at all.
      await tester.pumpWidget(hosted(header(), isTabbed: true));
      expect(
        find.descendant(
          of: find.byType(FeatureViewHeader),
          matching: find.byType(Container),
        ),
        findsNothing,
      );
    });

    testWidgets('the Files toolbar has the grip and a tab-aware close', (
      tester,
    ) async {
      useWindow(tester);
      final session = _androidSession();
      Widget toolbar() => FileManagerToolbar(
        controller: session.fileManagerController,
        onUpload: () {},
        onNewFolder: () {},
        onDownloadSelected: () {},
        onDeleteSelected: () {},
        onClose: () {},
      );

      await tester.pumpWidget(hosted(toolbar(), isTabbed: false));
      expect(find.byIcon(Icons.drag_indicator), findsOneWidget);
      expect(find.byTooltip('Close files pane'), findsOneWidget);

      await tester.pumpWidget(hosted(toolbar(), isTabbed: true));
      expect(find.byIcon(Icons.drag_indicator), findsNothing);
      expect(find.byTooltip('Close files pane'), findsNothing);
    });

    testWidgets('the Logs toolbar has the grip and a tab-aware close', (
      tester,
    ) async {
      useWindow(tester);
      final session = _androidSession();
      final logs = session.logSessionManager;
      Widget toolbar() => Toolbar(
        controller: logs.selectedTab!,
        logManager: logs,
        onImportLog: null,
        onExport: null,
        onCopyAll: null,
        onClose: () {},
      );

      await tester.pumpWidget(hosted(toolbar(), isTabbed: false));
      expect(find.byIcon(Icons.drag_indicator), findsOneWidget);
      expect(find.byTooltip('Close logs pane'), findsOneWidget);

      await tester.pumpWidget(hosted(toolbar(), isTabbed: true));
      expect(find.byIcon(Icons.drag_indicator), findsNothing);
      expect(find.byTooltip('Close logs pane'), findsNothing);
    });

    testWidgets('in the device screen the real pane headers drag their panes', (
      tester,
    ) async {
      useWindow(tester, const Size(1400, 900));
      // Utilities and Terminal stay usable while the device is away.
      final session = _androidSession(connected: false)
        ..openUtilities()
        ..openTerminal();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: DeviceScreenContent(
              session: session,
              appMemoryBytesListenable: ValueNotifier(0),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byIcon(Icons.drag_indicator), findsNWidgets(2));

      // Terminal's title drags it, the way a window's title bar does.
      Finder title(String text) => find.descendant(
        of: find.byType(FeatureViewHeader),
        matching: find.text(text),
      );
      final utilities = tester.getRect(
        find.ancestor(
          of: title('Utilities'),
          matching: find.byType(FeaturePane),
        ),
      );
      final gesture = await tester.startGesture(
        tester.getCenter(title('Terminal')),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(-24, 0));
      await tester.pump();
      await gesture.moveTo(Offset(utilities.center.dx, utilities.bottom - 120));
      await tester.pump();
      expect(find.text('Place below Utilities'), findsOneWidget);
      await gesture.up();
      await tester.pump();

      expect(
        describe(session.workspaceLayout.root),
        'column(utilities, terminal)',
      );
      expect(session.isTerminalOpen, isTrue);

      await tester.pumpWidget(const SizedBox());
    });
  });
}

/// A session for an Android device, torn down after the test.
/// [connected] false keeps Device Home from polling the device, which a
/// test that mounts the whole device screen needs.
DeviceSessionController _androidSession({bool connected = true}) {
  final device = Device(
    'emulator-5554',
    'device',
    platform: DevicePlatform.android,
    brand: 'Google',
    model: 'Pixel 8',
    connectionState: connected
        ? DeviceConnectionState.connected
        : DeviceConnectionState.disconnected,
  );
  final session = DeviceSessionController(
    device: device,
    service: FakeSessionService(device),
  );
  addTearDown(session.dispose);
  return session;
}

/// A stand-in pane: the standard header (so it has a grip and a draggable
/// title) over a text field whose contents show whether state survived.
class _TestPane extends StatelessWidget {
  const _TestPane({required this.pane, required this.onClose});

  final WorkspacePane pane;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => FeaturePane(
    key: ValueKey('pane.${pane.id}'),
    header: FeatureViewHeader(title: pane.label, onClose: onClose),
    body: const Padding(padding: EdgeInsets.all(16), child: TextField()),
  );
}

class _NoControls implements PaneControls {
  @override
  String get title => 'Pane';
  @override
  void startDrag(Offset globalPosition) {}
  @override
  void updateDrag(Offset globalPosition) {}
  @override
  void endDrag() {}
  @override
  void cancelDrag() {}
  @override
  List<PaneMenuItem> menuItems() => const [];
}
