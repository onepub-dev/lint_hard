import 'package:yaml/yaml.dart' as y;

void undocumentedPrefixed() {
  throw y.YamlException('bad', null);
}
