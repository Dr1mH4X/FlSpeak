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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( CoreError_PolicyDenied value)?  policyDenied,TResult Function( CoreError_Connection value)?  connection,TResult Function( CoreError_Internal value)?  internal,required TResult orElse(),}){
final _that = this;
switch (_that) {
case CoreError_PolicyDenied() when policyDenied != null:
return policyDenied(_that);case CoreError_Connection() when connection != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( CoreError_PolicyDenied value)  policyDenied,required TResult Function( CoreError_Connection value)  connection,required TResult Function( CoreError_Internal value)  internal,}){
final _that = this;
switch (_that) {
case CoreError_PolicyDenied():
return policyDenied(_that);case CoreError_Connection():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( CoreError_PolicyDenied value)?  policyDenied,TResult? Function( CoreError_Connection value)?  connection,TResult? Function( CoreError_Internal value)?  internal,}){
final _that = this;
switch (_that) {
case CoreError_PolicyDenied() when policyDenied != null:
return policyDenied(_that);case CoreError_Connection() when connection != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String message)?  policyDenied,TResult Function( String message)?  connection,TResult Function( String message)?  internal,required TResult orElse(),}) {final _that = this;
switch (_that) {
case CoreError_PolicyDenied() when policyDenied != null:
return policyDenied(_that.message);case CoreError_Connection() when connection != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String message)  policyDenied,required TResult Function( String message)  connection,required TResult Function( String message)  internal,}) {final _that = this;
switch (_that) {
case CoreError_PolicyDenied():
return policyDenied(_that.message);case CoreError_Connection():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String message)?  policyDenied,TResult? Function( String message)?  connection,TResult? Function( String message)?  internal,}) {final _that = this;
switch (_that) {
case CoreError_PolicyDenied() when policyDenied != null:
return policyDenied(_that.message);case CoreError_Connection() when connection != null:
return connection(_that.message);case CoreError_Internal() when internal != null:
return internal(_that.message);case _:
  return null;

}
}

}

/// @nodoc


class CoreError_PolicyDenied extends CoreError {
  const CoreError_PolicyDenied({required this.message}): super._();
  

@override final  String message;

/// Create a copy of CoreError
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CoreError_PolicyDeniedCopyWith<CoreError_PolicyDenied> get copyWith => _$CoreError_PolicyDeniedCopyWithImpl<CoreError_PolicyDenied>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CoreError_PolicyDenied&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode {
    return Object.hash(runtimeType,message);
}

@override
String toString() {
    return 'CoreError.policyDenied(message: $message)';
}


}

