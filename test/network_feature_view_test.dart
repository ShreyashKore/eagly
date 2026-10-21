import 'package:eagly/data/device.dart';
import 'package:eagly/features/network/components/network_filter_bar.dart';
import 'package:eagly/features/network/data/network_transaction.dart';
import 'package:eagly/features/network/network_controller.dart';
import 'package:eagly/features/network/services/network_source.dart';
import 'package:eagly/features/network/network_feature_view.dart';
import 'package:eagly/presentation/theme/app_theme.dart';
import 'package:eagly/services/preferences_service.dart';
import 'package:eagly/session/device_session_controller.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/network_test_support.dart';
import 'support/session_test_support.dart';

void main() {
  late DeviceSessionController session;
  late NetworkController controller;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesService.init();
  });

  setUp(() {
    NetworkController.notifyInterval = Duration.zero;
    final device = Device(
      'emulator-5554',
      'device',
      platform: DevicePlatform.android,
      model: 'Pixel 8',
    );
    session = DeviceSessionController(
      device: device,
      service: FakeSessionService(device),
    );
    controller = session.networkController;
  });

  tearDown(() {
    NetworkController.notifyInterval = const Duration(milliseconds: 100);
  });

  Future<void> pumpView(
    WidgetTester tester, {
    Size size = const Size(1200, 800),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: NetworkFeatureView(controller: controller, onClose: () {}),
        ),
      ),
    );
  }

  /// Three finished GETs (200, 404, pending) from one source.
  Future<void> addExchanges(WidgetTester tester) async {
    final source = FakeNetworkSource();
    controller.attach(source);
    source
      ..upsert(networkTransaction('1'))
      ..upsert(networkTransaction('2', code: 404))
      ..upsert(networkTransaction('3', state: NetworkTransactionState.pending));
    await tester.pump();
    await tester.pump();
  }

  Future<void> tearDownView(WidgetTester tester) async {
    // Unmount before disposing, so no pending fetch outlives the test body.
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  }

  testWidgets('explains the empty pane and offers a HAR file', (tester) async {
    await pumpView(tester);

    expect(find.text('No network traffic yet'), findsOneWidget);
    expect(find.text('Open HAR file'), findsOneWidget);
    expect(find.text('What is Inspektor?'), findsOneWidget);
    expect(
      find.text('Looking for apps with Inspektor on Pixel 8…'),
      findsOneWidget,
    );
    // A tester's steps come first, and know the device is already connected.
    expect(find.text('Get a test build that includes Inspektor'), findsOne);
    expect(find.text('Pixel 8 is connected'), findsOneWidget);

    session.dispose();
  });

  testWidgets('the empty pane walks a developer through adding Inspektor', (
    tester,
  ) async {
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await pumpView(tester);

    await tester.ensureVisible(find.text('I’m building the app'));
    await tester.tap(find.text('I’m building the app'));
    await tester.pumpAndSettle();

    // An Android device starts on OkHttp.
    expect(find.textContaining('inspektor-okhttp-no-op'), findsOneWidget);
    expect(find.textContaining('InspektorRemote.start()'), findsOneWidget);

    final ktor = find.widgetWithText(ChoiceChip, 'Ktor');
    await tester.ensureVisible(ktor);
    await tester.tap(ktor);
    await tester.pumpAndSettle();
    expect(find.textContaining('inspektor-okhttp'), findsNothing);
    expect(find.textContaining('install(Inspektor)'), findsOneWidget);

    await tester.ensureVisible(find.byTooltip('Copy').first);
    await tester.tap(find.byTooltip('Copy').first);
    await tester.pump();
    expect(copied.single, contains('inspektor-no-op:<version>'));

    session.dispose();
  });

  testWidgets('the empty pane names an app that is connected but quiet', (
    tester,
  ) async {
    await pumpView(tester);
    final source = FakeNetworkSource();
    controller.attach(source);
    source.status(NetworkSourceStatus.live);
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('Connected to Example app.'), findsOneWidget);

    await tearDownView(tester);
  });

  testWidgets('the empty pane fits a narrow pane', (tester) async {
    await pumpView(tester, size: const Size(340, 700));
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.text('I’m building the app'));
    await tester.tap(find.text('I’m building the app'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Swift / React Native'));
    await tester.tap(find.text('Swift / React Native'));
    await tester.pumpAndSettle();
    expect(find.textContaining('InspektorRemote.shared.start()'), findsOne);
    expect(tester.takeException(), isNull);

    session.dispose();
  });

  testWidgets('lists exchanges and opens one beside the list', (tester) async {
    await pumpView(tester);
    await addExchanges(tester);

    expect(find.text('/items/1'), findsOneWidget);
    expect(find.text('404'), findsOneWidget);
    expect(find.text('3 requests'), findsOneWidget);

    await tester.tap(find.text('/items/1'));
    await tester.pump();
    await tester.pump();

    // Side by side: the list stays, the exchange opens on its Headers tab.
    expect(find.text('/items/2'), findsOneWidget);
    expect(find.text('Headers'), findsOneWidget);
    expect(find.text('https://api.example.com/items/1'), findsOneWidget);

    await tester.tap(find.text('Response'));
    await tester.pump();
    await tester.pump();
    final editor = tester.widget<CodeEditor>(find.byType(CodeEditor));
    expect(editor.controller?.text, 'body of 1');

    await tester.tap(find.byTooltip('Close (Esc)'));
    await tester.pump();
    expect(controller.selected, isNull);
    expect(find.text('Headers'), findsNothing);

    await tearDownView(tester);
  });

  testWidgets('a narrow pane shows the exchange in place of the list', (
    tester,
  ) async {
    await pumpView(tester, size: const Size(600, 800));
    await addExchanges(tester);

    await tester.tap(find.text('/items/1'));
    await tester.pump();
    await tester.pump();

    expect(find.text('/items/2'), findsNothing);
    await tester.tap(find.byTooltip('Back to list'));
    await tester.pump();
    expect(find.text('/items/2'), findsOneWidget);

    await tearDownView(tester);
  });

  testWidgets('typing in the filter and toggling chips narrows the list', (
    tester,
  ) async {
    await pumpView(tester);
    await addExchanges(tester);

    await tester.enterText(
      find.descendant(
        of: find.byType(NetworkFilterBar),
        matching: find.byType(TextField),
      ),
      'status-code:404',
    );
    await tester.pump();
    expect(find.text('/items/1'), findsNothing);
    expect(find.text('/items/2'), findsOneWidget);
    expect(find.text('1 / 3 requests'), findsOneWidget);

    await tester.tap(find.byTooltip('Clear filter (Esc)'));
    await tester.pump();
    await tester.tap(find.byTooltip('Still waiting for the response'));
    await tester.pump();
    expect(find.text('/items/1'), findsNothing);
    expect(find.text('/items/3'), findsOneWidget);

    await tester.tap(find.text('All'));
    await tester.pump();
    expect(find.text('/items/1'), findsOneWidget);

    await tearDownView(tester);
  });

  testWidgets('the filter suggests keys, then the values seen', (tester) async {
    await pumpView(tester);
    await addExchanges(tester);

    List<String> suggestions(String text) => [
      for (final s in filterSuggestionsFor(
        controller,
        TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        ),
      ))
        s.label,
    ];

    expect(suggestions('dom'), ['domain:']);
    expect(suggestions('-meth'), ['-method:']);
    expect(suggestions('domain:'), ['domain:api.example.com']);
    expect(suggestions('status-code:4'), ['status-code:404']);
    expect(suggestions('is:'), contains('is:failed'));

    await tearDownView(tester);
  });

  testWidgets('a row\'s menu narrows the list to its host', (tester) async {
    await pumpView(tester);
    await addExchanges(tester);

    final row = tester.getCenter(find.text('/items/2'));
    await tester.tapAt(row, buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    expect(find.text('Copy as cURL'), findsOneWidget);

    await tester.tap(find.text('Hide api.example.com'));
    await tester.pumpAndSettle();
    expect(controller.filter.query, '-domain:api.example.com');
    expect(find.text('No requests match the filter'), findsOneWidget);

    await tester.tap(find.text('Clear filters'));
    await tester.pump();
    expect(find.text('/items/1'), findsOneWidget);

    await tearDownView(tester);
  });

  testWidgets('arrow keys move the selection', (tester) async {
    await pumpView(tester);
    await addExchanges(tester);

    await tester.tap(find.text('/items/1'));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(controller.selected?.key.id, '2');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(controller.selected, isNull);

    await tearDownView(tester);
  });

  testWidgets('column headers sort the list', (tester) async {
    await pumpView(tester);
    await addExchanges(tester);

    await tester.tap(find.text('Status'));
    await tester.pump();
    expect(controller.sort, const NetworkSort(NetworkSortColumn.status));
    final first = tester.getTopLeft(find.text('/items/3')).dy;
    final second = tester.getTopLeft(find.text('/items/1')).dy;
    expect(first, lessThan(second), reason: 'pending sorts first');

    await tearDownView(tester);
  });
}
