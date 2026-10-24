import 'package:eagly/features/apps/components/app_list_row.dart';
import 'package:eagly/features/apps/data/app_info.dart';
import 'package:flutter_test/flutter_test.dart';

/// The list view's details line, for what an iPhone reports: a version and a
/// build number, and no install or update times.
void main() {
  test('shows the build number after the version', () {
    const app = AppInfo(
      packageName: 'com.example.notes',
      versionName: '1.2.0',
      versionCode: '45',
    );

    expect(appDetailsLine(app), 'v1.2.0 (45)');
  });

  test('shows a build number equal to the version once', () {
    const app = AppInfo(
      packageName: 'com.apple.Music',
      versionName: '4026.110.1',
      versionCode: '4026.110.1',
    );

    expect(appDetailsLine(app), 'v4026.110.1');
  });
}
