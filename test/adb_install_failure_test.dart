import 'package:eagly/data/app_install_conflict.dart';
import 'package:eagly/services/tools/adb_install_failure.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a version downgrade names both version codes and the fix', () {
    const output =
        'Performing Streamed Install\n'
        'adb: failed to install /Users/me/OUT/network + fcm-appsflyer.apk: '
        'Failure [INSTALL_FAILED_VERSION_DOWNGRADE:\n'
        'Downgrade detected: Update version code 21 is older than current '
        '212]';

    expect(
      describeAdbInstallFailure(output),
      'The device already has a newer version of this app (version code 212; '
      'this APK is 21). Install a build with version code 212 or higher, or '
      'uninstall the app first. Uninstalling deletes that app\'s data, so '
      'back up anything you need first.',
    );
  });

  test('a signature mismatch names the package', () {
    const output =
        'adb: failed to install app.apk: Failure '
        '[INSTALL_FAILED_UPDATE_INCOMPATIBLE: Package com.example.app '
        'signatures do not match previously installed version; ignoring!]';

    expect(
      describeAdbInstallFailure(output),
      'The installed copy of com.example.app is signed with a different key. '
      'Uninstall it first, then install again. Uninstalling deletes that '
      'app\'s data, so back up anything you need first.',
    );
  });

  test('an older Android\'s "Existing package" wording still names it', () {
    const output =
        'Failure [INSTALL_FAILED_UPDATE_INCOMPATIBLE: Existing package '
        'com.example.app signatures do not match newer version; ignoring!]';

    expect(
      describeAdbInstallFailure(output),
      startsWith('The installed copy of com.example.app is signed'),
    );
    expect(adbInstallConflict(output), (
      kind: AppInstallConflictKind.signature,
      packageName: 'com.example.app',
    ));
  });

  test('a signature mismatch naming no package says "this app"', () {
    expect(
      describeAdbInstallFailure('Failure [INSTALL_FAILED_UPDATE_INCOMPATIBLE]'),
      startsWith('The installed copy of this app is signed'),
    );
  });

  test('only a signature mismatch or a downgrade is a conflict', () {
    expect(
      adbInstallConflict(
        'Failure [INSTALL_FAILED_VERSION_DOWNGRADE: Downgrade detected: '
        'Update version code 21 is older than current 212]',
      ),
      (kind: AppInstallConflictKind.downgrade, packageName: null),
    );
    expect(
      adbInstallConflict('Failure [INSTALL_FAILED_INSUFFICIENT_STORAGE]'),
      isNull,
    );
    expect(adbInstallConflict('adb: error: device offline'), isNull);
  });

  test('a too-new minSdk names both API levels', () {
    const output =
        'Failure [INSTALL_FAILED_OLDER_SDK: Failed parse during '
        'installPackageLI: /data/app/vmdl.tmp/base.apk (at Binary XML file '
        'line #7): Requires newer sdk version #34 (current version is #30)]';

    expect(
      describeAdbInstallFailure(output),
      'This APK needs Android API 34 or newer; the device runs API 30.',
    );
  });

  test('an unknown code keeps the code and the first line of its detail', () {
    const output =
        'Performing Streamed Install\n'
        'adb: failed to install /tmp/a.apk: Failure '
        '[INSTALL_FAILED_SOMETHING_NEW: first line\nsecond line]';

    expect(
      describeAdbInstallFailure(output),
      'INSTALL_FAILED_SOMETHING_NEW: first line.',
    );
  });

  test('a code with no detail still reads as a sentence', () {
    expect(
      describeAdbInstallFailure(
        'Failure [INSTALL_FAILED_INSUFFICIENT_STORAGE]',
      ),
      'The device is out of storage. Free some space and try again.',
    );
  });

  test('adb failing before the install drops the progress line', () {
    expect(
      describeAdbInstallFailure(
        'Performing Streamed Install\nadb: error: device offline',
      ),
      'The device is offline. Reconnect it and try again.',
    );
    expect(
      describeAdbInstallFailure(
        'Performing Streamed Install\nadb: failed to stat x.apk: No such file',
      ),
      'failed to stat x.apk: No such file.',
    );
  });

  test('nothing recognisable gives null', () {
    expect(describeAdbInstallFailure(''), isNull);
    expect(describeAdbInstallFailure('Performing Streamed Install\n'), isNull);
  });
}
