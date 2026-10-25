// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'session.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$CoreError {

 String get message;
/// Create a copy of CoreError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CoreErrorCopyWith<CoreError> get copyWith => _$CoreErrorCopyWithImpl<CoreError>(this as CoreError, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as CoreError;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CoreError&&(identical(other.message, _this.message) || other.message == _this.message));
}


@override
int get hashCode {
  final _this = this as CoreError;
  return Object.hash(runtimeType,_this.message);
}

@override
String toString() {
  final _this = this as CoreError;
  return 'CoreError(message: ${_this.message})';
}


}

/// @nodoc
abstract mixin class $CoreErrorCopyWith<$Res>  {
  factory $CoreErrorCopyWith(CoreError value, $Res Function(CoreError) _then) = _$CoreErrorCopyWithImpl;
@useResult
$Res call({
 String message
});




}
/// @nodoc
class _$CoreErrorCopyWithImpl<$Res>
    implements $CoreErrorCopyWith<$Res> {
  _$CoreErrorCopyWithImpl(this._self, this._then);

  final CoreError _self;
  final $Res Function(CoreError) _then;

/// Create a copy of CoreError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? message = null,}) {
  return _then(_self.copyWith(
message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [CoreError].
extension CoreErrorPatterns on CoreError {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( CoreError_InvalidAddress value)?  invalidAddress,TResult Function( CoreError_BlockedAddress value)?  blockedAddress,TResult Function( CoreError_Connection value)?  connection,TResult Function( CoreError_Internal value)?  internal,required TResult orElse(),}){
final _that = this;
switch (_that) {
case CoreError_InvalidAddress() when invalidAddress != null:
return invalidAddress(_that);case CoreError_BlockedAddress() when blockedAddress != null:
return blockedAddress(_that);case CoreError_Connection() when connection != null:
return connection(_that);case CoreError_Internal() when internal != null:
return internal(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( CoreError_InvalidAddress value)  invalidAddress,required TResult Function( CoreError_BlockedAddress value)  blockedAddress,required TResult Function( CoreError_Connection value)  connection,required TResult Function( CoreError_Internal value)  internal,}){
final _that = this;
switch (_that) {
case CoreError_InvalidAddress():
return invalidAddress(_that);case CoreError_BlockedAddress():
return blockedAddress(_that);case CoreError_Connection():
return connection(_that);case CoreError_Internal():
return internal(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( CoreError_InvalidAddress value)?  invalidAddress,TResult? Function( CoreError_BlockedAddress value)?  blockedAddress,TResult? Function( CoreError_Connection value)?  connection,TResult? Function( CoreError_Internal value)?  internal,}){
final _that = this;
switch (_that) {
case CoreError_InvalidAddress() when invalidAddress != null:
return invalidAddress(_that);case CoreError_BlockedAddress() when blockedAddress != null:
return blockedAddress(_that);case CoreError_Connection() when connection != null:
return connection(_that);case CoreError_Internal() when internal != null:
return internal(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String message)?  invalidAddress,TResult Function( String message)?  blockedAddress,TResult Function( String message)?  connection,TResult Function( String message)?  internal,required TResult orElse(),}) {final _that = this;
switch (_that) {
case CoreError_InvalidAddress() when invalidAddress != null:
return invalidAddress(_that.message);case CoreError_BlockedAddress() when blockedAddress != null:
return blockedAddress(_that.message);case CoreError_Connection() when connection != null:
return connection(_that.message);case CoreError_Internal() when internal != null:
return internal(_that.message);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String message)  invalidAddress,required TResult Function( String message)  blockedAddress,required TResult Function( String message)  connection,required TResult Function( String message)  internal,}) {final _that = this;
switch (_that) {
case CoreError_InvalidAddress():
return invalidAddress(_that.message);case CoreError_BlockedAddress():
return blockedAddress(_that.message);case CoreError_Connection():
return connection(_that.message);case CoreError_Internal():
return internal(_that.message);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String message)?  invalidAddress,TResult? Function( String message)?  blockedAddress,TResult? Function( String message)?  connection,TResult? Function( String message)?  internal,}) {final _that = this;
switch (_that) {
case CoreError_InvalidAddress() when invalidAddress != null:
return invalidAddress(_that.message);case CoreError_BlockedAddress() when blockedAddress != null:
return blockedAddress(_that.message);case CoreError_Connection() when connection != null:
return connection(_that.message);case CoreError_Internal() when internal != null:
return internal(_that.message);case _:
  return null;

}
}

}

/// @nodoc


class CoreError_InvalidAddress extends CoreError {
  const CoreError_InvalidAddress({required this.message}): super._();
  

@override final  String message;

/// Create a copy of CoreError
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CoreError_InvalidAddressCopyWith<CoreError_InvalidAddress> get copyWith => _$CoreError_InvalidAddressCopyWithImpl<CoreError_InvalidAddress>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CoreError_InvalidAddress&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode {
    return Object.hash(runtimeType,message);
}

@override
String toString() {
    return 'CoreError.invalidAddress(message: $message)';
}


}

/// @nodoc
abstract mixin class $CoreError_InvalidAddressCopyWith<$Res> implements $CoreErrorCopyWith<$Res> {
  factory $CoreError_InvalidAddressCopyWith(CoreError_InvalidAddress value, $Res Function(CoreError_InvalidAddress) _then) = _$CoreError_InvalidAddressCopyWithImpl;
@override @useResult
$Res call({
 String message
});




}
/// @nodoc
class _$CoreError_InvalidAddressCopyWithImpl<$Res>
    implements $CoreError_InvalidAddressCopyWith<$Res> {
  _$CoreError_InvalidAddressCopyWithImpl(this._self, this._then);

  final CoreError_InvalidAddress _self;
  final $Res Function(CoreError_InvalidAddress) _then;

/// Create a copy of CoreError
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? message = null,}) {
  return _then(CoreError_InvalidAddress(
message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class CoreError_BlockedAddress extends CoreError {
  const CoreError_BlockedAddress({required this.message}): super._();
  

@override final  String message;

/// Create a copy of CoreError
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CoreError_BlockedAddressCopyWith<CoreError_BlockedAddress> get copyWith => _$CoreError_BlockedAddressCopyWithImpl<CoreError_BlockedAddress>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CoreError_BlockedAddress&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode {
    return Object.hash(runtimeType,message);
}

@override
String toString() {
    return 'CoreError.blockedAddress(message: $message)';
}


}

/// @nodoc
abstract mixin class $CoreError_BlockedAddressCopyWith<$Res> implements $CoreErrorCopyWith<$Res> {
  factory $CoreError_BlockedAddressCopyWith(CoreError_BlockedAddress value, $Res Function(CoreError_BlockedAddress) _then) = _$CoreError_BlockedAddressCopyWithImpl;
@override @useResult
$Res call({
 String message
});




}
/// @nodoc
class _$CoreError_BlockedAddressCopyWithImpl<$Res>
    implements $CoreError_BlockedAddressCopyWith<$Res> {
  _$CoreError_BlockedAddressCopyWithImpl(this._self, this._then);

  final CoreError_BlockedAddress _self;
  final $Res Function(CoreError_BlockedAddress) _then;

/// Create a copy of CoreError
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? message = null,}) {
  return _then(CoreError_BlockedAddress(
message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class CoreError_Connection extends CoreError {
  const CoreError_Connection({required this.message}): super._();
  

@override final  String message;

/// Create a copy of CoreError
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CoreError_ConnectionCopyWith<CoreError_Connection> get copyWith => _$CoreError_ConnectionCopyWithImpl<CoreError_Connection>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CoreError_Connection&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode {
    return Object.hash(runtimeType,message);
}

@override
String toString() {
    return 'CoreError.connection(message: $message)';
}


}

/// @nodoc
abstract mixin class $CoreError_ConnectionCopyWith<$Res> implements $CoreErrorCopyWith<$Res> {
  factory $CoreError_ConnectionCopyWith(CoreError_Connection value, $Res Function(CoreError_Connection) _then) = _$CoreError_ConnectionCopyWithImpl;
@override @useResult
$Res call({
 String message
});




}
/// @nodoc
class _$CoreError_ConnectionCopyWithImpl<$Res>
    implements $CoreError_ConnectionCopyWith<$Res> {
  _$CoreError_ConnectionCopyWithImpl(this._self, this._then);

  final CoreError_Connection _self;
  final $Res Function(CoreError_Connection) _then;

/// Create a copy of CoreError
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? message = null,}) {
  return _then(CoreError_Connection(
message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class CoreError_Internal extends CoreError {
  const CoreError_Internal({required this.message}): super._();
  

@override final  String message;

/// Create a copy of CoreError
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CoreError_InternalCopyWith<CoreError_Internal> get copyWith => _$CoreError_InternalCopyWithImpl<CoreError_Internal>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CoreError_Internal&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode {
    return Object.hash(runtimeType,message);
}

@override
String toString() {
    return 'CoreError.internal(message: $message)';
}


}

/// @nodoc
abstract mixin class $CoreError_InternalCopyWith<$Res> implements $CoreErrorCopyWith<$Res> {
  factory $CoreError_InternalCopyWith(CoreError_Internal value, $Res Function(CoreError_Internal) _then) = _$CoreError_InternalCopyWithImpl;
@override @useResult
$Res call({
 String message
});




}
/// @nodoc
class _$CoreError_InternalCopyWithImpl<$Res>
    implements $CoreError_InternalCopyWith<$Res> {
  _$CoreError_InternalCopyWithImpl(this._self, this._then);

  final CoreError_Internal _self;
  final $Res Function(CoreError_Internal) _then;

/// Create a copy of CoreError
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? message = null,}) {
  return _then(CoreError_Internal(
message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$CoreEvent {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CoreEvent);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'CoreEvent()';
}


}

/// @nodoc
class $CoreEventCopyWith<$Res>  {
$CoreEventCopyWith(CoreEvent _, $Res Function(CoreEvent) __);
}


/// Adds pattern-matching-related methods to [CoreEvent].
extension CoreEventPatterns on CoreEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( CoreEvent_State value)?  state,TResult Function( CoreEvent_Servers value)?  servers,TResult Function( CoreEvent_Snapshot value)?  snapshot,TResult Function( CoreEvent_History value)?  history,TResult Function( CoreEvent_TextMessage value)?  textMessage,TResult Function( CoreEvent_ClientJoined value)?  clientJoined,TResult Function( CoreEvent_ClientLeft value)?  clientLeft,TResult Function( CoreEvent_ClientMoved value)?  clientMoved,TResult Function( CoreEvent_ClientUpdated value)?  clientUpdated,TResult Function( CoreEvent_Voice value)?  voice,TResult Function( CoreEvent_Speaking value)?  speaking,TResult Function( CoreEvent_SelfSpeaking value)?  selfSpeaking,TResult Function( CoreEvent_IdentityUpgrade value)?  identityUpgrade,TResult Function( CoreEvent_IdentityUpgraded value)?  identityUpgraded,TResult Function( CoreEvent_TransferStarted value)?  transferStarted,TResult Function( CoreEvent_TransferProgress value)?  transferProgress,TResult Function( CoreEvent_TransferFinished value)?  transferFinished,TResult Function( CoreEvent_Log value)?  log,TResult Function( CoreEvent_Denied value)?  denied,TResult Function( CoreEvent_Failed value)?  failed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case CoreEvent_State() when state != null:
return state(_that);case CoreEvent_Servers() when servers != null:
return servers(_that);case CoreEvent_Snapshot() when snapshot != null:
return snapshot(_that);case CoreEvent_History() when history != null:
return history(_that);case CoreEvent_TextMessage() when textMessage != null:
return textMessage(_that);case CoreEvent_ClientJoined() when clientJoined != null:
return clientJoined(_that);case CoreEvent_ClientLeft() when clientLeft != null:
return clientLeft(_that);case CoreEvent_ClientMoved() when clientMoved != null:
return clientMoved(_that);case CoreEvent_ClientUpdated() when clientUpdated != null:
return clientUpdated(_that);case CoreEvent_Voice() when voice != null:
return voice(_that);case CoreEvent_Speaking() when speaking != null:
return speaking(_that);case CoreEvent_SelfSpeaking() when selfSpeaking != null:
return selfSpeaking(_that);case CoreEvent_IdentityUpgrade() when identityUpgrade != null:
return identityUpgrade(_that);case CoreEvent_IdentityUpgraded() when identityUpgraded != null:
return identityUpgraded(_that);case CoreEvent_TransferStarted() when transferStarted != null:
return transferStarted(_that);case CoreEvent_TransferProgress() when transferProgress != null:
return transferProgress(_that);case CoreEvent_TransferFinished() when transferFinished != null:
return transferFinished(_that);case CoreEvent_Log() when log != null:
return log(_that);case CoreEvent_Denied() when denied != null:
return denied(_that);case CoreEvent_Failed() when failed != null:
return failed(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( CoreEvent_State value)  state,required TResult Function( CoreEvent_Servers value)  servers,required TResult Function( CoreEvent_Snapshot value)  snapshot,required TResult Function( CoreEvent_History value)  history,required TResult Function( CoreEvent_TextMessage value)  textMessage,required TResult Function( CoreEvent_ClientJoined value)  clientJoined,required TResult Function( CoreEvent_ClientLeft value)  clientLeft,required TResult Function( CoreEvent_ClientMoved value)  clientMoved,required TResult Function( CoreEvent_ClientUpdated value)  clientUpdated,required TResult Function( CoreEvent_Voice value)  voice,required TResult Function( CoreEvent_Speaking value)  speaking,required TResult Function( CoreEvent_SelfSpeaking value)  selfSpeaking,required TResult Function( CoreEvent_IdentityUpgrade value)  identityUpgrade,required TResult Function( CoreEvent_IdentityUpgraded value)  identityUpgraded,required TResult Function( CoreEvent_TransferStarted value)  transferStarted,required TResult Function( CoreEvent_TransferProgress value)  transferProgress,required TResult Function( CoreEvent_TransferFinished value)  transferFinished,required TResult Function( CoreEvent_Log value)  log,required TResult Function( CoreEvent_Denied value)  denied,required TResult Function( CoreEvent_Failed value)  failed,}){
final _that = this;
switch (_that) {
case CoreEvent_State():
return state(_that);case CoreEvent_Servers():
return servers(_that);case CoreEvent_Snapshot():
return snapshot(_that);case CoreEvent_History():
return history(_that);case CoreEvent_TextMessage():
return textMessage(_that);case CoreEvent_ClientJoined():
return clientJoined(_that);case CoreEvent_ClientLeft():
return clientLeft(_that);case CoreEvent_ClientMoved():
return clientMoved(_that);case CoreEvent_ClientUpdated():
return clientUpdated(_that);case CoreEvent_Voice():
return voice(_that);case CoreEvent_Speaking():
return speaking(_that);case CoreEvent_SelfSpeaking():
return selfSpeaking(_that);case CoreEvent_IdentityUpgrade():
return identityUpgrade(_that);case CoreEvent_IdentityUpgraded():
return identityUpgraded(_that);case CoreEvent_TransferStarted():
return transferStarted(_that);case CoreEvent_TransferProgress():
return transferProgress(_that);case CoreEvent_TransferFinished():
return transferFinished(_that);case CoreEvent_Log():
return log(_that);case CoreEvent_Denied():
return denied(_that);case CoreEvent_Failed():
return failed(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( CoreEvent_State value)?  state,TResult? Function( CoreEvent_Servers value)?  servers,TResult? Function( CoreEvent_Snapshot value)?  snapshot,TResult? Function( CoreEvent_History value)?  history,TResult? Function( CoreEvent_TextMessage value)?  textMessage,TResult? Function( CoreEvent_ClientJoined value)?  clientJoined,TResult? Function( CoreEvent_ClientLeft value)?  clientLeft,TResult? Function( CoreEvent_ClientMoved value)?  clientMoved,TResult? Function( CoreEvent_ClientUpdated value)?  clientUpdated,TResult? Function( CoreEvent_Voice value)?  voice,TResult? Function( CoreEvent_Speaking value)?  speaking,TResult? Function( CoreEvent_SelfSpeaking value)?  selfSpeaking,TResult? Function( CoreEvent_IdentityUpgrade value)?  identityUpgrade,TResult? Function( CoreEvent_IdentityUpgraded value)?  identityUpgraded,TResult? Function( CoreEvent_TransferStarted value)?  transferStarted,TResult? Function( CoreEvent_TransferProgress value)?  transferProgress,TResult? Function( CoreEvent_TransferFinished value)?  transferFinished,TResult? Function( CoreEvent_Log value)?  log,TResult? Function( CoreEvent_Denied value)?  denied,TResult? Function( CoreEvent_Failed value)?  failed,}){
final _that = this;
switch (_that) {
case CoreEvent_State() when state != null:
return state(_that);case CoreEvent_Servers() when servers != null:
return servers(_that);case CoreEvent_Snapshot() when snapshot != null:
return snapshot(_that);case CoreEvent_History() when history != null:
return history(_that);case CoreEvent_TextMessage() when textMessage != null:
return textMessage(_that);case CoreEvent_ClientJoined() when clientJoined != null:
return clientJoined(_that);case CoreEvent_ClientLeft() when clientLeft != null:
return clientLeft(_that);case CoreEvent_ClientMoved() when clientMoved != null:
return clientMoved(_that);case CoreEvent_ClientUpdated() when clientUpdated != null:
return clientUpdated(_that);case CoreEvent_Voice() when voice != null:
return voice(_that);case CoreEvent_Speaking() when speaking != null:
return speaking(_that);case CoreEvent_SelfSpeaking() when selfSpeaking != null:
return selfSpeaking(_that);case CoreEvent_IdentityUpgrade() when identityUpgrade != null:
return identityUpgrade(_that);case CoreEvent_IdentityUpgraded() when identityUpgraded != null:
return identityUpgraded(_that);case CoreEvent_TransferStarted() when transferStarted != null:
return transferStarted(_that);case CoreEvent_TransferProgress() when transferProgress != null:
return transferProgress(_that);case CoreEvent_TransferFinished() when transferFinished != null:
return transferFinished(_that);case CoreEvent_Log() when log != null:
return log(_that);case CoreEvent_Denied() when denied != null:
return denied(_that);case CoreEvent_Failed() when failed != null:
return failed(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( CoreSessionState state)?  state,TResult Function( List<ServerProfileView> profiles)?  servers,TResult Function( List<ChannelView> channels,  List<ClientView> clients)?  snapshot,TResult Function( List<CoreMessage> messages)?  history,TResult Function( String from,  String fromUid,  String message,  int targetMode,  int targetId,  int at)?  textMessage,TResult Function( int id,  String nickname,  String uid,  int channelId)?  clientJoined,TResult Function( int id)?  clientLeft,TResult Function( int id,  int channelId)?  clientMoved,TResult Function( int id,  bool? inputMuted,  bool? outputMuted)?  clientUpdated,TResult Function( CoreVoiceState state)?  voice,TResult Function( Int32List clientIds)?  speaking,TResult Function( bool speaking)?  selfSpeaking,TResult Function( int from,  int to)?  identityUpgrade,TResult Function( int level)?  identityUpgraded,TResult Function( int id,  CoreTransferDirection direction,  String remotePath,  int total)?  transferStarted,TResult Function( int id,  int transferred,  int total)?  transferProgress,TResult Function( int id,  String? error)?  transferFinished,TResult Function( String level,  String message)?  log,TResult Function( String message)?  denied,TResult Function( String message)?  failed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case CoreEvent_State() when state != null:
return state(_that.state);case CoreEvent_Servers() when servers != null:
return servers(_that.profiles);case CoreEvent_Snapshot() when snapshot != null:
return snapshot(_that.channels,_that.clients);case CoreEvent_History() when history != null:
return history(_that.messages);case CoreEvent_TextMessage() when textMessage != null:
return textMessage(_that.from,_that.fromUid,_that.message,_that.targetMode,_that.targetId,_that.at);case CoreEvent_ClientJoined() when clientJoined != null:
return clientJoined(_that.id,_that.nickname,_that.uid,_that.channelId);case CoreEvent_ClientLeft() when clientLeft != null:
return clientLeft(_that.id);case CoreEvent_ClientMoved() when clientMoved != null:
return clientMoved(_that.id,_that.channelId);case CoreEvent_ClientUpdated() when clientUpdated != null:
return clientUpdated(_that.id,_that.inputMuted,_that.outputMuted);case CoreEvent_Voice() when voice != null:
return voice(_that.state);case CoreEvent_Speaking() when speaking != null:
return speaking(_that.clientIds);case CoreEvent_SelfSpeaking() when selfSpeaking != null:
return selfSpeaking(_that.speaking);case CoreEvent_IdentityUpgrade() when identityUpgrade != null:
return identityUpgrade(_that.from,_that.to);case CoreEvent_IdentityUpgraded() when identityUpgraded != null:
return identityUpgraded(_that.level);case CoreEvent_TransferStarted() when transferStarted != null:
return transferStarted(_that.id,_that.direction,_that.remotePath,_that.total);case CoreEvent_TransferProgress() when transferProgress != null:
return transferProgress(_that.id,_that.transferred,_that.total);case CoreEvent_TransferFinished() when transferFinished != null:
return transferFinished(_that.id,_that.error);case CoreEvent_Log() when log != null:
return log(_that.level,_that.message);case CoreEvent_Denied() when denied != null:
return denied(_that.message);case CoreEvent_Failed() when failed != null:
return failed(_that.message);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( CoreSessionState state)  state,required TResult Function( List<ServerProfileView> profiles)  servers,required TResult Function( List<ChannelView> channels,  List<ClientView> clients)  snapshot,required TResult Function( List<CoreMessage> messages)  history,required TResult Function( String from,  String fromUid,  String message,  int targetMode,  int targetId,  int at)  textMessage,required TResult Function( int id,  String nickname,  String uid,  int channelId)  clientJoined,required TResult Function( int id)  clientLeft,required TResult Function( int id,  int channelId)  clientMoved,required TResult Function( int id,  bool? inputMuted,  bool? outputMuted)  clientUpdated,required TResult Function( CoreVoiceState state)  voice,required TResult Function( Int32List clientIds)  speaking,required TResult Function( bool speaking)  selfSpeaking,required TResult Function( int from,  int to)  identityUpgrade,required TResult Function( int level)  identityUpgraded,required TResult Function( int id,  CoreTransferDirection direction,  String remotePath,  int total)  transferStarted,required TResult Function( int id,  int transferred,  int total)  transferProgress,required TResult Function( int id,  String? error)  transferFinished,required TResult Function( String level,  String message)  log,required TResult Function( String message)  denied,required TResult Function( String message)  failed,}) {final _that = this;
switch (_that) {
case CoreEvent_State():
return state(_that.state);case CoreEvent_Servers():
return servers(_that.profiles);case CoreEvent_Snapshot():
return snapshot(_that.channels,_that.clients);case CoreEvent_History():
return history(_that.messages);case CoreEvent_TextMessage():
return textMessage(_that.from,_that.fromUid,_that.message,_that.targetMode,_that.targetId,_that.at);case CoreEvent_ClientJoined():
return clientJoined(_that.id,_that.nickname,_that.uid,_that.channelId);case CoreEvent_ClientLeft():
return clientLeft(_that.id);case CoreEvent_ClientMoved():
return clientMoved(_that.id,_that.channelId);case CoreEvent_ClientUpdated():
return clientUpdated(_that.id,_that.inputMuted,_that.outputMuted);case CoreEvent_Voice():
return voice(_that.state);case CoreEvent_Speaking():
return speaking(_that.clientIds);case CoreEvent_SelfSpeaking():
return selfSpeaking(_that.speaking);case CoreEvent_IdentityUpgrade():
return identityUpgrade(_that.from,_that.to);case CoreEvent_IdentityUpgraded():
return identityUpgraded(_that.level);case CoreEvent_TransferStarted():
return transferStarted(_that.id,_that.direction,_that.remotePath,_that.total);case CoreEvent_TransferProgress():
return transferProgress(_that.id,_that.transferred,_that.total);case CoreEvent_TransferFinished():
return transferFinished(_that.id,_that.error);case CoreEvent_Log():
return log(_that.level,_that.message);case CoreEvent_Denied():
return denied(_that.message);case CoreEvent_Failed():
return failed(_that.message);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( CoreSessionState state)?  state,TResult? Function( List<ServerProfileView> profiles)?  servers,TResult? Function( List<ChannelView> channels,  List<ClientView> clients)?  snapshot,TResult? Function( List<CoreMessage> messages)?  history,TResult? Function( String from,  String fromUid,  String message,  int targetMode,  int targetId,  int at)?  textMessage,TResult? Function( int id,  String nickname,  String uid,  int channelId)?  clientJoined,TResult? Function( int id)?  clientLeft,TResult? Function( int id,  int channelId)?  clientMoved,TResult? Function( int id,  bool? inputMuted,  bool? outputMuted)?  clientUpdated,TResult? Function( CoreVoiceState state)?  voice,TResult? Function( Int32List clientIds)?  speaking,TResult? Function( bool speaking)?  selfSpeaking,TResult? Function( int from,  int to)?  identityUpgrade,TResult? Function( int level)?  identityUpgraded,TResult? Function( int id,  CoreTransferDirection direction,  String remotePath,  int total)?  transferStarted,TResult? Function( int id,  int transferred,  int total)?  transferProgress,TResult? Function( int id,  String? error)?  transferFinished,TResult? Function( String level,  String message)?  log,TResult? Function( String message)?  denied,TResult? Function( String message)?  failed,}) {final _that = this;
switch (_that) {
case CoreEvent_State() when state != null:
return state(_that.state);case CoreEvent_Servers() when servers != null:
return servers(_that.profiles);case CoreEvent_Snapshot() when snapshot != null:
return snapshot(_that.channels,_that.clients);case CoreEvent_History() when history != null:
return history(_that.messages);case CoreEvent_TextMessage() when textMessage != null:
return textMessage(_that.from,_that.fromUid,_that.message,_that.targetMode,_that.targetId,_that.at);case CoreEvent_ClientJoined() when clientJoined != null:
return clientJoined(_that.id,_that.nickname,_that.uid,_that.channelId);case CoreEvent_ClientLeft() when clientLeft != null:
return clientLeft(_that.id);case CoreEvent_ClientMoved() when clientMoved != null:
return clientMoved(_that.id,_that.channelId);case CoreEvent_ClientUpdated() when clientUpdated != null:
return clientUpdated(_that.id,_that.inputMuted,_that.outputMuted);case CoreEvent_Voice() when voice != null:
return voice(_that.state);case CoreEvent_Speaking() when speaking != null:
return speaking(_that.clientIds);case CoreEvent_SelfSpeaking() when selfSpeaking != null:
return selfSpeaking(_that.speaking);case CoreEvent_IdentityUpgrade() when identityUpgrade != null:
return identityUpgrade(_that.from,_that.to);case CoreEvent_IdentityUpgraded() when identityUpgraded != null:
return identityUpgraded(_that.level);case CoreEvent_TransferStarted() when transferStarted != null:
return transferStarted(_that.id,_that.direction,_that.remotePath,_that.total);case CoreEvent_TransferProgress() when transferProgress != null:
return transferProgress(_that.id,_that.transferred,_that.total);case CoreEvent_TransferFinished() when transferFinished != null:
return transferFinished(_that.id,_that.error);case CoreEvent_Log() when log != null:
return log(_that.level,_that.message);case CoreEvent_Denied() when denied != null:
return denied(_that.message);case CoreEvent_Failed() when failed != null:
return failed(_that.message);case _:
  return null;

}
}

}

/// @nodoc


class CoreEvent_State extends CoreEvent {
  const CoreEvent_State({required this.state}): super._();
  

 final  CoreSessionState state;

/// Create a copy of CoreEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CoreEvent_StateCopyWith<CoreEvent_State> get copyWith => _$CoreEvent_StateCopyWithImpl<CoreEvent_State>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CoreEvent_State&&(identical(other.state, state) || other.state == state));
}


@override
int get hashCode {
    return Object.hash(runtimeType,state);
}

@override
String toString() {
    return 'CoreEvent.state(state: $state)';
}


}

/// @nodoc
abstract mixin class $CoreEvent_StateCopyWith<$Res> implements $CoreEventCopyWith<$Res> {
  factory $CoreEvent_StateCopyWith(CoreEvent_State value, $Res Function(CoreEvent_State) _then) = _$CoreEvent_StateCopyWithImpl;
@useResult
$Res call({
 CoreSessionState state
});


$CoreSessionStateCopyWith<$Res> get state;

}
/// @nodoc
class _$CoreEvent_StateCopyWithImpl<$Res>
    implements $CoreEvent_StateCopyWith<$Res> {
  _$CoreEvent_StateCopyWithImpl(this._self, this._then);

  final CoreEvent_State _self;
  final $Res Function(CoreEvent_State) _then;

/// Create a copy of CoreEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? state = null,}) {
  return _then(CoreEvent_State(
state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as CoreSessionState,
  ));
}

/// Create a copy of CoreEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$CoreSessionStateCopyWith<$Res> get state {
  
  return $CoreSessionStateCopyWith<$Res>(_self.state, (value) {
    return _then(_self.copyWith(state: value));
  });
}
}

/// @nodoc


class CoreEvent_Servers extends CoreEvent {
  const CoreEvent_Servers({required  List<ServerProfileView> profiles}): _profiles = profiles,super._();
  

 final  List<ServerProfileView> _profiles;
 List<ServerProfileView> get profiles {
  if (_profiles is EqualUnmodifiableListView) return _profiles;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_profiles);
}


/// Create a copy of CoreEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CoreEvent_ServersCopyWith<CoreEvent_Servers> get copyWith => _$CoreEvent_ServersCopyWithImpl<CoreEvent_Servers>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CoreEvent_Servers&&const DeepCollectionEquality().equals(other.profiles, _profiles));
}


@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(_profiles));
}

@override
String toString() {
    return 'CoreEvent.servers(profiles: $profiles)';
}


}

