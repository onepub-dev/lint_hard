class Throws {
  final List<Object> entries;

  const Throws(this.entries);
}

class ThrowSpec {
  final Type type;
  final String? reason;

  const ThrowSpec(this.type, [this.reason]);
}
