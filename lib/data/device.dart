enum DevicePlatform { android, ios }

enum DeviceConnectionState { connected, disconnected }

sealed class Device {
  final String id;
  final String status;
  final String? brand;
  final String? model;
  final String? name;
  final DeviceConnectionState connectionState;

  const Device._(
    this.id,
    this.status, {
    this.brand,
    this.model,
    this.name,
    this.connectionState = DeviceConnectionState.connected,
  });

  static const String _statusOnline = 'device';

  factory Device(
    String id,
    String status, {
    String? brand,
    String? model,
    String? name,
    DevicePlatform platform = DevicePlatform.android,
    DeviceConnectionState connectionState = DeviceConnectionState.connected,
  }) {
    return _buildDevice(
      platform: platform,
      id: id,
      status: status,
      brand: brand,
      model: model,
      name: name,
      connectionState: connectionState,
    );
  }

  factory Device.android(
    String id,
    String status, {
    String? brand,
    String? model,
    String? name,
    DeviceConnectionState connectionState = DeviceConnectionState.connected,
  }) {
    return AndroidDevice(
      id,
      status,
      brand: brand,
      model: model,
      name: name,
      connectionState: connectionState,
    );
  }

  factory Device.ios(
    String id,
    String status, {
    String? brand,
    String? model,
    String? name,
    DeviceConnectionState connectionState = DeviceConnectionState.connected,
  }) {
    return IosDevice(
      id,
      status,
      brand: brand,
      model: model,
      name: name,
      connectionState: connectionState,
    );
  }

  DevicePlatform get platform;

  bool get isConnected => connectionState == DeviceConnectionState.connected;
  bool get isDisconnected => !isConnected;

  String get statusLabel {
    if (isDisconnected) return 'disconnected';
    return switch (status) {
      _statusOnline => 'online',
      _ => status,
    };
  }

  ({String primary, String? secondary}) get displayLabel;

  String get displayName;

  Device copyWith({
    String? id,
    String? status,
    String? brand,
    String? model,
    String? name,
    DevicePlatform? platform,
    DeviceConnectionState? connectionState,
  }) {
    return _buildDevice(
      platform: platform ?? this.platform,
      id: id ?? this.id,
      status: status ?? this.status,
      brand: brand ?? this.brand,
      model: model ?? this.model,
      name: name ?? this.name,
      connectionState: connectionState ?? this.connectionState,
    );
  }

  @override
  String toString() {
    return 'Device(id: $id, status: $status, brand: $brand, model: $model, name: $name, platform: $platform, connectionState: $connectionState)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is Device &&
        other.id == id &&
        other.status == status &&
        other.brand == brand &&
        other.model == model &&
        other.name == name &&
        other.platform == platform &&
        other.connectionState == connectionState;
  }

  @override
  int get hashCode =>
      Object.hash(id, status, brand, model, name, platform, connectionState);
}

final class AndroidDevice extends Device {
  const AndroidDevice(
    super.id,
    super.status, {
    super.brand,
    super.model,
    super.name,
    super.connectionState,
    this.serialNumber,
  }) : super._();

  /// Underlying device serial number, populated when available (e.g. from
  /// `adb shell getprop ro.serialno`). Used internally for deduplication.
  final String? serialNumber;

  @override
  DevicePlatform get platform => DevicePlatform.android;

  /// True when this device is connected over Wi-Fi (TCP/IP or mDNS ADB TLS).
  bool get isWireless {
    if (RegExp(r'^\d+\.\d+\.\d+\.\d+:\d+$').hasMatch(id)) return true;
    if (id.contains('._adb-tls-')) return true;
    return false;
  }

  @override
  AndroidDevice copyWith({
    String? id,
    String? status,
    String? brand,
    String? model,
    String? name,
    DevicePlatform? platform,
    DeviceConnectionState? connectionState,
    String? serialNumber,
  }) {
    return AndroidDevice(
      id ?? this.id,
      status ?? this.status,
      brand: brand ?? this.brand,
      model: model ?? this.model,
      name: name ?? this.name,
      connectionState: connectionState ?? this.connectionState,
      serialNumber: serialNumber ?? this.serialNumber,
    );
  }

