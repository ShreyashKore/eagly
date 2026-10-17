// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'ios.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$IosError {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is IosError);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'IosError()';
}


}

/// @nodoc
class $IosErrorCopyWith<$Res>  {
$IosErrorCopyWith(IosError _, $Res Function(IosError) __);
}


/// Adds pattern-matching-related methods to [IosError].
extension IosErrorPatterns on IosError {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( IosError_UsbmuxdUnavailable value)?  usbmuxdUnavailable,TResult Function( IosError_DeviceNotFound value)?  deviceNotFound,TResult Function( IosError_NotPaired value)?  notPaired,TResult Function( IosError_PairingDialogPending value)?  pairingDialogPending,TResult Function( IosError_Locked value)?  locked,TResult Function( IosError_Other value)?  other,required TResult orElse(),}){
final _that = this;
switch (_that) {
case IosError_UsbmuxdUnavailable() when usbmuxdUnavailable != null:
return usbmuxdUnavailable(_that);case IosError_DeviceNotFound() when deviceNotFound != null:
return deviceNotFound(_that);case IosError_NotPaired() when notPaired != null:
return notPaired(_that);case IosError_PairingDialogPending() when pairingDialogPending != null:
return pairingDialogPending(_that);case IosError_Locked() when locked != null:
return locked(_that);case IosError_Other() when other != null:
return other(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( IosError_UsbmuxdUnavailable value)  usbmuxdUnavailable,required TResult Function( IosError_DeviceNotFound value)  deviceNotFound,required TResult Function( IosError_NotPaired value)  notPaired,required TResult Function( IosError_PairingDialogPending value)  pairingDialogPending,required TResult Function( IosError_Locked value)  locked,required TResult Function( IosError_Other value)  other,}){
final _that = this;
switch (_that) {
case IosError_UsbmuxdUnavailable():
return usbmuxdUnavailable(_that);case IosError_DeviceNotFound():
return deviceNotFound(_that);case IosError_NotPaired():
return notPaired(_that);case IosError_PairingDialogPending():
return pairingDialogPending(_that);case IosError_Locked():
return locked(_that);case IosError_Other():
return other(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( IosError_UsbmuxdUnavailable value)?  usbmuxdUnavailable,TResult? Function( IosError_DeviceNotFound value)?  deviceNotFound,TResult? Function( IosError_NotPaired value)?  notPaired,TResult? Function( IosError_PairingDialogPending value)?  pairingDialogPending,TResult? Function( IosError_Locked value)?  locked,TResult? Function( IosError_Other value)?  other,}){
final _that = this;
switch (_that) {
case IosError_UsbmuxdUnavailable() when usbmuxdUnavailable != null:
return usbmuxdUnavailable(_that);case IosError_DeviceNotFound() when deviceNotFound != null:
return deviceNotFound(_that);case IosError_NotPaired() when notPaired != null:
return notPaired(_that);case IosError_PairingDialogPending() when pairingDialogPending != null:
return pairingDialogPending(_that);case IosError_Locked() when locked != null:
return locked(_that);case IosError_Other() when other != null:
return other(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  usbmuxdUnavailable,TResult Function( String field0)?  deviceNotFound,TResult Function( String field0)?  notPaired,TResult Function( String field0)?  pairingDialogPending,TResult Function( String field0)?  locked,TResult Function( String field0)?  other,required TResult orElse(),}) {final _that = this;
switch (_that) {
case IosError_UsbmuxdUnavailable() when usbmuxdUnavailable != null:
return usbmuxdUnavailable();case IosError_DeviceNotFound() when deviceNotFound != null:
return deviceNotFound(_that.field0);case IosError_NotPaired() when notPaired != null:
return notPaired(_that.field0);case IosError_PairingDialogPending() when pairingDialogPending != null:
return pairingDialogPending(_that.field0);case IosError_Locked() when locked != null:
return locked(_that.field0);case IosError_Other() when other != null:
return other(_that.field0);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  usbmuxdUnavailable,required TResult Function( String field0)  deviceNotFound,required TResult Function( String field0)  notPaired,required TResult Function( String field0)  pairingDialogPending,required TResult Function( String field0)  locked,required TResult Function( String field0)  other,}) {final _that = this;
switch (_that) {
case IosError_UsbmuxdUnavailable():
return usbmuxdUnavailable();case IosError_DeviceNotFound():
return deviceNotFound(_that.field0);case IosError_NotPaired():
return notPaired(_that.field0);case IosError_PairingDialogPending():
return pairingDialogPending(_that.field0);case IosError_Locked():
return locked(_that.field0);case IosError_Other():
return other(_that.field0);}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  usbmuxdUnavailable,TResult? Function( String field0)?  deviceNotFound,TResult? Function( String field0)?  notPaired,TResult? Function( String field0)?  pairingDialogPending,TResult? Function( String field0)?  locked,TResult? Function( String field0)?  other,}) {final _that = this;
switch (_that) {
case IosError_UsbmuxdUnavailable() when usbmuxdUnavailable != null:
return usbmuxdUnavailable();case IosError_DeviceNotFound() when deviceNotFound != null:
return deviceNotFound(_that.field0);case IosError_NotPaired() when notPaired != null:
return notPaired(_that.field0);case IosError_PairingDialogPending() when pairingDialogPending != null:
return pairingDialogPending(_that.field0);case IosError_Locked() when locked != null:
return locked(_that.field0);case IosError_Other() when other != null:
return other(_that.field0);case _:
  return null;

}
}

}

/// @nodoc


class IosError_UsbmuxdUnavailable extends IosError {
  const IosError_UsbmuxdUnavailable(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is IosError_UsbmuxdUnavailable);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'IosError.usbmuxdUnavailable()';
}


}




