import 'package:flutter_test/flutter_test.dart';
import 'package:eagly/data/device.dart';

void main() {
  // ---------------------------------------------------------------------------
  // iOS device labels
  // ---------------------------------------------------------------------------

  group('IosDevice display', () {
    test('trims whitespace and drops duplicate secondary label', () {
      final device = Device.ios(
        'ios-1',
        'device',
        name: '  QA iPhone  ',
        model: ' QA iPhone ',
      );

      expect(device, isA<IosDevice>());
      expect(device.displayName, 'QA iPhone');
      expect(device.displayLabel.primary, 'QA iPhone');
      expect(device.displayLabel.secondary, isNull);
    });

    test('statusLabel maps "device" to "online"', () {
      final device = Device.ios('ios-1', 'device');
      expect(device.statusLabel, 'online');
    });

    test('statusLabel preserves non-"device" statuses verbatim', () {
      expect(Device.ios('x', 'unpaired').statusLabel, 'unpaired');
      expect(Device.ios('x', 'locked').statusLabel, 'locked');
      expect(Device.ios('x', 'unavailable').statusLabel, 'unavailable');
    });

    test('disconnected statusLabel is always "disconnected"', () {
      final device = Device.ios(
        'ios-1',
        'device',
        connectionState: DeviceConnectionState.disconnected,
      );
      expect(device.statusLabel, 'disconnected');
    });
  });

  // ---------------------------------------------------------------------------
  // Android — wired (non-wireless) device labels
  // ---------------------------------------------------------------------------

  group('AndroidDevice wired display', () {
    test('ignores whitespace-only metadata, falls back to model', () {
      final device = Device.android(
        'emulator-5554',
        'device',
        brand: '   ',
        model: ' Pixel 8 ',
        name: '  ',
      );

      expect(device, isA<AndroidDevice>());
      expect(device.displayName, 'Pixel 8');
      expect(device.displayLabel.secondary, 'Pixel 8');
    });

    test('label primary is the truncated serial ID for wired devices', () {
      final device = Device.android(
        'RZCW1186VXZ',
        'device',
        brand: 'Samsung',
        model: 'Galaxy S21',
      );

      expect(device.displayLabel.primary, 'RZCW1186VX...');
      expect(device.displayLabel.secondary, 'Samsung Galaxy S21');
    });

    test(
      'displayName appends serial when brand/model is distinct from name',
      () {
        final device = Device.android(
          'RZCW1186VXZ',
          'device',
          brand: 'Samsung',
          model: 'Galaxy S21',
          name: 'gts3l', // codename — distinct
        );

        expect(device.displayName, 'Samsung Galaxy S21 (RZCW1186VXZ)');
      },
    );

    test('displayName skips duplicate when model already contains brand', () {
      final device = Device.android(
        'emulator-5554',
        'device',
        brand: 'Google',
        model: 'Google Pixel 8',
      );

      expect(device.displayName, 'Google Pixel 8');
    });

    test('statusLabel maps "device" to "online"', () {
      expect(Device.android('x', 'device').statusLabel, 'online');
    });

    test('isWireless is false for plain serial IDs', () {
      final device = Device.android('RZCW1186VXZ', 'device') as AndroidDevice;
      expect(device.isWireless, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // Android — wireless via mDNS (ADB TLS)
  // ---------------------------------------------------------------------------

  group('AndroidDevice wireless mDNS display', () {
    const mdnsId = 'adb-RZCW1186VXZ-dKgTxk._adb-tls-connect._tcp';

    test('isWireless is true for mDNS IDs', () {
      final device = Device.android(mdnsId, 'device') as AndroidDevice;
      expect(device.isWireless, isTrue);
    });

    test(
      'displayLabel uses brand/model as primary and serial as secondary',
      () {
        final device = Device.android(
          mdnsId,
          'device',
          brand: 'Samsung',
          model: 'Galaxy S21',
        );

        expect(device.displayLabel.primary, 'Samsung Galaxy S21');
        expect(device.displayLabel.secondary, 'RZCW1186VXZ');
      },
    );

    test('displayLabel shows only extracted serial when undescribed', () {
      final device = Device.android(mdnsId, 'device');

      expect(device.displayLabel.primary, 'RZCW1186VXZ');
      expect(device.displayLabel.secondary, isNull);
    });

    test('displayName is clean brand/model — no mDNS noise', () {
      final device = Device.android(
        mdnsId,
        'device',
        brand: 'Samsung',
        model: 'Galaxy S21',
        name: 'gts3l',
      );

      expect(device.displayName, 'Samsung Galaxy S21');
      expect(device.displayName, isNot(contains('adb-')));
      expect(device.displayName, isNot(contains('._tcp')));
    });

    test('displayName falls back to extracted serial when undescribed', () {
      final device = Device.android(mdnsId, 'device');
      expect(device.displayName, 'RZCW1186VXZ');
    });

    test('serial is correctly extracted from various mDNS IDs', () {
      AndroidDevice make(String id) =>
          Device.android(id, 'device') as AndroidDevice;

      expect(
        make('adb-ABC123DEF-xYzW._adb-tls-connect._tcp').displayLabel.primary,
        'ABC123DEF',
      );
      expect(
        make('adb-R9XQ55T100-kPqR._adb-tls-connect._tcp').displayLabel.primary,
        'R9XQ55T100',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Android — wireless via TCP/IP (IP:port)
  // ---------------------------------------------------------------------------

  group('AndroidDevice wireless IP:port display', () {
    const ipId = '192.168.0.118:33537';

    test('isWireless is true for IP:port IDs', () {
      final device = Device.android(ipId, 'device') as AndroidDevice;
      expect(device.isWireless, isTrue);
    });

    test(
      'displayLabel uses brand/model as primary and bare IP as secondary',
      () {
        final device = Device.android(
          ipId,
          'device',
          brand: 'OnePlus',
          model: 'Nord 3',
        );

        expect(device.displayLabel.primary, 'OnePlus Nord 3');
        expect(device.displayLabel.secondary, '192.168.0.118');
        // Port is ephemeral — must not appear in the label.
        expect(device.displayLabel.secondary, isNot(contains(':33537')));
      },
    );

    test('displayLabel shows bare IP when undescribed', () {
      final device = Device.android(ipId, 'device');
      expect(device.displayLabel.primary, '192.168.0.118');
      expect(device.displayLabel.secondary, isNull);
    });

    test('displayName is clean brand/model — no port noise', () {
      final device = Device.android(
        ipId,
        'device',
        brand: 'OnePlus',
        model: 'Nord 3',
      );

      expect(device.displayName, 'OnePlus Nord 3');
      expect(device.displayName, isNot(contains(':33537')));
    });

    test('displayName falls back to bare IP when undescribed', () {
      final device = Device.android(ipId, 'device');
      expect(device.displayName, '192.168.0.118');
    });
  });
}
