import 'dart:async';
import 'dart:io';

import 'package:eagly/features/emulator_manager/services/host_dns_reader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('scutil output is reduced to unique IPv4 servers in order', () {
    const output = '''
DNS configuration

resolver #1
  search domain[0] : lan
  nameserver[0] : 27.109.1.2
  nameserver[1] : 8.8.4.4
  nameserver[2] : fe80::1%en0
  if_index : 14 (en0)

resolver #2
  domain   : local
  nameserver[0] : 127.0.0.1

DNS configuration (for scoped queries)

resolver #1
  nameserver[0] : 27.109.1.2
''';

    // The `local` resolver answers only for its own domain.
    expect(HostDnsReader.parseScutil(output), ['27.109.1.2', '8.8.4.4']);
  });

  test('resolv.conf nameserver lines are read, comments ignored', () {
    const contents = '''
# generated
nameserver 127.0.0.53
# nameserver 9.9.9.9
nameserver 1.1.1.1
options edns0
''';

    expect(HostDnsReader.parseResolvConf(contents), ['127.0.0.53', '1.1.1.1']);
  });

  test('one server per line, blanks and junk dropped', () {
    expect(
      HostDnsReader.parseLines('192.168.1.1\r\n\r\nnot-an-ip\n8.8.8.8\n'),
      ['192.168.1.1', '8.8.8.8'],
    );
  });

  group(
    'running a command',
    skip: Platform.isWindows ? 'POSIX shell' : false,
    () {
      test('returns its output, or nothing when it fails', () async {
        expect(
          await HostDnsReader.run('sh', ['-c', 'echo 1.1.1.1']),
          '1.1.1.1\n',
        );
        expect(
          await HostDnsReader.run('sh', ['-c', 'echo 1.1.1.1; exit 3']),
          '',
        );
      });

      test('kills it on timeout', () async {
        final dir = await Directory.systemTemp.createTemp('eagly-host-dns');
        addTearDown(() => dir.delete(recursive: true));
        final pidFile = File('${dir.path}/pid');

        await expectLater(
          HostDnsReader.run('sh', [
            '-c',
            'echo \$\$ > "\$0"; exec sleep 30',
            pidFile.path,
          ], timeout: const Duration(seconds: 1)),
          throwsA(isA<TimeoutException>()),
        );

        final pid = (await pidFile.readAsString()).trim();
        var alive = true;
        for (var i = 0; i < 20 && alive; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          alive = (await Process.run('kill', ['-0', pid])).exitCode == 0;
        }
        expect(alive, isFalse);
      });
    },
  );
}
