import 'package:flutter_test/flutter_test.dart';
import 'package:devspect/data/log_level.dart';
import 'package:devspect/services/preferences_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesService.init();
  });

  test('selectedLogLevel defaults to verbose', () {
    expect(PreferencesService.selectedLogLevel, LogLevel.verbose);
    expect(
      PreferencesService.defaultTabSettings.selectedLogLevel,
      LogLevel.verbose,
    );
  });

  test(
    'selectedLogLevel setter persists the canonical preference key',
    () async {
      PreferencesService.selectedLogLevel = LogLevel.error;

      final prefs = await SharedPreferences.getInstance();
      expect(PreferencesService.selectedLogLevel, LogLevel.error);
      expect(prefs.getString('selectedLogLevel'), LogLevel.error.code);
    },
  );
}