/// @nodoc
abstract mixin class $CoreError_PolicyDeniedCopyWith<$Res> implements $CoreErrorCopyWith<$Res> {
  factory $CoreError_PolicyDeniedCopyWith(CoreError_PolicyDenied value, $Res Function(CoreError_PolicyDenied) _then) = _$CoreError_PolicyDeniedCopyWithImpl;
@override @useResult
$Res call({
 String message
});




}
/// @nodoc
class _$CoreError_PolicyDeniedCopyWithImpl<$Res>
    implements $CoreError_PolicyDeniedCopyWith<$Res> {
  _$CoreError_PolicyDeniedCopyWithImpl(this._self, this._then);

  final CoreError_PolicyDenied _self;
  final $Res Function(CoreError_PolicyDenied) _then;

/// Create a copy of CoreError
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? message = null,}) {
  return _then(CoreError_PolicyDenied(
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( CoreEvent_State value)?  state,TResult Function( CoreEvent_Servers value)?  servers,TResult Function( CoreEvent_TextMessage value)?  textMessage,TResult Function( CoreEvent_ClientJoined value)?  clientJoined,TResult Function( CoreEvent_ClientLeft value)?  clientLeft,TResult Function( CoreEvent_ClientMoved value)?  clientMoved,TResult Function( CoreEvent_Log value)?  log,TResult Function( CoreEvent_Denied value)?  denied,TResult Function( CoreEvent_Failed value)?  failed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case CoreEvent_State() when state != null:
return state(_that);case CoreEvent_Servers() when servers != null:
return servers(_that);case CoreEvent_TextMessage() when textMessage != null:
return textMessage(_that);case CoreEvent_ClientJoined() when clientJoined != null:
return clientJoined(_that);case CoreEvent_ClientLeft() when clientLeft != null:
return clientLeft(_that);case CoreEvent_ClientMoved() when clientMoved != null:
return clientMoved(_that);case CoreEvent_Log() when log != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( CoreEvent_State value)  state,required TResult Function( CoreEvent_Servers value)  servers,required TResult Function( CoreEvent_TextMessage value)  textMessage,required TResult Function( CoreEvent_ClientJoined value)  clientJoined,required TResult Function( CoreEvent_ClientLeft value)  clientLeft,required TResult Function( CoreEvent_ClientMoved value)  clientMoved,required TResult Function( CoreEvent_Log value)  log,required TResult Function( CoreEvent_Denied value)  denied,required TResult Function( CoreEvent_Failed value)  failed,}){
final _that = this;
switch (_that) {
case CoreEvent_State():
return state(_that);case CoreEvent_Servers():
return servers(_that);case CoreEvent_TextMessage():
return textMessage(_that);case CoreEvent_ClientJoined():
return clientJoined(_that);case CoreEvent_ClientLeft():
return clientLeft(_that);case CoreEvent_ClientMoved():
return clientMoved(_that);case CoreEvent_Log():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( CoreEvent_State value)?  state,TResult? Function( CoreEvent_Servers value)?  servers,TResult? Function( CoreEvent_TextMessage value)?  textMessage,TResult? Function( CoreEvent_ClientJoined value)?  clientJoined,TResult? Function( CoreEvent_ClientLeft value)?  clientLeft,TResult? Function( CoreEvent_ClientMoved value)?  clientMoved,TResult? Function( CoreEvent_Log value)?  log,TResult? Function( CoreEvent_Denied value)?  denied,TResult? Function( CoreEvent_Failed value)?  failed,}){
final _that = this;
switch (_that) {
case CoreEvent_State() when state != null:
return state(_that);case CoreEvent_Servers() when servers != null:
return servers(_that);case CoreEvent_TextMessage() when textMessage != null:
return textMessage(_that);case CoreEvent_ClientJoined() when clientJoined != null:
return clientJoined(_that);case CoreEvent_ClientLeft() when clientLeft != null:
return clientLeft(_that);case CoreEvent_ClientMoved() when clientMoved != null:
return clientMoved(_that);case CoreEvent_Log() when log != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( CoreSessionState state)?  state,TResult Function( List<ServerProfileView> profiles)?  servers,TResult Function( String from,  String fromUid,  String message,  int targetMode,  int targetId)?  textMessage,TResult Function( int id,  String nickname,  int channelId)?  clientJoined,TResult Function( int id)?  clientLeft,TResult Function( int id,  int channelId)?  clientMoved,TResult Function( String level,  String message)?  log,TResult Function( String message)?  denied,TResult Function( String message)?  failed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case CoreEvent_State() when state != null:
return state(_that.state);case CoreEvent_Servers() when servers != null:
return servers(_that.profiles);case CoreEvent_TextMessage() when textMessage != null:
return textMessage(_that.from,_that.fromUid,_that.message,_that.targetMode,_that.targetId);case CoreEvent_ClientJoined() when clientJoined != null:
return clientJoined(_that.id,_that.nickname,_that.channelId);case CoreEvent_ClientLeft() when clientLeft != null:
return clientLeft(_that.id);case CoreEvent_ClientMoved() when clientMoved != null:
return clientMoved(_that.id,_that.channelId);case CoreEvent_Log() when log != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( CoreSessionState state)  state,required TResult Function( List<ServerProfileView> profiles)  servers,required TResult Function( String from,  String fromUid,  String message,  int targetMode,  int targetId)  textMessage,required TResult Function( int id,  String nickname,  int channelId)  clientJoined,required TResult Function( int id)  clientLeft,required TResult Function( int id,  int channelId)  clientMoved,required TResult Function( String level,  String message)  log,required TResult Function( String message)  denied,required TResult Function( String message)  failed,}) {final _that = this;
switch (_that) {
case CoreEvent_State():
return state(_that.state);case CoreEvent_Servers():
return servers(_that.profiles);case CoreEvent_TextMessage():
return textMessage(_that.from,_that.fromUid,_that.message,_that.targetMode,_that.targetId);case CoreEvent_ClientJoined():
return clientJoined(_that.id,_that.nickname,_that.channelId);case CoreEvent_ClientLeft():
return clientLeft(_that.id);case CoreEvent_ClientMoved():
return clientMoved(_that.id,_that.channelId);case CoreEvent_Log():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( CoreSessionState state)?  state,TResult? Function( List<ServerProfileView> profiles)?  servers,TResult? Function( String from,  String fromUid,  String message,  int targetMode,  int targetId)?  textMessage,TResult? Function( int id,  String nickname,  int channelId)?  clientJoined,TResult? Function( int id)?  clientLeft,TResult? Function( int id,  int channelId)?  clientMoved,TResult? Function( String level,  String message)?  log,TResult? Function( String message)?  denied,TResult? Function( String message)?  failed,}) {final _that = this;
switch (_that) {
case CoreEvent_State() when state != null:
return state(_that.state);case CoreEvent_Servers() when servers != null:
return servers(_that.profiles);case CoreEvent_TextMessage() when textMessage != null:
return textMessage(_that.from,_that.fromUid,_that.message,_that.targetMode,_that.targetId);case CoreEvent_ClientJoined() when clientJoined != null:
return clientJoined(_that.id,_that.nickname,_that.channelId);case CoreEvent_ClientLeft() when clientLeft != null:
return clientLeft(_that.id);case CoreEvent_ClientMoved() when clientMoved != null:
return clientMoved(_that.id,_that.channelId);case CoreEvent_Log() when log != null:
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


class CoreEvent_TextMessage extends CoreEvent {
  const CoreEvent_TextMessage({required this.from, required this.fromUid, required this.message, required this.targetMode, required this.targetId}): super._();
  

 final  String from;
 final  String fromUid;
 final  String message;
 final  int targetMode;
 final  int targetId;

/// Create a copy of CoreEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CoreEvent_TextMessageCopyWith<CoreEvent_TextMessage> get copyWith => _$CoreEvent_TextMessageCopyWithImpl<CoreEvent_TextMessage>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CoreEvent_TextMessage&&(identical(other.from, from) || other.from == from)&&(identical(other.fromUid, fromUid) || other.fromUid == fromUid)&&(identical(other.message, message) || other.message == message)&&(identical(other.targetMode, targetMode) || other.targetMode == targetMode)&&(identical(other.targetId, targetId) || other.targetId == targetId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,from,fromUid,message,targetMode,targetId);
}

@override
String toString() {
    return 'CoreEvent.textMessage(from: $from, fromUid: $fromUid, message: $message, targetMode: $targetMode, targetId: $targetId)';
}


}

/// @nodoc
abstract mixin class $CoreEvent_TextMessageCopyWith<$Res> implements $CoreEventCopyWith<$Res> {
  factory $CoreEvent_TextMessageCopyWith(CoreEvent_TextMessage value, $Res Function(CoreEvent_TextMessage) _then) = _$CoreEvent_TextMessageCopyWithImpl;
@useResult
$Res call({
 String from, String fromUid, String message, int targetMode, int targetId
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
@pragma('vm:prefer-inline') $Res call({Object? from = null,Object? fromUid = null,Object? message = null,Object? targetMode = null,Object? targetId = null,}) {
  return _then(CoreEvent_TextMessage(
from: null == from ? _self.from : from // ignore: cast_nullable_to_non_nullable
as String,fromUid: null == fromUid ? _self.fromUid : fromUid // ignore: cast_nullable_to_non_nullable
as String,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,targetMode: null == targetMode ? _self.targetMode : targetMode // ignore: cast_nullable_to_non_nullable
as int,targetId: null == targetId ? _self.targetId : targetId // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class CoreEvent_ClientJoined extends CoreEvent {
  const CoreEvent_ClientJoined({required this.id, required this.nickname, required this.channelId}): super._();
  

 final  int id;
 final  String nickname;
 final  int channelId;

/// Create a copy of CoreEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CoreEvent_ClientJoinedCopyWith<CoreEvent_ClientJoined> get copyWith => _$CoreEvent_ClientJoinedCopyWithImpl<CoreEvent_ClientJoined>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CoreEvent_ClientJoined&&(identical(other.id, id) || other.id == id)&&(identical(other.nickname, nickname) || other.nickname == nickname)&&(identical(other.channelId, channelId) || other.channelId == channelId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,nickname,channelId);
}

@override
String toString() {
    return 'CoreEvent.clientJoined(id: $id, nickname: $nickname, channelId: $channelId)';
}


}

/// @nodoc
abstract mixin class $CoreEvent_ClientJoinedCopyWith<$Res> implements $CoreEventCopyWith<$Res> {
  factory $CoreEvent_ClientJoinedCopyWith(CoreEvent_ClientJoined value, $Res Function(CoreEvent_ClientJoined) _then) = _$CoreEvent_ClientJoinedCopyWithImpl;
@useResult
$Res call({
 int id, String nickname, int channelId
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
@pragma('vm:prefer-inline') $Res call({Object? id = null,Object? nickname = null,Object? channelId = null,}) {
  return _then(CoreEvent_ClientJoined(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,nickname: null == nickname ? _self.nickname : nickname // ignore: cast_nullable_to_non_nullable
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( CoreSessionState_Disconnected value)?  disconnected,TResult Function( CoreSessionState_Connecting value)?  connecting,TResult Function( CoreSessionState_Connected value)?  connected,required TResult orElse(),}){
final _that = this;
switch (_that) {
case CoreSessionState_Disconnected() when disconnected != null:
return disconnected(_that);case CoreSessionState_Connecting() when connecting != null:
return connecting(_that);case CoreSessionState_Connected() when connected != null:
return connected(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( CoreSessionState_Disconnected value)  disconnected,required TResult Function( CoreSessionState_Connecting value)  connecting,required TResult Function( CoreSessionState_Connected value)  connected,}){
final _that = this;
switch (_that) {
case CoreSessionState_Disconnected():
return disconnected(_that);case CoreSessionState_Connecting():
return connecting(_that);case CoreSessionState_Connected():
return connected(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( CoreSessionState_Disconnected value)?  disconnected,TResult? Function( CoreSessionState_Connecting value)?  connecting,TResult? Function( CoreSessionState_Connected value)?  connected,}){
final _that = this;
switch (_that) {
case CoreSessionState_Disconnected() when disconnected != null:
return disconnected(_that);case CoreSessionState_Connecting() when connecting != null:
return connecting(_that);case CoreSessionState_Connected() when connected != null:
return connected(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  disconnected,TResult Function()?  connecting,TResult Function( int clientId,  int channelId)?  connected,required TResult orElse(),}) {final _that = this;
switch (_that) {
case CoreSessionState_Disconnected() when disconnected != null:
return disconnected();case CoreSessionState_Connecting() when connecting != null:
return connecting();case CoreSessionState_Connected() when connected != null:
return connected(_that.clientId,_that.channelId);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  disconnected,required TResult Function()  connecting,required TResult Function( int clientId,  int channelId)  connected,}) {final _that = this;
switch (_that) {
case CoreSessionState_Disconnected():
return disconnected();case CoreSessionState_Connecting():
return connecting();case CoreSessionState_Connected():
return connected(_that.clientId,_that.channelId);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  disconnected,TResult? Function()?  connecting,TResult? Function( int clientId,  int channelId)?  connected,}) {final _that = this;
switch (_that) {
case CoreSessionState_Disconnected() when disconnected != null:
return disconnected();case CoreSessionState_Connecting() when connecting != null:
return connecting();case CoreSessionState_Connected() when connected != null:
return connected(_that.clientId,_that.channelId);case _:
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

// dart format on
