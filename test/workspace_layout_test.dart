import 'package:eagly/data/device.dart';
import 'package:eagly/services/preferences_service.dart';
import 'package:eagly/session/device_session_controller.dart';
import 'package:eagly/session/workspace_layout.dart';
import 'package:fl_panel/fl_panel.dart';
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

  WorkspaceLayout createLayout({WorkspaceLayoutMemory? memory}) {
    final layout = WorkspaceLayout(memory: memory);
    addTearDown(layout.dispose);
    return layout;
  }

  String leafOf(WorkspaceLayout layout, WorkspacePane pane) =>
      layout.root!.leafOf(pane.id)!.id;

  /// [pane]'s share of the split it sits in.
  double shareOf(WorkspaceLayout layout, WorkspacePane pane) {
    final leaf = leafOf(layout, pane);
    final split = layout.root!.parentOf(leaf)!;
    double weight(PanelExtent size) => (size as FlexExtent).weight;
    final total = split.sizes.fold<double>(0, (sum, s) => sum + weight(s));
    final index = split.children.indexWhere((child) => child.id == leaf);
    return weight(split.sizes[index]) / total;
  }

  /// Moves [pane] beside [target] on [side], the way a drop on that edge of
  /// the target pane does.
  void dockBeside(
    WorkspaceLayout layout,
    WorkspacePane pane,
    WorkspacePane target,
    DockSide side,
  ) {
    final moved = layout.panels.dock(
      WorkspaceLayout.windowId,
      layout.sourceFor(pane)!,
      DockTarget.split(leafOf(layout, target), side, form: SurfaceForm.single),
    );
    expect(moved, isTrue, reason: 'dock $pane $side of $target');
  }

  group('WorkspaceLayout', () {
    test('panes open side by side, left to right, in the order opened', () {
      final layout = createLayout();

      layout
        ..show(WorkspacePane.files)
        ..show(WorkspacePane.logs)
        ..show(WorkspacePane.mirror);

      expect(describe(layout.root), 'row(files, logs, mirror)');
      expect(layout.openPanes, {
        WorkspacePane.files,
        WorkspacePane.logs,
        WorkspacePane.mirror,
      });
      expect(layout.isSideBySide, isFalse, reason: 'not in rail order');
    });

    test('a pane opening on the right takes its preferred width', () {
      final layout = createLayout()..viewportWidth = 1008;

      layout
        ..show(WorkspacePane.logs)
        ..show(WorkspacePane.mirror);

      final solved = layout.panels.solver.layout(
        layout.root,
        const PanelRect(0, 0, 1008, 700),
      );
      final mirror = solved.rectOf(leafOf(layout, WorkspacePane.mirror))!;
      // 340 of 1008 is its share of the 1000 left after the divider.
      expect(mirror.width, closeTo(1000 * 340 / 1008, 0.5));
    });

    test('a pane already open is brought to the front, not reopened', () {
      final layout = createLayout()
        ..show(WorkspacePane.files)
        ..show(WorkspacePane.apps);
      layout.stackWith(WorkspacePane.apps, WorkspacePane.files);
      expect(describe(layout.root), 'tabs(files, *apps)');
      expect(layout.isShown(WorkspacePane.files), isFalse);

      layout.show(WorkspacePane.files);

      expect(describe(layout.root), 'tabs(*files, apps)');
      expect(layout.isShown(WorkspacePane.files), isTrue);
      expect(layout.isTabbed(WorkspacePane.files), isTrue);
    });

    test('listeners hear about panes opening and closing, not moving', () {
      final layout = createLayout();
      var notified = 0;
      layout.addListener(() => notified++);

      layout
        ..show(WorkspacePane.logs)
        ..show(WorkspacePane.mirror);
      expect(notified, 2);

      layout.moveToEdge(WorkspacePane.mirror, DockSide.bottom);
      layout.stackWith(WorkspacePane.mirror, WorkspacePane.logs);
      layout.show(WorkspacePane.logs);
      expect(notified, 2);

      layout.hide(WorkspacePane.mirror);
      expect(notified, 3);
      expect(layout.openPanes, {WorkspacePane.logs});
    });

    test('a closed pane reopens where it was, at the size it had', () {
      final layout = createLayout()
        ..show(WorkspacePane.logs)
        ..show(WorkspacePane.files)
        ..show(WorkspacePane.mirror);
      dockBeside(
        layout,
        WorkspacePane.mirror,
        WorkspacePane.logs,
        DockSide.bottom,
      );
      expect(describe(layout.root), 'row(column(logs, mirror), files)');
      // Give Logs more of the column than the even split a drop makes.
      final column = layout.root!.parentOf(leafOf(layout, WorkspacePane.logs))!;
      layout.panels
        ..resize(
          WorkspaceLayout.windowId,
          column.id,
          0,
          150,
          const PanelRect(0, 0, 1200, 800),
        )
        ..settle();
      final mirrorShare = shareOf(layout, WorkspacePane.mirror);
      expect(mirrorShare, lessThan(0.4));

      layout.hide(WorkspacePane.mirror);
      expect(describe(layout.root), 'row(logs, files)');

      layout.show(WorkspacePane.mirror);
      expect(describe(layout.root), 'row(column(logs, mirror), files)');
      expect(shareOf(layout, WorkspacePane.mirror), closeTo(mirrorShare, 1e-9));
    });

    test('a pane reopens beside its neighbours even when they moved', () {
      final layout = createLayout()
        ..show(WorkspacePane.logs)
        ..show(WorkspacePane.terminal)
        ..show(WorkspacePane.files);
      // Terminal sat right of Logs; Logs then moves under Files.
      layout.hide(WorkspacePane.terminal);
      dockBeside(
        layout,
        WorkspacePane.logs,
        WorkspacePane.files,
        DockSide.bottom,
      );
      expect(describe(layout.root), 'column(files, logs)');

      layout.show(WorkspacePane.terminal);

      expect(describe(layout.root), 'column(files, row(logs, terminal))');
    });

    test('a pane that shared a tab group rejoins it', () {
      final layout = createLayout()
        ..show(WorkspacePane.logs)
        ..show(WorkspacePane.files)
        ..show(WorkspacePane.apps);
      layout.stackWith(WorkspacePane.apps, WorkspacePane.files);
      expect(describe(layout.root), 'row(logs, tabs(files, *apps))');

      layout.hide(WorkspacePane.apps);
      expect(describe(layout.root), 'row(logs, files)');

      layout.show(WorkspacePane.apps);
      expect(describe(layout.root), 'row(logs, tabs(files, *apps))');
    });

    test('a pane opening or closing mid-drag ends the drag', () {
      final layout = createLayout()
        ..show(WorkspacePane.logs)
        ..show(WorkspacePane.mirror);
      layout.panels
        ..beginDrag(
          WorkspaceLayout.windowId,
          layout.sourceFor(WorkspacePane.mirror)!,
        )
        ..updateDrag(
          DockHit.leaf(leafOf(layout, WorkspacePane.logs), 300, 700),
          layout.panels.solver.layout(
            layout.root,
            const PanelRect(0, 0, 1200, 800),
          ),
        );
      expect(layout.panels.drag?.candidate, isNotNull);

      layout.show(WorkspacePane.files);

      // The drop was computed without Files; it must not land and close it.
      expect(layout.panels.drag, isNull);
      expect(layout.panels.commitDrag(), isFalse);
      expect(describe(layout.root), 'row(logs, mirror, files)');
    });

    test('a pane never placed before opens on the right edge', () {
      final layout = createLayout()
        ..show(WorkspacePane.logs)
        ..show(WorkspacePane.mirror);
      layout.moveToEdge(WorkspacePane.mirror, DockSide.top);
      expect(describe(layout.root), 'column(mirror, logs)');

      layout.show(WorkspacePane.utilities);

      expect(describe(layout.root), 'row(column(mirror, logs), utilities)');
    });

    test('placement is shared by every workspace using the memory', () {
      final memory = WorkspaceLayoutMemory();
      final first = createLayout(memory: memory)
        ..show(WorkspacePane.logs)
        ..show(WorkspacePane.mirror);
      first.moveToEdge(WorkspacePane.mirror, DockSide.left);
      expect(describe(first.root), 'row(mirror, logs)');

      final second = createLayout(memory: memory)
        ..show(WorkspacePane.logs)
        ..show(WorkspacePane.mirror);

      expect(describe(second.root), 'row(mirror, logs)');
    });

    test('placement survives a restart through preferences', () {
      final before = createLayout(memory: WorkspaceLayoutMemory.persisted())
        ..show(WorkspacePane.logs)
        ..show(WorkspacePane.terminal);
      before.moveToEdge(WorkspacePane.terminal, DockSide.bottom);
      expect(PreferencesService.workspaceLayout, isNotNull);

      final after = createLayout(memory: WorkspaceLayoutMemory.persisted())
        ..show(WorkspacePane.terminal)
        ..show(WorkspacePane.logs);

      expect(describe(after.root), 'column(logs, terminal)');
    });

    test('an unreadable stored placement is ignored', () async {
      SharedPreferences.setMockInitialValues({'workspaceLayout': '{not json'});
      await PreferencesService.init();
      expect(PreferencesService.workspaceLayout, isNull);

      final layout = createLayout(memory: WorkspaceLayoutMemory.persisted())
        ..show(WorkspacePane.logs)
        ..show(WorkspacePane.mirror);
      expect(describe(layout.root), 'row(logs, mirror)');

      // A newer format and unknown panes read as nothing / what is known.
      expect(WorkspaceLayoutMemory.decode({'version': 99}), isNull);
      final known = WorkspaceLayoutMemory.encode(layout.root);
      final windows = known!['windows']! as List;
      final root = (windows.single as Map)['root'] as Map;
      final children = root['children'] as List;
      ((children.first as Map)['tab'] as Map)['id'] = 'retired-pane';
      expect(describe(WorkspaceLayoutMemory.decode(known)), 'mirror');
    });

    test('reset lines panes up in rail order and forgets placements', () {
      final layout = createLayout()
        ..show(WorkspacePane.files)
        ..show(WorkspacePane.logs)
        ..show(WorkspacePane.mirror);
      layout.moveToEdge(WorkspacePane.files, DockSide.bottom);
      layout.stackWith(WorkspacePane.mirror, WorkspacePane.logs);
      layout.hide(WorkspacePane.files);
      expect(layout.isSideBySide, isFalse);

      layout.reset();

      expect(describe(layout.root), 'row(logs, mirror)');
      expect(layout.isSideBySide, isTrue);
      // Files' old place below everything is forgotten.
      layout.show(WorkspacePane.files);
      expect(describe(layout.root), 'row(logs, mirror, files)');
    });

    test('menu moves: edges and tab groups', () {
      final layout = createLayout()
        ..show(WorkspacePane.logs)
        ..show(WorkspacePane.mirror);

      // Already along the right edge on its own: nothing to do.
      expect(layout.canMoveToEdge(WorkspacePane.mirror, DockSide.right), false);
      expect(layout.canMoveToEdge(WorkspacePane.mirror, DockSide.top), true);

      layout.moveToEdge(WorkspacePane.mirror, DockSide.top);
      expect(describe(layout.root), 'column(mirror, logs)');

      expect(
        layout.canStackWith(WorkspacePane.logs, WorkspacePane.mirror),
        true,
      );
      layout.stackWith(WorkspacePane.logs, WorkspacePane.mirror);
      expect(describe(layout.root), 'tabs(mirror, *logs)');
      expect(layout.groupOf(WorkspacePane.logs), [
        WorkspacePane.mirror,
        WorkspacePane.logs,
      ]);
    });
  });

  group('DeviceSessionController panes', () {
    late DeviceSessionController session;

    setUp(() {
      final device = Device(
        'emulator-5554',
        'device',
        platform: DevicePlatform.android,
        brand: 'Google',
        model: 'Pixel 8',
      );
      session = DeviceSessionController(
        device: device,
        service: FakeSessionService(device),
      );
      addTearDown(session.dispose);
    });

    test('opening panes leaves Home and lays them out in the workspace', () {
      expect(session.isHomeOpen, isTrue);

      session
        ..openUtilities()
        ..openTerminal();

      expect(session.isHomeOpen, isFalse);
      expect(session.isUtilitiesOpen, isTrue);
      expect(session.isTerminalOpen, isTrue);
      expect(
        describe(session.workspaceLayout.root),
        'row(utilities, terminal)',
      );
    });

    test('toggling a pane behind another tab brings it to the front', () {
      session
        ..openUtilities()
        ..openTerminal();
      session.workspaceLayout.stackWith(
        WorkspacePane.terminal,
        WorkspacePane.utilities,
      );

      session.toggleUtilities();
      expect(session.isUtilitiesOpen, isTrue);
      expect(session.workspaceLayout.isShown(WorkspacePane.utilities), isTrue);

      session.toggleUtilities();
      expect(session.isUtilitiesOpen, isFalse);
    });

    test('toggling from Home reveals the workspace instead of closing', () {
      session.openTerminal();
      session.openHome();

      session.toggleTerminal();

      expect(session.isHomeOpen, isFalse);
      expect(session.isTerminalOpen, isTrue);
    });

    test('closing the last pane from its tab falls back to Home', () async {
      session.openTerminal();
      var notified = 0;
      session.addListener(() => notified++);

      // What a tab chip's close button does: straight to the layout.
      await session.workspaceLayout.panels.close(WorkspacePane.terminal.id);

      expect(session.isTerminalOpen, isFalse);
      expect(session.isHomeOpen, isTrue);
      expect(notified, 1);
    });

    test('one notification per open or close made through the session', () {
      var notified = 0;
      session.addListener(() => notified++);

      session.openUtilities();
      expect(notified, 1);
      session.closeUtilities();
      expect(notified, 2);
    });
  });
}
