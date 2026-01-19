/// @Throwing(
///   ArgumentError,
///   reason: 'Because bad things',
///   call: 'args|addMultiOption',
///   origin: 'args|_addOption',
/// )
/// @Throwing(ArgumentError)
void main(List<String> args) {
  throw ArgumentError('bad');
}
