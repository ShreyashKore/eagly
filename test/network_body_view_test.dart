import 'dart:convert';
import 'dart:typed_data';

import 'package:eagly/features/network/components/network_body_view.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the content type picks the language, else the text is sniffed', () {
    expect(BodyLanguage.detect('application/json', '{}'), BodyLanguage.json);
    expect(
      BodyLanguage.detect('application/vnd.api+json', '[]'),
      BodyLanguage.json,
    );
    expect(BodyLanguage.detect('text/html', '<p>'), BodyLanguage.html);
    expect(BodyLanguage.detect('image/png', null), BodyLanguage.image);
    expect(BodyLanguage.detect('image/svg+xml', '<svg/>'), BodyLanguage.xml);
    expect(BodyLanguage.detect(null, null), BodyLanguage.hex);
    expect(BodyLanguage.detect('text/plain', ' {"a": 1}'), BodyLanguage.json);
    expect(BodyLanguage.detect(null, '{not json'), BodyLanguage.text);
    expect(
      BodyLanguage.detect(null, '<?xml version="1.0"?>'),
      BodyLanguage.xml,
    );
    expect(
      BodyLanguage.detect('application/x-www-form-urlencoded', 'a=1&b=2'),
      BodyLanguage.form,
    );
  });

  test('binary bodies are dumped as offset, hex and ASCII', () {
    final dump = hexDump(
      Uint8List.fromList([...utf8.encode('PNG'), 0, 1, 255]),
    );
    expect(
      dump,
      '00000000  50 4e 47 00 01 ff                                 PNG...',
    );
  });
}
