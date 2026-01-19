import 'dart:io';

import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

enum DocumentationStyle { docComment, annotation }

const _configKey = 'document_throws';
const _styleKey = 'documentation_style';
const _styleKeyAlt = 'documentationStyle';

final _styleCache = <String, DocumentationStyle>{};

DocumentationStyle documentationStyleForContext(RuleContext context) {
  final root = context.package?.root.path;
  if (root == null) return DocumentationStyle.docComment;
  return _styleCache.putIfAbsent(root, () => _readStyleFromRoot(root));
}

DocumentationStyle documentationStyleForRoot(String rootPath) {
  return _styleCache.putIfAbsent(rootPath, () => _readStyleFromRoot(rootPath));
}

DocumentationStyle _readStyleFromRoot(String rootPath) {
  final optionsFile = File(p.join(rootPath, 'analysis_options.yaml'));
  if (!optionsFile.existsSync()) return DocumentationStyle.docComment;
  final doc = loadYaml(optionsFile.readAsStringSync());
  if (doc is! YamlMap) return DocumentationStyle.docComment;
  final config = doc[_configKey];
  if (config is! YamlMap) return DocumentationStyle.docComment;
  final raw = config[_styleKey] ?? config[_styleKeyAlt];
  if (raw is! String) return DocumentationStyle.docComment;
  return _parseStyle(raw);
}

DocumentationStyle _parseStyle(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'annotation':
    case 'annotations':
      return DocumentationStyle.annotation;
    case 'doc':
    case 'doc_comment':
    case 'doc-comment':
    case 'comment':
    case 'doccomment':
      return DocumentationStyle.docComment;
    default:
      return DocumentationStyle.docComment;
  }
}