/// @nodoc
abstract mixin class $CoreEvent_ServersCopyWith<$Res> implements $CoreEventCopyWith<$Res> {
  factory $CoreEvent_ServersCopyWith(CoreEvent_Servers value, $Res Function(CoreEvent_Servers) _then) = _$CoreEvent_ServersCopyWithImpl;
@useResult
$Res call({
 List<ServerProfileView> profiles
});




}
/// @nodoc
class _$CoreEvent_ServersCopyWithImpl<$Res>
    implements $CoreEvent_ServersCopyWith<$Res> {
  _$CoreEvent_ServersCopyWithImpl(this._self, this._then);

  final CoreEvent_Servers _self;
  final $Res Function(CoreEvent_Servers) _then;

/// Create a copy of CoreEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? profiles = null,}) {
  return _then(CoreEvent_Servers(
profiles: null == profiles ? _self._profiles : profiles // ignore: cast_nullable_to_non_nullable
as List<ServerProfileView>,
  ));
}


}

/// @nodoc


class CoreEvent_Snapshot extends CoreEvent {
  const CoreEvent_Snapshot({required  List<ChannelView> channels, required  List<ClientView> clients}): _channels = channels,_clients = clients,super._();
  

 final  List<ChannelView> _channels;
 List<ChannelView> get channels {
  if (_channels is EqualUnmodifiableListView) return _channels;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_channels);
}

 final  List<ClientView> _clients;
 List<ClientView> get clients {
  if (_clients is EqualUnmodifiableListView) return _clients;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_clients);
}


