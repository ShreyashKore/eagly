import 'dart:io';

import 'package:eagly/services/ios/ios_backend.dart';
import 'package:eagly/services/ios/ios_log_service.dart';
import 'package:eagly/services/ios/libimobiledevice_ios_log_service.dart';
import 'package:eagly/services/ios/rust_ios_log_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => rustIosRuntimeFailed = false);

  test('defaults to the Rust backend', () {
    expect(useRustIosBackend, isTrue);
    expect(createIosLogService(), isA<RustIosLogService>());
  }, skip: Platform.environment['EAGLY_IOS_BACKEND'] == 'cli');

  test('falls back to the CLIs when the Rust library failed to load', () {
    rustIosRuntimeFailed = true;

    expect(useRustIosBackend, isFalse);
    expect(createIosLogService(), isA<LibimobiledeviceIosLogService>());
  });
}
