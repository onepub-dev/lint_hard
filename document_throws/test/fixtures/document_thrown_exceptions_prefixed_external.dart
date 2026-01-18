import 'package:yaml/yaml.dart' as y;

void undocumentedPrefixedExternal() {
  y.loadYaml('foo: bar');
}