/// Create a copy of CoreEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CoreEvent_SnapshotCopyWith<CoreEvent_Snapshot> get copyWith => _$CoreEvent_SnapshotCopyWithImpl<CoreEvent_Snapshot>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CoreEvent_Snapshot&&const DeepCollectionEquality().equals(other.channels, _channels)&&const DeepCollectionEquality().equals(other.clients, _clients));
}


@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(_channels),const DeepCollectionEquality().hash(_clients));
}

@override
String toString() {
    return 'CoreEvent.snapshot(channels: $channels, clients: $clients)';
}


}

/// @nodoc
abstract mixin class $CoreEvent_SnapshotCopyWith<$Res> implements $CoreEventCopyWith<$Res> {
  factory $CoreEvent_SnapshotCopyWith(CoreEvent_Snapshot value, $Res Function(CoreEvent_Snapshot) _then) = _$CoreEvent_SnapshotCopyWithImpl;
@useResult
$Res call({
 List<ChannelView> channels, List<ClientView> clients
});




}
/// @nodoc
class _$CoreEvent_SnapshotCopyWithImpl<$Res>
    implements $CoreEvent_SnapshotCopyWith<$Res> {
  _$CoreEvent_SnapshotCopyWithImpl(this._self, this._then);

  final CoreEvent_Snapshot _self;
  final $Res Function(CoreEvent_Snapshot) _then;

/// Create a copy of CoreEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? channels = null,Object? clients = null,}) {
  return _then(CoreEvent_Snapshot(
channels: null == channels ? _self._channels : channels // ignore: cast_nullable_to_non_nullable
as List<ChannelView>,clients: null == clients ? _self._clients : clients // ignore: cast_nullable_to_non_nullable
as List<ClientView>,
  ));
}


}

