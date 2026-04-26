enum DevicePlatform { android, ios }

enum DeviceConnectionState { connected, disconnected }

class Device {
  final String id;
  final String status;
  final String? brand;
  final String? model;
  final String? name;
  final DevicePlatform platform;
  final DeviceConnectionState connectionState;

  Device(
    this.id,
    this.status, {
    this.brand,
    this.model,
    this.name,
    this.platform = DevicePlatform.android,
    this.connectionState = DeviceConnectionState.connected,
  });

  bool get isAndroid => platform == DevicePlatform.android;
  bool get isIos => platform == DevicePlatform.ios;
  bool get isConnected => connectionState == DeviceConnectionState.connected;
  bool get isDisconnected => !isConnected;

  String get statusLabel => isDisconnected ? 'disconnected' : status;

  ({String primary, String? secondary}) get displayLabel =>
      (primary: _primaryLabel, secondary: _secondaryLabel);

  String get _primaryLabel => isAndroid ? id : name ?? model ?? brand ?? id;

  String get displayName {
    if (isAndroid) {
      return _androidDisplayName;
    }

    if (model != null && name != null) {
      return '$model ($name)';
    } else if (model != null) {
      return model!;
    } else if (name != null) {
      return name!;
    }
    return id;
  }

  String? get _secondaryLabel {
    if (isAndroid) {
      return _androidPrimaryLabel ?? _normalizedValue(name);
    }

    final normalizedModel = _normalizedValue(model);
    final normalizedName = _normalizedValue(name);
    if (normalizedModel != null &&
        _isDistinctFrom(normalizedModel, normalizedName)) {
      return normalizedModel;
    }
    return normalizedModel ?? normalizedName;
  }

  String get _androidDisplayName {
    final primary = _androidPrimaryLabel;
    if (primary != null && _isDistinctFrom(primary, name)) {
      return '$primary ($id)';
    }
    if (primary != null) {
      return primary;
    }
    if (name != null) {
      return name!;
    }
    if (model != null) {
      return model!;
    }
    if (brand != null) {
      return brand!;
    }
    return id;
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

  Device copyWith({
    String? id,
    String? status,
    String? brand,
    String? model,
    String? name,
    DevicePlatform? platform,
    DeviceConnectionState? connectionState,
  }) {
    return Device(
      id ?? this.id,
      status ?? this.status,
      brand: brand ?? this.brand,
      model: model ?? this.model,
      name: name ?? this.name,
      platform: platform ?? this.platform,
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