/// @nodoc


class IosError_DeviceNotFound extends IosError {
  const IosError_DeviceNotFound(this.field0): super._();
  

 final  String field0;

/// Create a copy of IosError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$IosError_DeviceNotFoundCopyWith<IosError_DeviceNotFound> get copyWith => _$IosError_DeviceNotFoundCopyWithImpl<IosError_DeviceNotFound>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is IosError_DeviceNotFound&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'IosError.deviceNotFound(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $IosError_DeviceNotFoundCopyWith<$Res> implements $IosErrorCopyWith<$Res> {
  factory $IosError_DeviceNotFoundCopyWith(IosError_DeviceNotFound value, $Res Function(IosError_DeviceNotFound) _then) = _$IosError_DeviceNotFoundCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$IosError_DeviceNotFoundCopyWithImpl<$Res>
    implements $IosError_DeviceNotFoundCopyWith<$Res> {
  _$IosError_DeviceNotFoundCopyWithImpl(this._self, this._then);

  final IosError_DeviceNotFound _self;
  final $Res Function(IosError_DeviceNotFound) _then;

/// Create a copy of IosError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(IosError_DeviceNotFound(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class IosError_NotPaired extends IosError {
  const IosError_NotPaired(this.field0): super._();
  

 final  String field0;

/// Create a copy of IosError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$IosError_NotPairedCopyWith<IosError_NotPaired> get copyWith => _$IosError_NotPairedCopyWithImpl<IosError_NotPaired>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is IosError_NotPaired&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'IosError.notPaired(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $IosError_NotPairedCopyWith<$Res> implements $IosErrorCopyWith<$Res> {
  factory $IosError_NotPairedCopyWith(IosError_NotPaired value, $Res Function(IosError_NotPaired) _then) = _$IosError_NotPairedCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$IosError_NotPairedCopyWithImpl<$Res>
    implements $IosError_NotPairedCopyWith<$Res> {
  _$IosError_NotPairedCopyWithImpl(this._self, this._then);

  final IosError_NotPaired _self;
  final $Res Function(IosError_NotPaired) _then;

/// Create a copy of IosError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(IosError_NotPaired(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class IosError_PairingDialogPending extends IosError {
  const IosError_PairingDialogPending(this.field0): super._();
  

 final  String field0;

/// Create a copy of IosError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$IosError_PairingDialogPendingCopyWith<IosError_PairingDialogPending> get copyWith => _$IosError_PairingDialogPendingCopyWithImpl<IosError_PairingDialogPending>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is IosError_PairingDialogPending&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'IosError.pairingDialogPending(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $IosError_PairingDialogPendingCopyWith<$Res> implements $IosErrorCopyWith<$Res> {
  factory $IosError_PairingDialogPendingCopyWith(IosError_PairingDialogPending value, $Res Function(IosError_PairingDialogPending) _then) = _$IosError_PairingDialogPendingCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$IosError_PairingDialogPendingCopyWithImpl<$Res>
    implements $IosError_PairingDialogPendingCopyWith<$Res> {
  _$IosError_PairingDialogPendingCopyWithImpl(this._self, this._then);

  final IosError_PairingDialogPending _self;
  final $Res Function(IosError_PairingDialogPending) _then;

/// Create a copy of IosError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(IosError_PairingDialogPending(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class IosError_Locked extends IosError {
  const IosError_Locked(this.field0): super._();
  

 final  String field0;

/// Create a copy of IosError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$IosError_LockedCopyWith<IosError_Locked> get copyWith => _$IosError_LockedCopyWithImpl<IosError_Locked>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is IosError_Locked&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'IosError.locked(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $IosError_LockedCopyWith<$Res> implements $IosErrorCopyWith<$Res> {
  factory $IosError_LockedCopyWith(IosError_Locked value, $Res Function(IosError_Locked) _then) = _$IosError_LockedCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$IosError_LockedCopyWithImpl<$Res>
    implements $IosError_LockedCopyWith<$Res> {
  _$IosError_LockedCopyWithImpl(this._self, this._then);

  final IosError_Locked _self;
  final $Res Function(IosError_Locked) _then;

/// Create a copy of IosError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(IosError_Locked(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class IosError_Other extends IosError {
  const IosError_Other(this.field0): super._();
  

 final  String field0;

/// Create a copy of IosError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$IosError_OtherCopyWith<IosError_Other> get copyWith => _$IosError_OtherCopyWithImpl<IosError_Other>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is IosError_Other&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'IosError.other(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $IosError_OtherCopyWith<$Res> implements $IosErrorCopyWith<$Res> {
  factory $IosError_OtherCopyWith(IosError_Other value, $Res Function(IosError_Other) _then) = _$IosError_OtherCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$IosError_OtherCopyWithImpl<$Res>
    implements $IosError_OtherCopyWith<$Res> {
  _$IosError_OtherCopyWithImpl(this._self, this._then);

  final IosError_Other _self;
  final $Res Function(IosError_Other) _then;

/// Create a copy of IosError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(IosError_Other(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