/// @nodoc


class CoreEvent_History extends CoreEvent {
  const CoreEvent_History({required  List<CoreMessage> messages}): _messages = messages,super._();
  

 final  List<CoreMessage> _messages;
 List<CoreMessage> get messages {
  if (_messages is EqualUnmodifiableListView) return _messages;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_messages);
}


/// Create a copy of CoreEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CoreEvent_HistoryCopyWith<CoreEvent_History> get copyWith => _$CoreEvent_HistoryCopyWithImpl<CoreEvent_History>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CoreEvent_History&&const DeepCollectionEquality().equals(other.messages, _messages));
}


@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(_messages));
}

@override
String toString() {
    return 'CoreEvent.history(messages: $messages)';
}


}

/// @nodoc
abstract mixin class $CoreEvent_HistoryCopyWith<$Res> implements $CoreEventCopyWith<$Res> {
  factory $CoreEvent_HistoryCopyWith(CoreEvent_History value, $Res Function(CoreEvent_History) _then) = _$CoreEvent_HistoryCopyWithImpl;
@useResult
$Res call({
 List<CoreMessage> messages
});




}
/// @nodoc
class _$CoreEvent_HistoryCopyWithImpl<$Res>
    implements $CoreEvent_HistoryCopyWith<$Res> {
  _$CoreEvent_HistoryCopyWithImpl(this._self, this._then);

  final CoreEvent_History _self;
  final $Res Function(CoreEvent_History) _then;

/// Create a copy of CoreEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? messages = null,}) {
  return _then(CoreEvent_History(
messages: null == messages ? _self._messages : messages // ignore: cast_nullable_to_non_nullable
as List<CoreMessage>,
  ));
}


}

/// @nodoc


class CoreEvent_TextMessage extends CoreEvent {
  const CoreEvent_TextMessage({required this.from, required this.fromUid, required this.message, required this.targetMode, required this.targetId, required this.at}): super._();
  

