import 'utility_command.dart';

/// Curated value lists for [UtilityParamKind.suggestion] fields.
///
/// None of these are exhaustive — they are the values a developer reaches for
/// often enough that typing them out is busywork. A suggestion field always
/// accepts anything the user types, so a missing entry here is a convenience
/// gap, never a capability gap.

// ── Android runtime permissions ───────────────────────────────────────────

/// The runtime (dangerous-group) permissions `pm grant` / `pm revoke` accept.
/// Install-time permissions are deliberately left out: `pm grant` rejects them,
/// so offering them would only produce confusing failures.
const List<UtilityOption> androidRuntimePermissions = [
  UtilityOption(
    'android.permission.CAMERA',
    'Camera',
    description: 'android.permission.CAMERA',
  ),
  UtilityOption(
    'android.permission.RECORD_AUDIO',
    'Microphone',
    description: 'android.permission.RECORD_AUDIO',
  ),
  UtilityOption(
    'android.permission.ACCESS_FINE_LOCATION',
    'Location (precise)',
    description: 'android.permission.ACCESS_FINE_LOCATION',
  ),
  UtilityOption(
    'android.permission.ACCESS_COARSE_LOCATION',
    'Location (approximate)',
    description: 'android.permission.ACCESS_COARSE_LOCATION',
  ),
  UtilityOption(
    'android.permission.ACCESS_BACKGROUND_LOCATION',
    'Location (background)',
    description: 'android.permission.ACCESS_BACKGROUND_LOCATION',
  ),
  UtilityOption(
    'android.permission.POST_NOTIFICATIONS',
    'Notifications',
    description: 'android.permission.POST_NOTIFICATIONS',
  ),
  UtilityOption(
    'android.permission.READ_CONTACTS',
    'Contacts (read)',
    description: 'android.permission.READ_CONTACTS',
  ),
  UtilityOption(
    'android.permission.WRITE_CONTACTS',
    'Contacts (write)',
    description: 'android.permission.WRITE_CONTACTS',
  ),
  UtilityOption(
    'android.permission.READ_CALENDAR',
    'Calendar (read)',
    description: 'android.permission.READ_CALENDAR',
  ),
  UtilityOption(
    'android.permission.WRITE_CALENDAR',
    'Calendar (write)',
    description: 'android.permission.WRITE_CALENDAR',
  ),
  UtilityOption(
    'android.permission.READ_MEDIA_IMAGES',
    'Photos & images',
    description: 'android.permission.READ_MEDIA_IMAGES',
  ),
  UtilityOption(
    'android.permission.READ_MEDIA_VIDEO',
    'Videos',
    description: 'android.permission.READ_MEDIA_VIDEO',
  ),
  UtilityOption(
    'android.permission.READ_MEDIA_AUDIO',
    'Music & audio',
    description: 'android.permission.READ_MEDIA_AUDIO',
  ),
  UtilityOption(
    'android.permission.READ_EXTERNAL_STORAGE',
    'Storage (read, legacy)',
    description: 'android.permission.READ_EXTERNAL_STORAGE',
  ),
  UtilityOption(
    'android.permission.WRITE_EXTERNAL_STORAGE',
    'Storage (write, legacy)',
    description: 'android.permission.WRITE_EXTERNAL_STORAGE',
  ),
  UtilityOption(
    'android.permission.READ_PHONE_STATE',
    'Phone state',
    description: 'android.permission.READ_PHONE_STATE',
  ),
  UtilityOption(
    'android.permission.CALL_PHONE',
    'Place calls',
    description: 'android.permission.CALL_PHONE',
  ),
  UtilityOption(
    'android.permission.READ_CALL_LOG',
    'Call log (read)',
    description: 'android.permission.READ_CALL_LOG',
  ),
  UtilityOption(
    'android.permission.SEND_SMS',
    'SMS (send)',
    description: 'android.permission.SEND_SMS',
  ),
  UtilityOption(
    'android.permission.READ_SMS',
    'SMS (read)',
    description: 'android.permission.READ_SMS',
  ),
  UtilityOption(
    'android.permission.RECEIVE_SMS',
    'SMS (receive)',
    description: 'android.permission.RECEIVE_SMS',
  ),
  UtilityOption(
    'android.permission.BODY_SENSORS',
    'Body sensors',
    description: 'android.permission.BODY_SENSORS',
  ),
  UtilityOption(
    'android.permission.ACTIVITY_RECOGNITION',
    'Physical activity',
    description: 'android.permission.ACTIVITY_RECOGNITION',
  ),
  UtilityOption(
    'android.permission.BLUETOOTH_CONNECT',
    'Bluetooth (connect)',
    description: 'android.permission.BLUETOOTH_CONNECT',
  ),
  UtilityOption(
    'android.permission.BLUETOOTH_SCAN',
    'Bluetooth (scan)',
    description: 'android.permission.BLUETOOTH_SCAN',
  ),
  UtilityOption(
    'android.permission.NEARBY_WIFI_DEVICES',
    'Nearby Wi-Fi devices',
    description: 'android.permission.NEARBY_WIFI_DEVICES',
  ),
];

