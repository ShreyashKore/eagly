/// Turns `adb install` output into one short sentence a person can act on.
///
/// adb's failure text is a progress line, the APK's full path and the
/// package manager's `Failure [INSTALL_FAILED_…: detail]`, all on top of one
/// another. Only the status code and its detail say what went wrong, so the
/// known codes become a plain-language cause plus a fix, and an unknown code
/// falls back to the code and its detail without the noise around it. The raw
/// output still goes to the log.
///
/// Returns null when [output] holds nothing recognisable.
String? describeAdbInstallFailure(String output) {
  final failure = _failurePattern.firstMatch(output);
  if (failure != null) {
    final code = failure.group(1)!;
    final detail = (failure.group(2) ?? '').trim();
    return _explain(code, detail) ?? _fallback(code, detail);
  }

  final transport = _transportError(output);
  if (transport != null) return transport;

  // Lines adb prints on the way to failing, which say nothing about why.
  final lines = output
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .where((line) => !line.startsWith('Performing '))
      .toList();
  if (lines.isEmpty) return null;
  final last = lines.last.replaceFirst(_adbPrefix, '');
  return last.isEmpty ? null : _sentence(last);
}

/// `Failure [CODE]` or `Failure [CODE: detail]`; the detail may span lines.
final _failurePattern = RegExp(r'Failure \[([A-Z0-9_]+)(?::\s*([\s\S]*?))?\]');

final _adbPrefix = RegExp(r'^adb: (?:error: )?');

String? _explain(String code, String detail) {
  switch (code) {
    case 'INSTALL_FAILED_VERSION_DOWNGRADE':
      final versions = RegExp(
        r'version code (\d+) is older than current (\d+)',
      ).firstMatch(detail);
      if (versions == null) {
        return 'A newer version of this app is already installed. '
            'Uninstall it first, or install a newer build.';
      }
      final current = versions.group(2);
      return 'The device already has a newer version of this app (version '
          'code $current; this APK is ${versions.group(1)}). Uninstall the '
          'app first, or install a build with version code $current or '
          'higher.';
    case 'INSTALL_FAILED_UPDATE_INCOMPATIBLE':
      final package = RegExp(r'Package (\S+)').firstMatch(detail)?.group(1);
      final app = package ?? 'the installed app';
      return 'The installed copy of $app is signed with a different key. '
          'Uninstall it first, then install again.';
    case 'INSTALL_FAILED_ALREADY_EXISTS':
      return 'This app is already installed. Uninstall it first.';
    case 'INSTALL_FAILED_INSUFFICIENT_STORAGE':
      return 'The device is out of storage. Free some space and try again.';
    case 'INSTALL_FAILED_OLDER_SDK':
      final sdks = RegExp(
        r'newer sdk version #(\d+) \(current version is #(\d+)\)',
      ).firstMatch(detail);
      if (sdks == null) {
        return 'This APK needs a newer Android version than the device runs.';
      }
      return 'This APK needs Android API ${sdks.group(1)} or newer; the '
          'device runs API ${sdks.group(2)}.';
    case 'INSTALL_FAILED_DEPRECATED_SDK_VERSION':
      return "The APK's targetSdkVersion is too old for this Android version. "
          'Rebuild it with a newer targetSdkVersion.';
    case 'INSTALL_FAILED_NO_MATCHING_ABIS':
      return "The APK has no native code for this device's CPU "
          '(for example, an x86-only build on an ARM device).';
    case 'INSTALL_FAILED_USER_RESTRICTED':
    case 'INSTALL_FAILED_ABORTED':
      return 'The device blocked the install. Accept the prompt on the '
          'device, or turn on "Install via USB" in Developer options.';
    case 'INSTALL_FAILED_VERIFICATION_FAILURE':
      return 'The device rejected the APK during verification (often Play '
          'Protect). Check the device for a prompt.';
    case 'INSTALL_FAILED_MISSING_SPLIT':
      return 'This APK is one part of a split app; it needs the other split '
          'APKs installed with it.';
    case 'INSTALL_FAILED_DUPLICATE_PERMISSION':
    case 'INSTALL_FAILED_CONFLICTING_PROVIDER':
      return 'Another installed app already declares something this APK '
          'declares. Uninstall the other app first'
          '${detail.isEmpty ? '.' : ' ($detail).'}';
    case 'INSTALL_FAILED_MISSING_SHARED_LIBRARY':
      return 'The device is missing a library this APK requires'
          '${detail.isEmpty ? '.' : ' ($detail).'}';
    case 'INSTALL_PARSE_FAILED_NO_CERTIFICATES':
      return 'The APK is not signed. Sign it (a debug key is fine) and try '
          'again.';
    case 'INSTALL_PARSE_FAILED_NOT_APK':
    case 'INSTALL_FAILED_INVALID_APK':
    case 'INSTALL_PARSE_FAILED_UNEXPECTED_EXCEPTION':
      return 'The file is not a valid APK, or it is damaged.';
  }
  return null;
}

/// An unknown code: keep it, since it is what people search for, and the
/// first line of its detail.
String _fallback(String code, String detail) {
  final firstLine = detail.split('\n').first.trim();
  return _sentence(firstLine.isEmpty ? code : '$code: $firstLine');
}

/// adb failing before the package manager is ever reached.
String? _transportError(String output) {
  final normalized = output.toLowerCase();
  if (normalized.contains('device unauthorized')) {
    return 'The device has not authorized this computer. Accept the USB '
        'debugging prompt on the device.';
  }
  if (normalized.contains('device offline')) {
    return 'The device is offline. Reconnect it and try again.';
  }
  if (normalized.contains('not found') &&
      (normalized.contains("device '") || normalized.contains('no devices'))) {
    return 'The device is no longer connected.';
  }
  return null;
}

String _sentence(String text) =>
    text.endsWith('.') || text.endsWith('!') ? text : '$text.';
