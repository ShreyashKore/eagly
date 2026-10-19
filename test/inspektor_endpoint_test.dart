import 'package:eagly/features/network/services/inspektor/inspektor_endpoint.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('finds Inspektor sockets in /proc/net/unix, each once', () {
    // A listening socket (flags 00010000) and two connections accepted from
    // it, which carry the same path; another app's socket; an unnamed one.
    const dump = '''
Num       RefCount Protocol Flags    Type St Inode Path
0000000000000000: 00000002 00000000 00010000 0001 01 21853 @inspektor_3506_kotlin
0000000000000000: 00000003 00000000 00000000 0001 03 22016 @inspektor_3506_kotlin
0000000000000000: 00000003 00000000 00000000 0001 03 22020 @inspektor_3506_kotlin
0000000000000000: 00000002 00000000 00010000 0001 01 39992 @stetho_com.example_devtools_remote
0000000000000000: 00000002 00000000 00010000 0001 01 40101 @inspektor_4120_dart
0000000000000000: 00000003 00000000 00000000 0001 03 40102
''';

    final endpoints = parseInspektorSockets(dump);

    expect(endpoints, [
      const InspektorEndpoint(name: 'inspektor_3506_kotlin'),
      const InspektorEndpoint(name: 'inspektor_4120_dart'),
    ]);
    expect(endpoints.first.pid, 3506);
    expect(endpoints.first.runtime, 'kotlin');
    expect(endpoints.last.runtime, 'dart');
  });

  test('ignores names that only look alike', () {
    const dump = '''
0000000000000000: 00000002 00000000 00010000 0001 01 1 @inspektor_abc_kotlin
0000000000000000: 00000002 00000000 00010000 0001 01 2 @inspektor_12_kotlin_extra
0000000000000000: 00000002 00000000 00010000 0001 01 3 /data/inspektor_12_kotlin
''';
    expect(parseInspektorSockets(dump), isEmpty);
    expect(parseInspektorSockets(''), isEmpty);
  });

  test('an iOS endpoint is its port, one of the eight from 38470', () {
    expect(inspektorPorts, [
      38470,
      38471,
      38472,
      38473,
      38474,
      38475,
      38476,
      38477,
    ]);
    final endpoint = InspektorEndpoint.tcp(38471);
    expect(endpoint.port, 38471);
    expect(endpoint, InspektorEndpoint.tcp(38471));
    expect(endpoint, isNot(InspektorEndpoint.tcp(38470)));
  });
}