// ── `dumpsys` services ────────────────────────────────────────────────────

/// The `dumpsys` services worth a shortcut. `dumpsys -l` on the device lists
/// the full set, which varies by OEM and API level.
const List<UtilityOption> dumpsysServices = [
  UtilityOption('battery', 'battery', description: 'Charge, health, source'),
  UtilityOption('power', 'power', description: 'Wake locks and doze state'),
  UtilityOption('activity', 'activity', description: 'Activity manager state'),
  UtilityOption('window', 'window', description: 'Windows, focus, rotation'),
  UtilityOption('package', 'package', description: 'Installed packages'),
  UtilityOption('wifi', 'wifi', description: 'Wi-Fi state and scan results'),
  UtilityOption('connectivity', 'connectivity', description: 'Network state'),
  UtilityOption(
    'telephony.registry',
    'telephony.registry',
    description: 'Signal, SIM and call state',
  ),
  UtilityOption('meminfo', 'meminfo', description: 'Memory use per process'),
  UtilityOption('cpuinfo', 'cpuinfo', description: 'CPU use per process'),
  UtilityOption('gfxinfo', 'gfxinfo', description: 'Frame render timings'),
  UtilityOption('input', 'input', description: 'Input devices and focus'),
  UtilityOption(
    'notification',
    'notification',
    description: 'Posted notifications',
  ),
  UtilityOption('alarm', 'alarm', description: 'Scheduled alarms'),
  UtilityOption('jobscheduler', 'jobscheduler', description: 'Scheduled jobs'),
  UtilityOption('display', 'display', description: 'Displays and density'),
  UtilityOption('audio', 'audio', description: 'Audio routing and volumes'),
  UtilityOption('location', 'location', description: 'Location providers'),
  UtilityOption('usagestats', 'usagestats', description: 'App usage history'),
  UtilityOption('deviceidle', 'deviceidle', description: 'Doze / idle state'),
];

// ── Screen overrides ──────────────────────────────────────────────────────

const List<UtilityOption> screenResolutions = [
  UtilityOption('reset', 'reset', description: 'Back to the physical size'),
  UtilityOption('720x1280', '720 × 1280', description: 'HD phone'),
  UtilityOption('1080x1920', '1080 × 1920', description: 'Full HD phone'),
  UtilityOption('1080x2400', '1080 × 2400', description: 'Modern tall phone'),
  UtilityOption('1440x3120', '1440 × 3120', description: 'QHD+ flagship'),
  UtilityOption('1600x2560', '1600 × 2560', description: 'Tablet'),
];

const List<UtilityOption> screenDensities = [
  UtilityOption('reset', 'reset', description: 'Back to the physical density'),
  UtilityOption('240', '240 dpi', description: 'hdpi'),
  UtilityOption('320', '320 dpi', description: 'xhdpi'),
  UtilityOption('420', '420 dpi', description: 'Common phone default'),
  UtilityOption('480', '480 dpi', description: 'xxhdpi'),
  UtilityOption('560', '560 dpi', description: 'Large flagship'),
  UtilityOption('640', '640 dpi', description: 'xxxhdpi'),
];
