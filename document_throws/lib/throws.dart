class Throws {
  final Type type;
  final String? reason;
  final String? call;
  final String? origin;

  const Throws(
    this.type, {
    this.reason,
    this.call,
    this.origin,
  });
}
