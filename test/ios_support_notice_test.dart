import 'package:eagly/presentation/components/ios_support_notice.dart';
import 'package:eagly/presentation/theme/app_theme.dart';
import 'package:eagly/services/ios/apple_usb_probe.dart';
import 'package:eagly/services/preferences_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _iPhone = AppleUsbDevice(
  serial: '00008030001A2C3E0E38802E',
  kind: AppleUsbDeviceKind.iPhone,
);
const _iPad = AppleUsbDevice(
  serial: '00008103000A1B2C3D4E5F60',
  kind: AppleUsbDeviceKind.iPad,
);

void main() {
  setUp(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
    await PreferencesService.init();
  });

  group('IosSupportNotice', () {
    Future<void> pump(WidgetTester tester, List<AppleUsbDevice> devices) {
      return tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(body: IosSupportNotice(devices: devices)),
        ),
      );
    }

    testWidgets('guesses when no iPhone is on USB', (tester) async {
      await pump(tester, const []);
      expect(find.text("Don't see your iPhone or iPad?"), findsOneWidget);
    });

    testWidgets('names a plugged-in iPhone', (tester) async {
      await pump(tester, const [_iPhone]);
      expect(
        find.text("iPhone connected, but Eagly can't reach it"),
        findsOneWidget,
      );
      expect(find.textContaining('reconnect the iPhone'), findsOneWidget);
    });

    testWidgets('comes back after dismissal only for a new device', (
      tester,
    ) async {
      await pump(tester, const []);
      await tester.tap(find.byTooltip('Dismiss'));
      await tester.pump();
      expect(find.byType(Text), findsNothing);

      await pump(tester, const [_iPhone]);
      expect(
        find.text("iPhone connected, but Eagly can't reach it"),
        findsOneWidget,
      );

      await tester.tap(find.byTooltip('Dismiss'));
      await tester.pump();
      await pump(tester, const [_iPhone]);
      expect(find.byType(Text), findsNothing);
    });
  });

  group('IosSupportPromptDialog', () {
    late int storeOpens;

    Future<void> open(
      WidgetTester tester, [
      List<AppleUsbDevice> devices = const [_iPhone],
    ]) async {
      storeOpens = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => IosSupportPromptDialog(
                  devices: devices,
                  openStorePage: () async => storeOpens++,
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('sends the user to the Store and closes', (tester) async {
      await open(tester);
      expect(find.text('iPhone connected'), findsOneWidget);

      await tester.tap(find.text('Get Apple Devices'));
      await tester.pumpAndSettle();

      expect(storeOpens, 1);
      expect(find.byType(IosSupportPromptDialog), findsNothing);
      expect(PreferencesService.skipIosSupportPrompt, isFalse);
    });

    testWidgets("'Not now' with the box ticked stops asking", (tester) async {
      await open(tester);

      await tester.ensureVisible(find.text("Don't ask again"));
      await tester.tap(find.text("Don't ask again"));
      await tester.pump();
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();

      expect(storeOpens, 0);
      expect(PreferencesService.skipIosSupportPrompt, isTrue);
    });

    testWidgets("'Not now' alone asks again next time", (tester) async {
      await open(tester);

      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();

      expect(PreferencesService.skipIosSupportPrompt, isFalse);
    });

    testWidgets('names an iPhone and an iPad together', (tester) async {
      await open(tester, const [_iPhone, _iPad]);
      expect(find.text('iPhone and iPad connected'), findsOneWidget);
    });
  });
}
