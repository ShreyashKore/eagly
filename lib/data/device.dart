class Device {
  final String id;
  final String status;
  final String? model;
  final String? name;

  Device(this.id, this.status, {this.model, this.name});

  String get displayName {
    if (model != null && name != null) {
      return '$name ($model)';
    } else if (model != null) {
      return model!;
    } else if (name != null) {
      return name!;
    }
    return id;
  }

  @override
  String toString() {
    return 'Device(id: $id, status: $status, model: $model, name: $name)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is Device &&
      other.id == id &&
      other.status == status &&
      other.model == model &&
      other.name == name;
  }

  @override
  int get hashCode => Object.hash(id, status, model, name);
}
