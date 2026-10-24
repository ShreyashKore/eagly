import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../../features/app_log/app_logger.dart';

/// What an Apple USB product id says a device is.
enum AppleUsbDeviceKind(final String label) {
  iPhone('iPhone'),
  iPad('iPad'),
  iPod('iPod touch'),
}

/// An iPhone, iPad or iPod on this computer's USB bus, as the OS itself sees
/// it — no usbmuxd involved.
class const AppleUsbDevice({
  /// The USB serial number: the device's UDID, without the dash newer ones
  /// have. Only used to tell devices apart.
  required final String serial,
  required final AppleUsbDeviceKind kind,
}) {
  @override
  bool operator ==(Object other) =>
      other is AppleUsbDevice && other.serial == serial && other.kind == kind;

  @override
  int get hashCode => Object.hash(serial, kind);

  @override
  String toString() => 'AppleUsbDevice(${kind.label}, $serial)';
}

/// Lists the iOS devices plugged into this computer by asking the OS's USB
/// stack rather than usbmuxd.
///
/// On Windows an iPhone appears in File Explorer, through Windows' own camera
/// driver, without any Apple software. usbmuxd (and every iOS feature with it)
/// arrives only with Apple Mobile Device Support. This is how Eagly tells "no
/// iPhone plugged in" from "an iPhone Eagly can't reach yet".
abstract interface class AppleUsbProbe {
  List<AppleUsbDevice> listConnected();
}

/// Picks an iOS device out of a PnP device instance id such as
/// `USB\VID_05AC&PID_12A8\00008030001A2C3E0E38802E`. Returns null for anything
/// else: an iPhone's interfaces (`…&MI_00\…`), other Apple hardware
/// (keyboards, AirPods, a phone in recovery mode) and other vendors.
AppleUsbDevice? parseAppleUsbInstanceId(String instanceId) {
  final match = _appleInstanceId.firstMatch(instanceId);
  if (match == null) return null;
  final productId = int.parse(match.group(1)!, radix: 16);
  // usbmuxd's own range: every iPhone, iPad and iPod that speaks it.
  if (productId < 0x1290 || productId > 0x12AF) return null;
  return AppleUsbDevice(
    serial: match.group(2)!.toUpperCase(),
    kind: _iPadProductIds.contains(productId)
        ? AppleUsbDeviceKind.iPad
        : _iPodProductIds.contains(productId)
        ? AppleUsbDeviceKind.iPod
        : AppleUsbDeviceKind.iPhone,
  );
}

final RegExp _appleInstanceId = RegExp(
  r'^USB\\VID_05AC&PID_([0-9A-F]{4})\\([^\\]+)$',
  caseSensitive: false,
);

// Every iPhone since the iPhone 5 is 0x12A8, so anything not listed here is
// taken for an iPhone.
const Set<int> _iPadProductIds = {
  0x129A, 0x129F, 0x12A2, 0x12A3, 0x12A4, 0x12A5, 0x12A6, 0x12A9, 0x12AB, //
};
const Set<int> _iPodProductIds = {
  0x1291, 0x1293, 0x1296, 0x1299, 0x129E, 0x12AA, //
};

/// [AppleUsbProbe] over the Windows Configuration Manager (cfgmgr32): the
/// instance ids of the USB devices present right now. A couple of in-process
/// calls, cheap enough to run on every device poll.
class WindowsAppleUsbProbe implements AppleUsbProbe {
  final AppLogger _logger = AppLogger(source: 'WindowsAppleUsbProbe');

  _Cfgmgr32? _api;
  bool _apiUnavailable = false;
  bool _loggedFailure = false;

  @override
  List<AppleUsbDevice> listConnected() {
    final api = _loadApi();
    if (api == null) return const [];
    try {
      final devices = [
        for (final id in api.presentUsbInstanceIds())
          // A present-only listing is a Windows 7+ flag; confirming each match
          // keeps an iPhone plugged in last month from ever prompting.
          if (parseAppleUsbInstanceId(id) case final device?
              when api.isPresent(id))
            device,
      ];
      _loggedFailure = false;
      return devices;
    } catch (error) {
      if (!_loggedFailure) {
        _loggedFailure = true;
        _logger.warning('Could not list USB devices', detail: '$error');
      }
      return const [];
    }
  }

