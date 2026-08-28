import 'package:eagly/data/device.dart';
import 'package:eagly/features/device_home/data/device_info.dart';
import 'package:eagly/services/tools/adb_tool.dart';
import 'package:eagly/services/tools/idevice_info_tool.dart';
import 'package:eagly/services/tools/tool_process_runner.dart';
import 'package:flutter_test/flutter_test.dart';

/// Stubs the process boundary by overriding [runText] (a regular,
/// overridable instance method) so [AdbTool.fetchDeviceInfo]'s real parsing
/// runs against canned per-command `adb shell` output, keyed by a substring
/// of the joined argument list.
class _FakeAdbTool extends AdbTool {
  _FakeAdbTool(this.responses) : super(executablePath: '/usr/bin/true');

  final Map<String, String> responses;

  @override
  Future<ToolCommandResult> runText(List<String> arguments) async {
    final joined = arguments.join(' ');
    for (final entry in responses.entries) {
      if (joined.contains(entry.key)) {
        return ToolCommandResult(exitCode: 0, stdout: entry.value, stderr: '');
      }
    }
    return const ToolCommandResult(exitCode: 0, stdout: '', stderr: '');
  }
}

class _FakeIdeviceInfoTool extends IdeviceInfoTool {
  _FakeIdeviceInfoTool(this.responses) : super(executablePath: '/usr/bin/true');

  final Map<String, String> responses;

  @override
  Future<ToolCommandResult> runText(List<String> arguments) async {
    final key = arguments.contains('-q') ? arguments.last : 'default';
    return ToolCommandResult(
      exitCode: 0,
      stdout: responses[key] ?? '',
      stderr: '',
    );
  }
}

