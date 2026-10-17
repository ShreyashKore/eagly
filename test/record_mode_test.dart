import 'package:eagly/data/device.dart';
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

  group('stand-in ids', () {
    final standIn = RecordMode.standInId;

    test('look like the real id but are not it', () {
      final serial = standIn('RZCW1186VXZ');
      expect(serial, isNot('RZCW1186VXZ'));
      expect(serial, hasLength(11));
      expect(serial, startsWith('RZ'), reason: 'manufacturer prefix kept');
      expect(serial, matches(RegExp(r'^RZ[A-Z]{2}\d{4}[A-Z]{3}$')));
    });

    test('keep a UDID a well-formed UDID for the same chip', () {
      final udid = standIn('00008140-001564CA3493801C');
      expect(udid, isNot('00008140-001564CA3493801C'));
      expect(udid, matches(RegExp(r'^00008140-[0-9A-F]{16}$')));
    });

    test('are stable, so every take shows the same device the same way', () {
      expect(standIn('RZCW1186VXZ'), standIn('RZCW1186VXZ'));
      expect(standIn('RZCW1186VXZ'), isNot(standIn('RZCW1186VXY')));
    });

    test('leave alone what identifies no one', () {
      expect(standIn('emulator-5554'), 'emulator-5554');
      expect(standIn('192.168.0.118:33537'), '192.168.0.118:33537');
    });

    test('an mDNS id gets the same stand-in serial as its short form', () {
      final full = standIn('adb-RZCW1186VXZ-xYzW._adb-tls-connect._tcp');
      expect(full, startsWith('adb-${standIn('RZCW1186VXZ')}-'));
      expect(full, endsWith('._adb-tls-connect._tcp'));
      expect(full, isNot(contains('RZCW1186VXZ')));
    });

    group('once in use', () {
      setUp(RecordMode.anonymizeDevices);
      tearDown(() {
        Device.presentId = (id) => id;
        Device.shortNames = false;
      });

      test('name a device by brand and model; the id tools get is real', () {
        final device = Device.android(
          'RZCW1186VXZ',
          'device',
          brand: 'Samsung',
          model: 'Galaxy S21',
          name: 'o1s',
        );
        final fake = standIn('RZCW1186VXZ');

        expect(device.id, 'RZCW1186VXZ');
        expect(device.shownId, fake);
        expect(device.displayName, 'Samsung Galaxy S21');
        expect(device.displayLabel.primary, 'Samsung Galaxy S21');
        expect(
          device.displayLabel.secondary,
          fake,
          reason: 'shown only when two tabs would read the same',
        );
      });

      test('keep an iPhone\'s owner-given name off screen', () {
        final device = Device.ios(
          '00008140-001564CA3493801C',
          'device',
          name: 'Shreyash’s iPhone',
          model: 'iPhone 16 Pro Max',
        );

        expect(device.displayName, 'iPhone 16 Pro Max');
        expect(device.displayLabel.primary, 'iPhone 16 Pro Max');
        expect(
          device.displayLabel.secondary,
          standIn('00008140-001564CA3493801C'),
          reason: 'the stand-in UDID tells two of one model apart',
        );
      });

      test('reach a wireless device\'s serial', () {
        final device = Device.android(
          'adb-RZCW1186VXZ-xYzW._adb-tls-connect._tcp',
          'device',
        );
        expect(device.displayLabel.primary, standIn('RZCW1186VXZ'));
      });
    });
  });
}