 final  String from;
 final  String fromUid;
 final  String message;
 final  int targetMode;
 final  int targetId;
 final  int at;

/// Create a copy of CoreEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CoreEvent_TextMessageCopyWith<CoreEvent_TextMessage> get copyWith => _$CoreEvent_TextMessageCopyWithImpl<CoreEvent_TextMessage>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CoreEvent_TextMessage&&(identical(other.from, from) || other.from == from)&&(identical(other.fromUid, fromUid) || other.fromUid == fromUid)&&(identical(other.message, message) || other.message == message)&&(identical(other.targetMode, targetMode) || other.targetMode == targetMode)&&(identical(other.targetId, targetId) || other.targetId == targetId)&&(identical(other.at, at) || other.at == at));
}


@override
int get hashCode {
    return Object.hash(runtimeType,from,fromUid,message,targetMode,targetId,at);
}

@override
String toString() {
    return 'CoreEvent.textMessage(from: $from, fromUid: $fromUid, message: $message, targetMode: $targetMode, targetId: $targetId, at: $at)';
}


}

/// @nodoc
abstract mixin class $CoreEvent_TextMessageCopyWith<$Res> implements $CoreEventCopyWith<$Res> {
  factory $CoreEvent_TextMessageCopyWith(CoreEvent_TextMessage value, $Res Function(CoreEvent_TextMessage) _then) = _$CoreEvent_TextMessageCopyWithImpl;
@useResult
$Res call({
 String from, String fromUid, String message, int targetMode, int targetId, int at
});




}
/// @nodoc
class _$CoreEvent_TextMessageCopyWithImpl<$Res>
    implements $CoreEvent_TextMessageCopyWith<$Res> {
  _$CoreEvent_TextMessageCopyWithImpl(this._self, this._then);

  final CoreEvent_TextMessage _self;
  final $Res Function(CoreEvent_TextMessage) _then;

/// Create a copy of CoreEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? from = null,Object? fromUid = null,Object? message = null,Object? targetMode = null,Object? targetId = null,Object? at = null,}) {
  return _then(CoreEvent_TextMessage(
from: null == from ? _self.from : from // ignore: cast_nullable_to_non_nullable
as String,fromUid: null == fromUid ? _self.fromUid : fromUid // ignore: cast_nullable_to_non_nullable
as String,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,targetMode: null == targetMode ? _self.targetMode : targetMode // ignore: cast_nullable_to_non_nullable
as int,targetId: null == targetId ? _self.targetId : targetId // ignore: cast_nullable_to_non_nullable
as int,at: null == at ? _self.at : at // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class CoreEvent_ClientJoined extends CoreEvent {
  const CoreEvent_ClientJoined({required this.id, required this.nickname, required this.uid, required this.channelId}): super._();
  

 final  int id;
 final  String nickname;
 final  String uid;
 final  int channelId;

/// Create a copy of CoreEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CoreEvent_ClientJoinedCopyWith<CoreEvent_ClientJoined> get copyWith => _$CoreEvent_ClientJoinedCopyWithImpl<CoreEvent_ClientJoined>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CoreEvent_ClientJoined&&(identical(other.id, id) || other.id == id)&&(identical(other.nickname, nickname) || other.nickname == nickname)&&(identical(other.uid, uid) || other.uid == uid)&&(identical(other.channelId, channelId) || other.channelId == channelId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,nickname,uid,channelId);
}

@override
String toString() {
    return 'CoreEvent.clientJoined(id: $id, nickname: $nickname, uid: $uid, channelId: $channelId)';
}


}

/// @nodoc
abstract mixin class $CoreEvent_ClientJoinedCopyWith<$Res> implements $CoreEventCopyWith<$Res> {
  factory $CoreEvent_ClientJoinedCopyWith(CoreEvent_ClientJoined value, $Res Function(CoreEvent_ClientJoined) _then) = _$CoreEvent_ClientJoinedCopyWithImpl;
@useResult
$Res call({
 int id, String nickname, String uid, int channelId
});




}
/// @nodoc
class _$CoreEvent_ClientJoinedCopyWithImpl<$Res>
    implements $CoreEvent_ClientJoinedCopyWith<$Res> {
  _$CoreEvent_ClientJoinedCopyWithImpl(this._self, this._then);

  final CoreEvent_ClientJoined _self;
  final $Res Function(CoreEvent_ClientJoined) _then;

/// Create a copy of CoreEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? id = null,Object? nickname = null,Object? uid = null,Object? channelId = null,}) {
  return _then(CoreEvent_ClientJoined(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,nickname: null == nickname ? _self.nickname : nickname // ignore: cast_nullable_to_non_nullable
as String,uid: null == uid ? _self.uid : uid // ignore: cast_nullable_to_non_nullable
as String,channelId: null == channelId ? _self.channelId : channelId // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class CoreEvent_ClientLeft extends CoreEvent {
  const CoreEvent_ClientLeft({required this.id}): super._();
  

 final  int id;

/// Create a copy of CoreEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CoreEvent_ClientLeftCopyWith<CoreEvent_ClientLeft> get copyWith => _$CoreEvent_ClientLeftCopyWithImpl<CoreEvent_ClientLeft>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CoreEvent_ClientLeft&&(identical(other.id, id) || other.id == id));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id);
}

@override
String toString() {
    return 'CoreEvent.clientLeft(id: $id)';
}


}

/// @nodoc
abstract mixin class $CoreEvent_ClientLeftCopyWith<$Res> implements $CoreEventCopyWith<$Res> {
  factory $CoreEvent_ClientLeftCopyWith(CoreEvent_ClientLeft value, $Res Function(CoreEvent_ClientLeft) _then) = _$CoreEvent_ClientLeftCopyWithImpl;
@useResult
$Res call({
 int id
});




}
/// @nodoc
class _$CoreEvent_ClientLeftCopyWithImpl<$Res>
    implements $CoreEvent_ClientLeftCopyWith<$Res> {
  _$CoreEvent_ClientLeftCopyWithImpl(this._self, this._then);

  final CoreEvent_ClientLeft _self;
  final $Res Function(CoreEvent_ClientLeft) _then;

/// Create a copy of CoreEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? id = null,}) {
  return _then(CoreEvent_ClientLeft(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class CoreEvent_ClientMoved extends CoreEvent {
  const CoreEvent_ClientMoved({required this.id, required this.channelId}): super._();
  

 final  int id;
 final  int channelId;

/// Create a copy of CoreEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CoreEvent_ClientMovedCopyWith<CoreEvent_ClientMoved> get copyWith => _$CoreEvent_ClientMovedCopyWithImpl<CoreEvent_ClientMoved>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CoreEvent_ClientMoved&&(identical(other.id, id) || other.id == id)&&(identical(other.channelId, channelId) || other.channelId == channelId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,channelId);
}

@override
String toString() {
    return 'CoreEvent.clientMoved(id: $id, channelId: $channelId)';
}


}

/// @nodoc
abstract mixin class $CoreEvent_ClientMovedCopyWith<$Res> implements $CoreEventCopyWith<$Res> {
  factory $CoreEvent_ClientMovedCopyWith(CoreEvent_ClientMoved value, $Res Function(CoreEvent_ClientMoved) _then) = _$CoreEvent_ClientMovedCopyWithImpl;
@useResult
$Res call({
 int id, int channelId
});




}
/// @nodoc
class _$CoreEvent_ClientMovedCopyWithImpl<$Res>
    implements $CoreEvent_ClientMovedCopyWith<$Res> {
  _$CoreEvent_ClientMovedCopyWithImpl(this._self, this._then);

  final CoreEvent_ClientMoved _self;
  final $Res Function(CoreEvent_ClientMoved) _then;

/// Create a copy of CoreEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? id = null,Object? channelId = null,}) {
  return _then(CoreEvent_ClientMoved(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,channelId: null == channelId ? _self.channelId : channelId // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class CoreEvent_ClientUpdated extends CoreEvent {
  const CoreEvent_ClientUpdated({required this.id, this.inputMuted, this.outputMuted}): super._();
  

 final  int id;
 final  bool? inputMuted;
 final  bool? outputMuted;

/// Create a copy of CoreEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CoreEvent_ClientUpdatedCopyWith<CoreEvent_ClientUpdated> get copyWith => _$CoreEvent_ClientUpdatedCopyWithImpl<CoreEvent_ClientUpdated>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CoreEvent_ClientUpdated&&(identical(other.id, id) || other.id == id)&&(identical(other.inputMuted, inputMuted) || other.inputMuted == inputMuted)&&(identical(other.outputMuted, outputMuted) || other.outputMuted == outputMuted));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,inputMuted,outputMuted);
}

@override
String toString() {
    return 'CoreEvent.clientUpdated(id: $id, inputMuted: $inputMuted, outputMuted: $outputMuted)';
}


}

/// @nodoc
abstract mixin class $CoreEvent_ClientUpdatedCopyWith<$Res> implements $CoreEventCopyWith<$Res> {
  factory $CoreEvent_ClientUpdatedCopyWith(CoreEvent_ClientUpdated value, $Res Function(CoreEvent_ClientUpdated) _then) = _$CoreEvent_ClientUpdatedCopyWithImpl;
@useResult
$Res call({
 int id, bool? inputMuted, bool? outputMuted
});




}
/// @nodoc
class _$CoreEvent_ClientUpdatedCopyWithImpl<$Res>
    implements $CoreEvent_ClientUpdatedCopyWith<$Res> {
  _$CoreEvent_ClientUpdatedCopyWithImpl(this._self, this._then);

  final CoreEvent_ClientUpdated _self;
  final $Res Function(CoreEvent_ClientUpdated) _then;

/// Create a copy of CoreEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? id = null,Object? inputMuted = freezed,Object? outputMuted = freezed,}) {
  return _then(CoreEvent_ClientUpdated(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,inputMuted: freezed == inputMuted ? _self.inputMuted : inputMuted // ignore: cast_nullable_to_non_nullable
as bool?,outputMuted: freezed == outputMuted ? _self.outputMuted : outputMuted // ignore: cast_nullable_to_non_nullable
as bool?,
  ));
}


}

/// @nodoc


class CoreEvent_Voice extends CoreEvent {
  const CoreEvent_Voice({required this.state}): super._();
  

 final  CoreVoiceState state;

/// Create a copy of CoreEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CoreEvent_VoiceCopyWith<CoreEvent_Voice> get copyWith => _$CoreEvent_VoiceCopyWithImpl<CoreEvent_Voice>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CoreEvent_Voice&&(identical(other.state, state) || other.state == state));
}


@override
int get hashCode {
    return Object.hash(runtimeType,state);
}

@override
String toString() {
    return 'CoreEvent.voice(state: $state)';
}


}

/// @nodoc
abstract mixin class $CoreEvent_VoiceCopyWith<$Res> implements $CoreEventCopyWith<$Res> {
  factory $CoreEvent_VoiceCopyWith(CoreEvent_Voice value, $Res Function(CoreEvent_Voice) _then) = _$CoreEvent_VoiceCopyWithImpl;
@useResult
$Res call({
 CoreVoiceState state
});




}
/// @nodoc
class _$CoreEvent_VoiceCopyWithImpl<$Res>
    implements $CoreEvent_VoiceCopyWith<$Res> {
  _$CoreEvent_VoiceCopyWithImpl(this._self, this._then);

  final CoreEvent_Voice _self;
  final $Res Function(CoreEvent_Voice) _then;

/// Create a copy of CoreEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? state = null,}) {
  return _then(CoreEvent_Voice(
state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as CoreVoiceState,
  ));
}


}

/// @nodoc


class CoreEvent_Speaking extends CoreEvent {
  const CoreEvent_Speaking({required this.clientIds}): super._();
  

 final  Int32List clientIds;

/// Create a copy of CoreEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CoreEvent_SpeakingCopyWith<CoreEvent_Speaking> get copyWith => _$CoreEvent_SpeakingCopyWithImpl<CoreEvent_Speaking>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CoreEvent_Speaking&&const DeepCollectionEquality().equals(other.clientIds, clientIds));
}


@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(clientIds));
}

