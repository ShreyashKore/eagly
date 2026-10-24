import 'package:eagly/features/layout_inspector/services/inspector_helper.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/layout_inspector_test_support.dart';

void main() {
  test('a helper that dies before hello reports what it printed', () async {
    final process = FakeHelperProcess(sayHello: false);
    final attaching = InspectorHelper.attach(process);
    process
      ..writeStderr('line one\nline two\nNoSuchMethodException: connect\n')
      ..exit(1);
    await expectLater(
      attaching,
      throwsA(
        isA<InspectorHelperException>()
            .having((error) => error.code, 'code', 'exited')
            .having(
              (error) => error.message,
              'message',
              contains('NoSuchMethodException: connect'),
            ),
      ),
    );
  });

  test('busy is reported as such', () async {
    final process = FakeHelperProcess(sayHello: false)
      ..send({'event': 'error', 'code': 'busy', 'message': 'registered'});
    await expectLater(
      InspectorHelper.attach(process),
      throwsA(
        isA<InspectorHelperException>().having(
          (error) => error.isBusy,
          'isBusy',
          isTrue,
        ),
      ),
    );
  });

  test(
    'an error reply fails that request only; stray output is skipped',
    () async {
      final process = FakeHelperProcess(
        respond: (method, _) =>
            method == 'snapshot' ? throw StateError('no windows') : null,
      );
      final helper = await InspectorHelper.attach(process);
      expect(helper.sdk, 34);
      process.send({'not': 'a reply'});

      await expectLater(
        helper.snapshot(),
        throwsA(isA<InspectorHelperException>()),
      );
      expect(await helper.request('ping'), isEmpty);
      await helper.close();
      expect(process.hasExited, isTrue);
    },
  );

  test('requests in flight fail when the helper exits', () async {
    final process = FakeHelperProcess(respond: (_, _) => null);
    final helper = await InspectorHelper.attach(process);
    process.respond = (_, _) {
      process.exit(137);
      return null;
    };
    await expectLater(
      helper.request('snapshot'),
      throwsA(
        isA<InspectorHelperException>().having(
          (error) => error.code,
          'code',
          'exited',
        ),
      ),
    );
    expect(helper.isClosed, isTrue);
  });
}