void main() {
  group('AdbTool.fetchDeviceInfo', () {
    const getprop = '''
[ro.product.manufacturer]: [Google]
[ro.product.cpu.abi]: [arm64-v8a]
[ro.build.version.release]: [14]
[ro.build.display.id]: [UQ1A.240205.004]
[ro.build.version.sdk]: [34]
[ro.build.version.security_patch]: [2024-02-05]
[persist.sys.locale]: [en-US]
[persist.sys.timezone]: [America/Los_Angeles]
[gsm.operator.alpha]: [T-Mobile]
[gsm.sim.operator.alpha]: [T-Mobile]
[gsm.network.type]: [LTE]
[gsm.sim.state]: [LOADED]
[gsm.operator.numeric]: [310260]
''';

    const battery = '''
Current Battery Service state:
  AC powered: false
  USB powered: true
  status: 2
  health: 2
  present: true
  level: 87
  scale: 100
  voltage: 4350
  temperature: 285
  technology: Li-ion
''';

    const df = '''
Filesystem     1K-blocks    Used Available Use% Mounted on
/dev/block/dm-7 51380224 20000000 31380224  39% /data
''';

    const displayDump = '''
  DisplayDeviceInfo{"Built-in Screen": ... rotation=0, ... refreshRate=120.0}
''';

    const ip = '''
3: wlan0    inet 192.168.1.42/24 brd 192.168.1.255 scope global wlan0
''';

    Future<DeviceInfo> fetch({bool wireless = false}) {
      final tool = _FakeAdbTool({
        'shell getprop': getprop,
        'dumpsys battery': battery,
        'shell df /data': df,
        'wm size': 'Physical size: 1080x2400\n',
        'wm density': 'Physical density: 420\n',
        'dumpsys display': displayDump,
        'global wifi_on': '1',
        'global bluetooth_on': '0',
        'global development_settings_enabled': '1',
        'global adb_enabled': '1',
        'ip -f inet addr show wlan0': ip,
      });
      final device = AndroidDevice(
        wireless ? '192.168.1.42:5555' : 'ABC123SERIAL',
        'device',
        model: 'Pixel 7',
        serialNumber: 'ABC123SERIAL',
      );
      return tool.fetchDeviceInfo(device);
    }

    test('parses identity, software and cellular from getprop', () async {
      final info = await fetch();

      expect(info.identity.manufacturer, 'Google');
      expect(info.identity.osName, 'Android');
      expect(info.identity.osVersion, '14');
      expect(info.identity.buildVersion, 'UQ1A.240205.004');
      expect(info.identity.cpuArchitecture, 'arm64-v8a');
      expect(info.identity.serialNumber, 'ABC123SERIAL');

      expect(info.software.sdkLevel, 34);
      expect(info.software.securityPatch, '2024-02-05');
      expect(info.software.locale, 'en-US');
      expect(info.software.timeZone, 'America/Los_Angeles');

      expect(info.cellular.carrierName, 'T-Mobile');
      expect(info.cellular.simOperatorName, 'T-Mobile');
      expect(info.cellular.networkType, 'LTE');
      expect(info.cellular.simState, 'LOADED');
      expect(info.cellular.mcc, '310');
      expect(info.cellular.mnc, '260');
    });

    test('parses battery status/health codes and temperature', () async {
      final info = await fetch();

      expect(info.battery.percentage, 87);
      expect(info.battery.chargingState, BatteryChargingState.charging);
      expect(info.battery.health, BatteryHealth.good);
      expect(info.battery.temperatureCelsius, closeTo(28.5, 0.001));
    });

    test('parses storage from df /data in KB-to-bytes', () async {
      final info = await fetch();

      expect(info.storage.totalBytes, 51380224 * 1024);
      expect(info.storage.usedBytes, 20000000 * 1024);
      expect(info.storage.availableBytes, 31380224 * 1024);
      expect(info.storage.usagePercent, isNotNull);
    });

    test(
      'parses display size, density, refresh rate and orientation',
      () async {
        final info = await fetch();

        expect(info.display.widthPx, 1080);
        expect(info.display.heightPx, 2400);
        expect(info.display.densityDpi, 420);
        expect(info.display.refreshRateHz, 120.0);
        expect(info.display.orientation, DisplayOrientation.portrait);
      },
    );

    test('reports USB connection for a wired device id', () async {
      final info = await fetch();
      expect(info.connectivity.usbConnected, true);
      expect(info.connectivity.wifiEnabled, true);
      expect(info.connectivity.bluetoothEnabled, false);
      expect(info.connectivity.ipAddress, '192.168.1.42');
    });

    test('reports wireless connection for an IP:port device id', () async {
      final info = await fetch(wireless: true);
      expect(info.connectivity.usbConnected, false);
    });

    test('reports developer/adb readiness from settings + status', () async {
      final info = await fetch();
      expect(info.developerState.developerModeEnabled, true);
      expect(info.developerState.adbEnabled, true);
      expect(info.developerState.debuggingReady, true);
    });

    test('leaves fields null when a command fails or is unparsable', () async {
      final tool = _FakeAdbTool(const {});
      final device = AndroidDevice('ABC123SERIAL', 'device');
      final info = await tool.fetchDeviceInfo(device);

      expect(info.battery.isEmpty, true);
      expect(info.storage.isEmpty, true);
      expect(info.display.isEmpty, true);
    });
  });

  group('IdeviceInfoTool.fetchExtendedInfo', () {
    const defaultDomain = '''
DeviceName: My iPhone
ProductVersion: 17.4
BuildVersion: 21E219
SerialNumber: ABCD1234EFGH
CPUArchitecture: arm64e
SIMStatus: kCTSIMSupportSIMStatusReady
TimeZone: America/New_York
''';

    const batteryDomain = '''
BatteryCurrentCapacity: 76
BatteryIsCharging: false
''';

    const diskDomain = '''
TotalDiskCapacity: 128000000000
TotalDataAvailable: 32000000000
''';

    const internationalDomain = '''
Locale: en_US
TimeZone: America/New_York
''';

    Future<DeviceInfo> fetch({String status = 'device'}) {
      final tool = _FakeIdeviceInfoTool({
        'default': defaultDomain,
        'com.apple.mobile.battery': batteryDomain,
        'com.apple.disk_usage': diskDomain,
        'com.apple.international': internationalDomain,
      });
      final device = IosDevice('udid-1', status, model: 'iPhone 15 Pro');
      return tool.fetchExtendedInfo(device);
    }

    test('parses identity from the default domain', () async {
      final info = await fetch();

      expect(info.identity.manufacturer, 'Apple');
      expect(info.identity.osName, 'iOS');
      expect(info.identity.osVersion, '17.4');
      expect(info.identity.buildVersion, '21E219');
      expect(info.identity.serialNumber, 'ABCD1234EFGH');
      expect(info.identity.cpuArchitecture, 'arm64e');
    });

    test('parses battery from com.apple.mobile.battery', () async {
      final info = await fetch();
      expect(info.battery.percentage, 76);
      expect(info.battery.chargingState, BatteryChargingState.discharging);
    });

    test('parses storage from com.apple.disk_usage', () async {
      final info = await fetch();
      expect(info.storage.totalBytes, 128000000000);
      expect(info.storage.availableBytes, 32000000000);
      expect(info.storage.usedBytes, 128000000000 - 32000000000);
    });

    test('assumes USB connectivity and reports SIM state', () async {
      final info = await fetch();
      expect(info.connectivity.usbConnected, true);
      expect(info.connectivity.wifiEnabled, isNull);
      expect(info.cellular.simState, 'kCTSIMSupportSIMStatusReady');
      expect(info.cellular.carrierName, isNull);
    });

    test('maps device status to a pairing state label', () async {
      expect(
        (await fetch(status: 'device')).developerState.pairingState,
        'Paired',
      );
      expect(
        (await fetch(status: 'unpaired')).developerState.pairingState,
        'Not Paired',
      );
      expect(
        (await fetch(status: 'locked')).developerState.pairingState,
        'Locked (enter passcode)',
      );
    });

    test('parses locale/timezone from com.apple.international', () async {
      final info = await fetch();
      expect(info.software.locale, 'en_US');
      expect(info.software.timeZone, 'America/New_York');
    });
  });
}