@override
String toString() {
    return 'CoreEvent.speaking(clientIds: $clientIds)';
}


}

/// @nodoc
abstract mixin class $CoreEvent_SpeakingCopyWith<$Res> implements $CoreEventCopyWith<$Res> {
  factory $CoreEvent_SpeakingCopyWith(CoreEvent_Speaking value, $Res Function(CoreEvent_Speaking) _then) = _$CoreEvent_SpeakingCopyWithImpl;
@useResult
$Res call({
 Int32List clientIds
});




}
/// @nodoc
class _$CoreEvent_SpeakingCopyWithImpl<$Res>
    implements $CoreEvent_SpeakingCopyWith<$Res> {
  _$CoreEvent_SpeakingCopyWithImpl(this._self, this._then);

  final CoreEvent_Speaking _self;
  final $Res Function(CoreEvent_Speaking) _then;

/// Create a copy of CoreEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? clientIds = null,}) {
  return _then(CoreEvent_Speaking(
clientIds: null == clientIds ? _self.clientIds : clientIds // ignore: cast_nullable_to_non_nullable
as Int32List,
  ));
}


}

/// @nodoc


class CoreEvent_SelfSpeaking extends CoreEvent {
  const CoreEvent_SelfSpeaking({required this.speaking}): super._();
  

 final  bool speaking;

/// Create a copy of CoreEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CoreEvent_SelfSpeakingCopyWith<CoreEvent_SelfSpeaking> get copyWith => _$CoreEvent_SelfSpeakingCopyWithImpl<CoreEvent_SelfSpeaking>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CoreEvent_SelfSpeaking&&(identical(other.speaking, speaking) || other.speaking == speaking));
}


@override
int get hashCode {
    return Object.hash(runtimeType,speaking);
}

@override
String toString() {
    return 'CoreEvent.selfSpeaking(speaking: $speaking)';
}


}

