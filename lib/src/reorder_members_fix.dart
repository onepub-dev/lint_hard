import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analysis_server_plugin/edit/dart/dart_fix_kind_priority.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/source/source_range.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:analyzer_plugin/utilities/fixes/fixes.dart';

import 'sort_fields_then_constructors.dart';

class ReorderMembersFix extends ResolvedCorrectionProducer {
  static const FixKind _fixKind = FixKind(
    'lint_hard.fix.reorder_members',
    DartFixKindPriority.standard,
    'Reorder members: fields → constructors → others',
  );

  // Wire the fix into the analysis server context.
  ReorderMembersFix({required super.context});

  @override
  // Apply within a single file without needing broader analysis.
  CorrectionApplicability get applicability =>
      CorrectionApplicability.acrossSingleFile;

  @override
  // Expose the fix kind identifier for this lint.
  FixKind get fixKind => _fixKind;

  @override
  // Reorder members into fields, constructors, then others.
  Future<void> compute(ChangeBuilder builder) async {
    if (diagnostic?.diagnosticCode != FieldsFirstConstructorsNext.code) return;

    final decl = _containingType(node);
    if (decl == null) return;

    final members = decl.members;
    if (members.isEmpty || _alreadyOrdered(members)) return;

    final content = unitResult.content;
    final nl = content.contains('\r\n') ? '\r\n' : '\n';

    final fields = <ClassMember>[];
    final ctors = <ClassMember>[];
    final othersM = <ClassMember>[];

    for (final m in members) {
      if (m is FieldDeclaration) {
        fields.add(m);
      } else if (m is ConstructorDeclaration) {
        ctors.add(m);
      } else {
        othersM.add(m);
      }
    }

    // Each slice includes leading comments & original indentation.
    // Preserve comments/metadata attached to a member.
    String slice(ClassMember m) {
      final start = _memberSliceStart(content, m);
      return content.substring(start, m.end);
    }

    // Join members with a blank line between them.
    String joinGroup(List<ClassMember> group) =>
        group.map(slice).join('$nl$nl');

    final parts = <String>[];
    // Append a group with spacing between groups.
    void addGroup(List<ClassMember> g) {
      if (g.isEmpty) return;
      if (parts.isNotEmpty) parts.add('$nl$nl');
      parts.add(joinGroup(g));
    }

    addGroup(fields);
    addGroup(ctors);
    addGroup(othersM);

    final newBlock = parts.join();

    // Replace from the beginning of the first member's line to the end of the last member.
    final firstStartLine = _lineStart(
      content,
      _memberSliceStart(content, members.first),
    );
    final end = members.last.end;

    await builder.addDartFileEdit(file, (builder) {
      builder.addSimpleReplacement(
        SourceRange(firstStartLine, end - firstStartLine),
        newBlock,
      );
    });
  }

  // Verify members are already ordered as fields, ctors, then others.
  bool _alreadyOrdered(List<ClassMember> members) {
    final fields = <ClassMember>[];
    final ctors = <ClassMember>[];
    final others = <ClassMember>[];
    for (final m in members) {
      if (m is FieldDeclaration)
        fields.add(m);
      else if (m is ConstructorDeclaration)
        ctors.add(m);
      else
        others.add(m);
    }
    if (members.length != fields.length + ctors.length + others.length) {
      return false;
    }
    var i = 0;
    for (final m in fields) {
      if (!identical(members[i++], m)) return false;
    }
    for (final m in ctors) {
      if (!identical(members[i++], m)) return false;
    }
    for (final m in others) {
      if (!identical(members[i++], m)) return false;
    }
    return true;
  }

  // Find the nearest class or mixin for the current node.
  _ClassOrMixinDecl? _containingType(AstNode node) {
    final decl = node.thisOrAncestorOfType<ClassDeclaration>();
    if (decl != null) return _ClassOrMixinDecl.classDecl(decl);
    final mixinDecl = node.thisOrAncestorOfType<MixinDeclaration>();
    if (mixinDecl != null) return _ClassOrMixinDecl.mixinDecl(mixinDecl);
    return null;
  }

  // Include leading doc/metadata/comment lines for a member slice.
  int _memberSliceStart(String content, ClassMember m) {
    var earliest = m.offset;

    final doc = m.documentationComment;
    if (doc != null) earliest = doc.offset < earliest ? doc.offset : earliest;
    final md = m.metadata;
    if (md.isNotEmpty) {
      final mdStart = md.first.offset;
      if (mdStart < earliest) earliest = mdStart;
    }

    var top = _lineStart(content, earliest);
    var cursor = top;
    var inBlock = false;

    while (true) {
      if (cursor == 0) break;
      final prevStart = _lineStart(content, cursor - 1);
      final line = content.substring(prevStart, cursor);

      if (line.trim().isEmpty) break;

      final text = line.trimLeft();

      if (!inBlock) {
        if (text.startsWith('//')) {
          cursor = prevStart;
          continue;
        }
        if (text.endsWith('*/')) {
          inBlock = true;
          cursor = prevStart;
          continue;
        }
        break;
      } else {
        cursor = prevStart;
        if (text.startsWith('/*')) {
          inBlock = false;
          continue;
        }
      }
    }

    return cursor;
  }

  // Locate the first character offset for the line containing offset.
  int _lineStart(String content, int offset) {
    var i = offset - 1;
    while (i >= 0) {
      final ch = content.codeUnitAt(i);
      if (ch == 0x0A) return i + 1; // \n
      if (ch == 0x0D) {
        final isCrLf =
            (i + 1 < content.length) && content.codeUnitAt(i + 1) == 0x0A;
        return isCrLf ? i + 2 : i + 1;
      }
      i--;
    }
    return 0;
  }
}

class _ClassOrMixinDecl {
  final ClassDeclaration? classDecl;
  final MixinDeclaration? mixinDecl;

  // Represent either a class or mixin declaration.
  const _ClassOrMixinDecl._(this.classDecl, this.mixinDecl);

  // Wrap a class declaration.
  factory _ClassOrMixinDecl.classDecl(ClassDeclaration decl) =>
      _ClassOrMixinDecl._(decl, null);
  // Wrap a mixin declaration.
  factory _ClassOrMixinDecl.mixinDecl(MixinDeclaration decl) =>
      _ClassOrMixinDecl._(null, decl);

  // Return members for the stored class or mixin.
  List<ClassMember> get members =>
      classDecl != null ? classDecl!.members : mixinDecl!.members;
}