  @override
  ({String primary, String? secondary}) get displayLabel {
    if (isWireless) {
      final label = _androidPrimaryLabel;
      final hint = _wirelessShortId;
      if (label != null) {
        // Brand/model as primary; short wireless ID as disambiguating secondary.
        return (primary: label, secondary: hint);
      }
      return (primary: hint, secondary: null);
    }
    return (
      primary: _subString(id, 10),
      secondary: _androidPrimaryLabel ?? _normalizedValue(name),
    );
  }

  String _subString(String value, int maxLength) {
    if (value.length <= maxLength) {
      return value;
    }
    return '${value.substring(0, maxLength)}...';
  }

  @override
  String get displayName {
    final primary = _androidPrimaryLabel;
    if (isWireless) {
      // Never append the full mDNS or IP:port ID — it's unreadable noise.
      return primary ??
          _normalizedValue(name) ??
          _normalizedValue(model) ??
          _normalizedValue(brand) ??
          _wirelessShortId;
    }
    if (primary != null && _isDistinctFrom(primary, name)) {
      return '$primary ($id)';
    }
    return primary ??
        _normalizedValue(name) ??
        _normalizedValue(model) ??
        _normalizedValue(brand) ??
        id;
  }

  /// A short, human-readable identifier derived from the wireless ADB device
  /// ID. For mDNS IDs the embedded serial is extracted; for IP:port IDs the
  /// ephemeral port is dropped so only the IP address remains.
  String get _wirelessShortId {
    // IP:port — drop the port, show just the IP.
    if (RegExp(r'^\d+\.\d+\.\d+\.\d+:\d+$').hasMatch(id)) {
      return id.split(':').first;
    }
    // mDNS: adb-SERIAL-suffix._adb-tls-connect._tcp — extract the serial.
    final match = RegExp(r'^adb-([A-Za-z0-9]+)-').firstMatch(id);
    if (match != null) return match.group(1)!;
    return _subString(id, 12);
  }

  String? get _androidPrimaryLabel {
    final normalizedBrand = _normalizedValue(brand);
    final normalizedModel = _normalizedValue(model);
    if (normalizedBrand == null) {
      return normalizedModel;
    }
    if (normalizedModel == null) {
      return normalizedBrand;
    }
    if (normalizedModel.toLowerCase().startsWith(
      normalizedBrand.toLowerCase(),
    )) {
      return normalizedModel;
    }
    return '$normalizedBrand $normalizedModel';
  }
}

final class IosDevice extends Device {
  const IosDevice(
    super.id,
    super.status, {
    super.brand,
    super.model,
    super.name,
    super.connectionState,
  }) : super._();

  @override
  DevicePlatform get platform => DevicePlatform.ios;

  @override
  ({String primary, String? secondary}) get displayLabel {
    final primary =
        _normalizedValue(name) ??
        _normalizedValue(model) ??
        _normalizedValue(brand) ??
        id;
    final secondary = _normalizedValue(model);
    return (
      primary: primary,
      secondary: _isDistinctFrom(primary, secondary) ? secondary : null,
    );
  }

  @override
  String get displayName {
    final normalizedModel = _normalizedValue(model);
    final normalizedName = _normalizedValue(name);
    if (normalizedModel != null && normalizedName != null) {
      return _isDistinctFrom(normalizedModel, normalizedName)
          ? '$normalizedModel ($normalizedName)'
          : normalizedModel;
    }
    return normalizedModel ?? normalizedName ?? id;
  }
}

Device _buildDevice({
  required DevicePlatform platform,
  required String id,
  required String status,
  String? brand,
  String? model,
  String? name,
  DeviceConnectionState connectionState = DeviceConnectionState.connected,
}) {
  return switch (platform) {
    DevicePlatform.android => AndroidDevice(
      id,
      status,
      brand: brand,
      model: model,
      name: name,
      connectionState: connectionState,
    ),
    DevicePlatform.ios => IosDevice(
      id,
      status,
      brand: brand,
      model: model,
      name: name,
      connectionState: connectionState,
    ),
  };
}

String? _normalizedValue(String? value) {
  if (value == null) {
    return null;
  }
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

bool _isDistinctFrom(String primary, String? candidate) {
  final normalizedCandidate = _normalizedValue(candidate);
  if (normalizedCandidate == null) {
    return false;
  }

  final loweredPrimary = primary.toLowerCase();
  final loweredCandidate = normalizedCandidate.toLowerCase();
  return loweredPrimary != loweredCandidate &&
      !loweredPrimary.contains(loweredCandidate) &&
      !loweredCandidate.contains(loweredPrimary);
}