/// @nodoc
abstract mixin class $CoreEvent_SelfSpeakingCopyWith<$Res> implements $CoreEventCopyWith<$Res> {
  factory $CoreEvent_SelfSpeakingCopyWith(CoreEvent_SelfSpeaking value, $Res Function(CoreEvent_SelfSpeaking) _then) = _$CoreEvent_SelfSpeakingCopyWithImpl;
@useResult
$Res call({
 bool speaking
});




}
/// @nodoc
class _$CoreEvent_SelfSpeakingCopyWithImpl<$Res>
    implements $CoreEvent_SelfSpeakingCopyWith<$Res> {
  _$CoreEvent_SelfSpeakingCopyWithImpl(this._self, this._then);

  final CoreEvent_SelfSpeaking _self;
  final $Res Function(CoreEvent_SelfSpeaking) _then;

/// Create a copy of CoreEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? speaking = null,}) {
  return _then(CoreEvent_SelfSpeaking(
speaking: null == speaking ? _self.speaking : speaking // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc


class CoreEvent_IdentityUpgrade extends CoreEvent {
  const CoreEvent_IdentityUpgrade({required this.from, required this.to}): super._();
  

 final  int from;
 final  int to;

/// Create a copy of CoreEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CoreEvent_IdentityUpgradeCopyWith<CoreEvent_IdentityUpgrade> get copyWith => _$CoreEvent_IdentityUpgradeCopyWithImpl<CoreEvent_IdentityUpgrade>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CoreEvent_IdentityUpgrade&&(identical(other.from, from) || other.from == from)&&(identical(other.to, to) || other.to == to));
}


@override
int get hashCode {
    return Object.hash(runtimeType,from,to);
}

@override
String toString() {
    return 'CoreEvent.identityUpgrade(from: $from, to: $to)';
}


}

/// @nodoc
abstract mixin class $CoreEvent_IdentityUpgradeCopyWith<$Res> implements $CoreEventCopyWith<$Res> {
  factory $CoreEvent_IdentityUpgradeCopyWith(CoreEvent_IdentityUpgrade value, $Res Function(CoreEvent_IdentityUpgrade) _then) = _$CoreEvent_IdentityUpgradeCopyWithImpl;
@useResult
$Res call({
 int from, int to
});




}
/// @nodoc
class _$CoreEvent_IdentityUpgradeCopyWithImpl<$Res>
    implements $CoreEvent_IdentityUpgradeCopyWith<$Res> {
  _$CoreEvent_IdentityUpgradeCopyWithImpl(this._self, this._then);

  final CoreEvent_IdentityUpgrade _self;
  final $Res Function(CoreEvent_IdentityUpgrade) _then;

/// Create a copy of CoreEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? from = null,Object? to = null,}) {
  return _then(CoreEvent_IdentityUpgrade(
from: null == from ? _self.from : from // ignore: cast_nullable_to_non_nullable
as int,to: null == to ? _self.to : to // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class CoreEvent_IdentityUpgraded extends CoreEvent {
  const CoreEvent_IdentityUpgraded({required this.level}): super._();
  

 final  int level;

/// Create a copy of CoreEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CoreEvent_IdentityUpgradedCopyWith<CoreEvent_IdentityUpgraded> get copyWith => _$CoreEvent_IdentityUpgradedCopyWithImpl<CoreEvent_IdentityUpgraded>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CoreEvent_IdentityUpgraded&&(identical(other.level, level) || other.level == level));
}


@override
int get hashCode {
    return Object.hash(runtimeType,level);
}

@override
String toString() {
    return 'CoreEvent.identityUpgraded(level: $level)';
}


}

/// @nodoc
abstract mixin class $CoreEvent_IdentityUpgradedCopyWith<$Res> implements $CoreEventCopyWith<$Res> {
  factory $CoreEvent_IdentityUpgradedCopyWith(CoreEvent_IdentityUpgraded value, $Res Function(CoreEvent_IdentityUpgraded) _then) = _$CoreEvent_IdentityUpgradedCopyWithImpl;
@useResult
$Res call({
 int level
});




}
/// @nodoc
class _$CoreEvent_IdentityUpgradedCopyWithImpl<$Res>
    implements $CoreEvent_IdentityUpgradedCopyWith<$Res> {
  _$CoreEvent_IdentityUpgradedCopyWithImpl(this._self, this._then);

  final CoreEvent_IdentityUpgraded _self;
  final $Res Function(CoreEvent_IdentityUpgraded) _then;

/// Create a copy of CoreEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? level = null,}) {
  return _then(CoreEvent_IdentityUpgraded(
level: null == level ? _self.level : level // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class CoreEvent_TransferStarted extends CoreEvent {
  const CoreEvent_TransferStarted({required this.id, required this.direction, required this.remotePath, required this.total}): super._();
  

 final  int id;
 final  CoreTransferDirection direction;
 final  String remotePath;
 final  int total;

/// Create a copy of CoreEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CoreEvent_TransferStartedCopyWith<CoreEvent_TransferStarted> get copyWith => _$CoreEvent_TransferStartedCopyWithImpl<CoreEvent_TransferStarted>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CoreEvent_TransferStarted&&(identical(other.id, id) || other.id == id)&&(identical(other.direction, direction) || other.direction == direction)&&(identical(other.remotePath, remotePath) || other.remotePath == remotePath)&&(identical(other.total, total) || other.total == total));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,direction,remotePath,total);
}

@override
String toString() {
    return 'CoreEvent.transferStarted(id: $id, direction: $direction, remotePath: $remotePath, total: $total)';
}


}

/// @nodoc
abstract mixin class $CoreEvent_TransferStartedCopyWith<$Res> implements $CoreEventCopyWith<$Res> {
  factory $CoreEvent_TransferStartedCopyWith(CoreEvent_TransferStarted value, $Res Function(CoreEvent_TransferStarted) _then) = _$CoreEvent_TransferStartedCopyWithImpl;
@useResult
$Res call({
 int id, CoreTransferDirection direction, String remotePath, int total
});




}
/// @nodoc
class _$CoreEvent_TransferStartedCopyWithImpl<$Res>
    implements $CoreEvent_TransferStartedCopyWith<$Res> {
  _$CoreEvent_TransferStartedCopyWithImpl(this._self, this._then);

  final CoreEvent_TransferStarted _self;
  final $Res Function(CoreEvent_TransferStarted) _then;

/// Create a copy of CoreEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? id = null,Object? direction = null,Object? remotePath = null,Object? total = null,}) {
  return _then(CoreEvent_TransferStarted(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,direction: null == direction ? _self.direction : direction // ignore: cast_nullable_to_non_nullable
as CoreTransferDirection,remotePath: null == remotePath ? _self.remotePath : remotePath // ignore: cast_nullable_to_non_nullable
as String,total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class CoreEvent_TransferProgress extends CoreEvent {
  const CoreEvent_TransferProgress({required this.id, required this.transferred, required this.total}): super._();
  

 final  int id;
 final  int transferred;
 final  int total;

/// Create a copy of CoreEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CoreEvent_TransferProgressCopyWith<CoreEvent_TransferProgress> get copyWith => _$CoreEvent_TransferProgressCopyWithImpl<CoreEvent_TransferProgress>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CoreEvent_TransferProgress&&(identical(other.id, id) || other.id == id)&&(identical(other.transferred, transferred) || other.transferred == transferred)&&(identical(other.total, total) || other.total == total));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,transferred,total);
}

@override
String toString() {
    return 'CoreEvent.transferProgress(id: $id, transferred: $transferred, total: $total)';
}


}

/// @nodoc
abstract mixin class $CoreEvent_TransferProgressCopyWith<$Res> implements $CoreEventCopyWith<$Res> {
  factory $CoreEvent_TransferProgressCopyWith(CoreEvent_TransferProgress value, $Res Function(CoreEvent_TransferProgress) _then) = _$CoreEvent_TransferProgressCopyWithImpl;
@useResult
$Res call({
 int id, int transferred, int total
});




}
/// @nodoc
class _$CoreEvent_TransferProgressCopyWithImpl<$Res>
    implements $CoreEvent_TransferProgressCopyWith<$Res> {
  _$CoreEvent_TransferProgressCopyWithImpl(this._self, this._then);

  final CoreEvent_TransferProgress _self;
  final $Res Function(CoreEvent_TransferProgress) _then;

/// Create a copy of CoreEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? id = null,Object? transferred = null,Object? total = null,}) {
  return _then(CoreEvent_TransferProgress(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,transferred: null == transferred ? _self.transferred : transferred // ignore: cast_nullable_to_non_nullable
as int,total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class CoreEvent_TransferFinished extends CoreEvent {
  const CoreEvent_TransferFinished({required this.id, this.error}): super._();
  

 final  int id;
 final  String? error;

/// Create a copy of CoreEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CoreEvent_TransferFinishedCopyWith<CoreEvent_TransferFinished> get copyWith => _$CoreEvent_TransferFinishedCopyWithImpl<CoreEvent_TransferFinished>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CoreEvent_TransferFinished&&(identical(other.id, id) || other.id == id)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,error);
}

@override
String toString() {
    return 'CoreEvent.transferFinished(id: $id, error: $error)';
}


}

/// @nodoc
abstract mixin class $CoreEvent_TransferFinishedCopyWith<$Res> implements $CoreEventCopyWith<$Res> {
  factory $CoreEvent_TransferFinishedCopyWith(CoreEvent_TransferFinished value, $Res Function(CoreEvent_TransferFinished) _then) = _$CoreEvent_TransferFinishedCopyWithImpl;
@useResult
$Res call({
 int id, String? error
});




}
/// @nodoc
class _$CoreEvent_TransferFinishedCopyWithImpl<$Res>
    implements $CoreEvent_TransferFinishedCopyWith<$Res> {
  _$CoreEvent_TransferFinishedCopyWithImpl(this._self, this._then);

  final CoreEvent_TransferFinished _self;
  final $Res Function(CoreEvent_TransferFinished) _then;

/// Create a copy of CoreEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? id = null,Object? error = freezed,}) {
  return _then(CoreEvent_TransferFinished(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc


class CoreEvent_Log extends CoreEvent {
  const CoreEvent_Log({required this.level, required this.message}): super._();
  

 final  String level;
 final  String message;

/// Create a copy of CoreEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CoreEvent_LogCopyWith<CoreEvent_Log> get copyWith => _$CoreEvent_LogCopyWithImpl<CoreEvent_Log>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CoreEvent_Log&&(identical(other.level, level) || other.level == level)&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode {
    return Object.hash(runtimeType,level,message);
}

@override
String toString() {
    return 'CoreEvent.log(level: $level, message: $message)';
}


}

/// @nodoc
abstract mixin class $CoreEvent_LogCopyWith<$Res> implements $CoreEventCopyWith<$Res> {
  factory $CoreEvent_LogCopyWith(CoreEvent_Log value, $Res Function(CoreEvent_Log) _then) = _$CoreEvent_LogCopyWithImpl;
@useResult
$Res call({
 String level, String message
});




}
/// @nodoc
class _$CoreEvent_LogCopyWithImpl<$Res>
    implements $CoreEvent_LogCopyWith<$Res> {
  _$CoreEvent_LogCopyWithImpl(this._self, this._then);

  final CoreEvent_Log _self;
  final $Res Function(CoreEvent_Log) _then;

/// Create a copy of CoreEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? level = null,Object? message = null,}) {
  return _then(CoreEvent_Log(
level: null == level ? _self.level : level // ignore: cast_nullable_to_non_nullable
as String,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class CoreEvent_Denied extends CoreEvent {
  const CoreEvent_Denied({required this.message}): super._();
  

 final  String message;

/// Create a copy of CoreEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CoreEvent_DeniedCopyWith<CoreEvent_Denied> get copyWith => _$CoreEvent_DeniedCopyWithImpl<CoreEvent_Denied>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CoreEvent_Denied&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode {
    return Object.hash(runtimeType,message);
}

@override
String toString() {
    return 'CoreEvent.denied(message: $message)';
}


}

/// @nodoc
abstract mixin class $CoreEvent_DeniedCopyWith<$Res> implements $CoreEventCopyWith<$Res> {
  factory $CoreEvent_DeniedCopyWith(CoreEvent_Denied value, $Res Function(CoreEvent_Denied) _then) = _$CoreEvent_DeniedCopyWithImpl;
@useResult
$Res call({
 String message
});




}
/// @nodoc
class _$CoreEvent_DeniedCopyWithImpl<$Res>
    implements $CoreEvent_DeniedCopyWith<$Res> {
  _$CoreEvent_DeniedCopyWithImpl(this._self, this._then);

  final CoreEvent_Denied _self;
  final $Res Function(CoreEvent_Denied) _then;

/// Create a copy of CoreEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? message = null,}) {
  return _then(CoreEvent_Denied(
message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class CoreEvent_Failed extends CoreEvent {
  const CoreEvent_Failed({required this.message}): super._();
  

 final  String message;

/// Create a copy of CoreEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CoreEvent_FailedCopyWith<CoreEvent_Failed> get copyWith => _$CoreEvent_FailedCopyWithImpl<CoreEvent_Failed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CoreEvent_Failed&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode {
    return Object.hash(runtimeType,message);
}

@override
String toString() {
    return 'CoreEvent.failed(message: $message)';
}


}

/// @nodoc
abstract mixin class $CoreEvent_FailedCopyWith<$Res> implements $CoreEventCopyWith<$Res> {
  factory $CoreEvent_FailedCopyWith(CoreEvent_Failed value, $Res Function(CoreEvent_Failed) _then) = _$CoreEvent_FailedCopyWithImpl;
@useResult
$Res call({
 String message
});




}
/// @nodoc
class _$CoreEvent_FailedCopyWithImpl<$Res>
    implements $CoreEvent_FailedCopyWith<$Res> {
  _$CoreEvent_FailedCopyWithImpl(this._self, this._then);

  final CoreEvent_Failed _self;
  final $Res Function(CoreEvent_Failed) _then;

/// Create a copy of CoreEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? message = null,}) {
  return _then(CoreEvent_Failed(
message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$CoreSessionState {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CoreSessionState);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'CoreSessionState()';
}


}

/// @nodoc
class $CoreSessionStateCopyWith<$Res>  {
$CoreSessionStateCopyWith(CoreSessionState _, $Res Function(CoreSessionState) __);
}


/// Adds pattern-matching-related methods to [CoreSessionState].
extension CoreSessionStatePatterns on CoreSessionState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( CoreSessionState_Disconnected value)?  disconnected,TResult Function( CoreSessionState_Connecting value)?  connecting,TResult Function( CoreSessionState_Connected value)?  connected,TResult Function( CoreSessionState_Reconnecting value)?  reconnecting,required TResult orElse(),}){
final _that = this;
switch (_that) {
case CoreSessionState_Disconnected() when disconnected != null:
return disconnected(_that);case CoreSessionState_Connecting() when connecting != null:
return connecting(_that);case CoreSessionState_Connected() when connected != null:
return connected(_that);case CoreSessionState_Reconnecting() when reconnecting != null:
return reconnecting(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( CoreSessionState_Disconnected value)  disconnected,required TResult Function( CoreSessionState_Connecting value)  connecting,required TResult Function( CoreSessionState_Connected value)  connected,required TResult Function( CoreSessionState_Reconnecting value)  reconnecting,}){
final _that = this;
switch (_that) {
case CoreSessionState_Disconnected():
return disconnected(_that);case CoreSessionState_Connecting():
return connecting(_that);case CoreSessionState_Connected():
return connected(_that);case CoreSessionState_Reconnecting():
return reconnecting(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( CoreSessionState_Disconnected value)?  disconnected,TResult? Function( CoreSessionState_Connecting value)?  connecting,TResult? Function( CoreSessionState_Connected value)?  connected,TResult? Function( CoreSessionState_Reconnecting value)?  reconnecting,}){
final _that = this;
switch (_that) {
case CoreSessionState_Disconnected() when disconnected != null:
return disconnected(_that);case CoreSessionState_Connecting() when connecting != null:
return connecting(_that);case CoreSessionState_Connected() when connected != null:
return connected(_that);case CoreSessionState_Reconnecting() when reconnecting != null:
return reconnecting(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  disconnected,TResult Function()?  connecting,TResult Function( int clientId,  int channelId)?  connected,TResult Function( int attempt,  int delayMs)?  reconnecting,required TResult orElse(),}) {final _that = this;
switch (_that) {
case CoreSessionState_Disconnected() when disconnected != null:
return disconnected();case CoreSessionState_Connecting() when connecting != null:
return connecting();case CoreSessionState_Connected() when connected != null:
return connected(_that.clientId,_that.channelId);case CoreSessionState_Reconnecting() when reconnecting != null:
return reconnecting(_that.attempt,_that.delayMs);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  disconnected,required TResult Function()  connecting,required TResult Function( int clientId,  int channelId)  connected,required TResult Function( int attempt,  int delayMs)  reconnecting,}) {final _that = this;
switch (_that) {
case CoreSessionState_Disconnected():
return disconnected();case CoreSessionState_Connecting():
return connecting();case CoreSessionState_Connected():
return connected(_that.clientId,_that.channelId);case CoreSessionState_Reconnecting():
return reconnecting(_that.attempt,_that.delayMs);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  disconnected,TResult? Function()?  connecting,TResult? Function( int clientId,  int channelId)?  connected,TResult? Function( int attempt,  int delayMs)?  reconnecting,}) {final _that = this;
switch (_that) {
case CoreSessionState_Disconnected() when disconnected != null:
return disconnected();case CoreSessionState_Connecting() when connecting != null:
return connecting();case CoreSessionState_Connected() when connected != null:
return connected(_that.clientId,_that.channelId);case CoreSessionState_Reconnecting() when reconnecting != null:
return reconnecting(_that.attempt,_that.delayMs);case _:
  return null;

}
}

}

/// @nodoc


class CoreSessionState_Disconnected extends CoreSessionState {
  const CoreSessionState_Disconnected(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CoreSessionState_Disconnected);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'CoreSessionState.disconnected()';
}


}




/// @nodoc


class CoreSessionState_Connecting extends CoreSessionState {
  const CoreSessionState_Connecting(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CoreSessionState_Connecting);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'CoreSessionState.connecting()';
}


}




/// @nodoc


class CoreSessionState_Connected extends CoreSessionState {
  const CoreSessionState_Connected({required this.clientId, required this.channelId}): super._();
  

 final  int clientId;
 final  int channelId;

/// Create a copy of CoreSessionState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CoreSessionState_ConnectedCopyWith<CoreSessionState_Connected> get copyWith => _$CoreSessionState_ConnectedCopyWithImpl<CoreSessionState_Connected>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CoreSessionState_Connected&&(identical(other.clientId, clientId) || other.clientId == clientId)&&(identical(other.channelId, channelId) || other.channelId == channelId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,clientId,channelId);
}

@override
String toString() {
    return 'CoreSessionState.connected(clientId: $clientId, channelId: $channelId)';
}


}

/// @nodoc
abstract mixin class $CoreSessionState_ConnectedCopyWith<$Res> implements $CoreSessionStateCopyWith<$Res> {
  factory $CoreSessionState_ConnectedCopyWith(CoreSessionState_Connected value, $Res Function(CoreSessionState_Connected) _then) = _$CoreSessionState_ConnectedCopyWithImpl;
@useResult
$Res call({
 int clientId, int channelId
});




}
/// @nodoc
class _$CoreSessionState_ConnectedCopyWithImpl<$Res>
    implements $CoreSessionState_ConnectedCopyWith<$Res> {
  _$CoreSessionState_ConnectedCopyWithImpl(this._self, this._then);

  final CoreSessionState_Connected _self;
  final $Res Function(CoreSessionState_Connected) _then;

/// Create a copy of CoreSessionState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? clientId = null,Object? channelId = null,}) {
  return _then(CoreSessionState_Connected(
clientId: null == clientId ? _self.clientId : clientId // ignore: cast_nullable_to_non_nullable
as int,channelId: null == channelId ? _self.channelId : channelId // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class CoreSessionState_Reconnecting extends CoreSessionState {
  const CoreSessionState_Reconnecting({required this.attempt, required this.delayMs}): super._();
  

 final  int attempt;
 final  int delayMs;

/// Create a copy of CoreSessionState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CoreSessionState_ReconnectingCopyWith<CoreSessionState_Reconnecting> get copyWith => _$CoreSessionState_ReconnectingCopyWithImpl<CoreSessionState_Reconnecting>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CoreSessionState_Reconnecting&&(identical(other.attempt, attempt) || other.attempt == attempt)&&(identical(other.delayMs, delayMs) || other.delayMs == delayMs));
}


@override
int get hashCode {
    return Object.hash(runtimeType,attempt,delayMs);
}

@override
String toString() {
    return 'CoreSessionState.reconnecting(attempt: $attempt, delayMs: $delayMs)';
}


}

/// @nodoc
abstract mixin class $CoreSessionState_ReconnectingCopyWith<$Res> implements $CoreSessionStateCopyWith<$Res> {
  factory $CoreSessionState_ReconnectingCopyWith(CoreSessionState_Reconnecting value, $Res Function(CoreSessionState_Reconnecting) _then) = _$CoreSessionState_ReconnectingCopyWithImpl;
@useResult
$Res call({
 int attempt, int delayMs
});




}
/// @nodoc
class _$CoreSessionState_ReconnectingCopyWithImpl<$Res>
    implements $CoreSessionState_ReconnectingCopyWith<$Res> {
  _$CoreSessionState_ReconnectingCopyWithImpl(this._self, this._then);

  final CoreSessionState_Reconnecting _self;
  final $Res Function(CoreSessionState_Reconnecting) _then;

/// Create a copy of CoreSessionState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? attempt = null,Object? delayMs = null,}) {
  return _then(CoreSessionState_Reconnecting(
attempt: null == attempt ? _self.attempt : attempt // ignore: cast_nullable_to_non_nullable
as int,delayMs: null == delayMs ? _self.delayMs : delayMs // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

// dart format on