  _Cfgmgr32? _loadApi() {
    if (_api != null || _apiUnavailable) return _api;
    try {
      return _api = _Cfgmgr32(DynamicLibrary.open('cfgmgr32.dll'));
    } catch (error) {
      _apiUnavailable = true;
      _logger.warning('cfgmgr32 is unavailable', detail: '$error');
      return null;
    }
  }
}

// ── cfgmgr32 bindings ──────────────────────────────────────────────────────

typedef _GetIdListSizeNative = Uint32 Function(
  Pointer<Uint32> length,
  Pointer<Utf16> filter,
  Uint32 flags,
);
typedef _GetIdListSizeDart = int Function(
  Pointer<Uint32> length,
  Pointer<Utf16> filter,
  int flags,
);
typedef _GetIdListNative = Uint32 Function(
  Pointer<Utf16> filter,
  Pointer<Uint16> buffer,
  Uint32 length,
  Uint32 flags,
);
typedef _GetIdListDart = int Function(
  Pointer<Utf16> filter,
  Pointer<Uint16> buffer,
  int length,
  int flags,
);
typedef _LocateDevNodeNative = Uint32 Function(
  Pointer<Uint32> devInst,
  Pointer<Utf16> id,
  Uint32 flags,
);
typedef _LocateDevNodeDart = int Function(
  Pointer<Uint32> devInst,
  Pointer<Utf16> id,
  int flags,
);

class _Cfgmgr32(DynamicLibrary library) {
  this
    : _getIdListSize = library
          .lookupFunction<_GetIdListSizeNative, _GetIdListSizeDart>(
            'CM_Get_Device_ID_List_SizeW',
          ),
      _getIdList = library.lookupFunction<_GetIdListNative, _GetIdListDart>(
        'CM_Get_Device_ID_ListW',
      ),
      _locateDevNode = library
          .lookupFunction<_LocateDevNodeNative, _LocateDevNodeDart>(
            'CM_Locate_DevNodeW',
          );

  // From cfgmgr32.h.
  static const int _crSuccess = 0x00;
  static const int _crBufferSmall = 0x1A;
  static const int _filterEnumerator = 0x001;
  static const int _filterPresent = 0x100;
  static const int _locateNormal = 0x0;

  final _GetIdListSizeDart _getIdListSize;
  final _GetIdListDart _getIdList;
  final _LocateDevNodeDart _locateDevNode;

  /// Instance ids of the devices the USB enumerator has right now.
  List<String> presentUsbInstanceIds() {
    return using((arena) {
      final filter = 'USB'.toNativeUtf16(allocator: arena);
      final length = arena<Uint32>();
      const flags = _filterEnumerator | _filterPresent;
      // A device plugged in between sizing the list and filling it makes the
      // buffer too small, so size it again.
      for (var attempt = 0; attempt < 3; attempt++) {
        _check(
          _getIdListSize(length, filter, flags),
          'CM_Get_Device_ID_List_SizeW',
        );
        final size = length.value;
        if (size == 0) return const <String>[];
        final buffer = arena<Uint16>(size);
        final result = _getIdList(filter, buffer, size, flags);
        if (result == _crBufferSmall) continue;
        _check(result, 'CM_Get_Device_ID_ListW');
        // A run of NUL-terminated strings, ended by an empty one.
        return String.fromCharCodes(buffer.asTypedList(size))
            .split('\u0000')
            .where((id) => id.isNotEmpty)
            .toList();
      }
      throw StateError('the USB device list kept changing');
    });
  }

  /// Whether [instanceId] is in the device tree now, not just remembered.
  bool isPresent(String instanceId) {
    return using((arena) {
      final devInst = arena<Uint32>();
      final id = instanceId.toNativeUtf16(allocator: arena);
      return _locateDevNode(devInst, id, _locateNormal) == _crSuccess;
    });
  }

  static void _check(int result, String function) {
    if (result != _crSuccess) {
      throw StateError('$function failed: 0x${result.toRadixString(16)}');
    }
  }
}
