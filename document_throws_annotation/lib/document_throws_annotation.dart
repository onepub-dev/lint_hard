class Throwing {
  final Type type;
  final String? reason;
  final String? call;
  final String? origin;

  const Throwing(
    this.type, {
    this.reason,
    this.call,
    this.origin,
  });
}
