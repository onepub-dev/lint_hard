import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

import 'throws_cache_lookup.dart';

class ThrowsIndexUpToDate extends AnalysisRule {
  static const LintCode code = LintCode(
    'throws_index_up_to_date',
    'Throws cache is missing or out of date (missing: {0}).',
    correctionMessage: 'Run dt-index to refresh the throws cache.',
  );

  ThrowsIndexUpToDate()
    : super(
        name: code.name,
        description:
            'Warn when the throws cache for SDK or packages is missing.',
      );

  @override
  LintCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    final visitor = _Visitor(this, context);
    registry.addCompilationUnit(this, visitor);
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  static final Set<String> _reportedRoots = {};

  final AnalysisRule rule;
  final RuleContext context;

  _Visitor(this.rule, this.context);

  @override
  void visitCompilationUnit(CompilationUnit node) {
    final root = context.package?.root.path;
    if (root == null) return;
    if (_reportedRoots.contains(root)) return;
    _reportedRoots.add(root);

    final lookup = ThrowsCacheLookup.forProjectRoot(root);
    if (lookup == null) return;

    final missing = lookup.missingCaches();
    if (missing.isEmpty) return;

    final firstMissing = firstMissingCacheLabel(missing);
    if (firstMissing == null) return;

    final token = node.beginToken;
    rule.reportAtToken(token, arguments: [firstMissing]);
  }
}

String? firstMissingCacheLabel(MissingThrowsCaches missing) {
  if (missing.sdkMissing) return 'sdk';
  if (missing.missingPackages.isEmpty) return null;
  return missing.missingPackages.first;
}
