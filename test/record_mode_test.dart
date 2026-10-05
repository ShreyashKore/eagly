import 'package:eagly/utils/record_mode.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('record mode is off without the flag', () {
    expect(RecordMode.isRequested(const []), isFalse);
    expect(RecordMode.isRequested(const ['--record', 'record-mode']), isFalse);
  });

  test('record mode is on when the flag is passed', () {
    expect(RecordMode.isRequested(const ['--record-mode']), isTrue);
    expect(
      RecordMode.isRequested(const [
        '-NSDocumentRevisionsDebugMode',
        'YES',
        '--record-mode',
      ]),
      isTrue,
    );
  });
}
