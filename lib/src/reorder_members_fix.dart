import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/error/error.dart';
import 'package:analyzer/source/source_range.dart';
import 'package:custom_lint_builder/custom_lint_builder.dart';

class ReorderMembersFix extends DartFix {
  ReorderMembersFix();

  @override
  Future<void> run(
    CustomLintResolver resolver,
    ChangeReporter reporter,
    CustomLintContext context,
    AnalysisError analysisError,
    List<AnalysisError> others,
  ) async {
    final unit = await resolver.getResolvedUnitResult();
    final content = unit.content;

    // Only decide to show the fix if the primary error really needs changes.
    final type = _containingType(unit.unit, analysisError.offset);
    late final List<ClassMember> members;
    switch (type) {
      case ClassDeclaration d:
        members = d.members;
      case MixinDeclaration d:
        members = d.members;
      default:
        return; // skip enums/others
    }
    final decl = type!;

    if (members.isEmpty) return;
    if (_alreadyOrdered(members)) return;

    final changeBuilder = reporter.createChangeBuilder(
      message: 'Reorder members: fields → constructors → others',
      priority: 1,
    );

    changeBuilder.addDartFileEdit((builder) {
      // We’ll fix all affected types in this file (primary + others), but dedupe.
      final handledDecls = <int>{};

      Future<void> applyTo(AstNode d) async {
        if (!handledDecls.add(d.offset)) return;

        final mems =
            d is ClassDeclaration ? d.members : (d as MixinDeclaration).members;
        if (mems.isEmpty || _alreadyOrdered(mems)) return;

        final fields = <ClassMember>[];
        final ctors = <ClassMember>[];
        final othersM = <ClassMember>[];

        for (final m in mems) {
          if (m is FieldDeclaration) {
            fields.add(m);
          } else if (m is ConstructorDeclaration) {
            ctors.add(m);
          } else {
            othersM.add(m);
          }
        }

        final nl = content.contains('\r\n') ? '\r\n' : '\n';

        // IMPORTANT: each slice includes leading comments & original indentation
        String slice(ClassMember m) {
          final start = _memberSliceStart(content, m);
          return content.substring(start, m.end);
        }

        String joinGroup(List<ClassMember> group) =>
            group.map(slice).join('$nl$nl');

        final parts = <String>[];
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
          _memberSliceStart(content, mems.first),
        );
        final end = mems.last.end;

        builder.addSimpleReplacement(
          SourceRange(firstStartLine, end - firstStartLine),
          newBlock,
        );
      }

      // Primary declaration
      applyTo(decl);

      // Fix-all in file for same-code diagnostics
      for (final err in others) {
        final d = _containingType(unit.unit, err.offset);
        if (d is ClassDeclaration || d is MixinDeclaration) {
          applyTo(d!);
        }
      }
    });
  }

  // ---- helpers ----

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
    if (members.length != fields.length + ctors.length + others.length)
      return false;
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

  /// Start of the class/mixin/enum containing [offset], or null.
  AstNode? _containingType(CompilationUnit unit, int offset) {
    for (final d in unit.declarations) {
      if (d is ClassDeclaration ||
          d is MixinDeclaration ||
          d is EnumDeclaration) {
        if (d.offset <= offset && offset < d.end) return d;
      }
    }
    return null;
  }

  /// Returns the **line start** of the member slice, including:
  /// - doc comments (`///` or `/** ... */`)
  /// - annotations (`@deprecated`, etc.)
  /// - any contiguous `//` lines or `/* ... */` block immediately above
  ///   (but stops at the first blank line).
  int _memberSliceStart(String content, ClassMember m) {
    var earliest = m.offset;

    // Include doc comments / metadata when present
    final doc = m.documentationComment;
    if (doc != null) earliest = doc.offset < earliest ? doc.offset : earliest;
    final md = m.metadata;
    if (md.isNotEmpty) {
      final mdStart = md.first.offset;
      if (mdStart < earliest) earliest = mdStart;
    }

    // Start from the beginning of that line
    var top = _lineStart(content, earliest);

    // Now walk upwards over immediate comment(s), stopping on first blank line
    var cursor = top;
    var inBlock = false;

    while (true) {
      if (cursor == 0) break;
      final prevStart = _lineStart(content, cursor - 1);
      final line = content.substring(prevStart, cursor);

      // If the previous line is blank, stop (do not include the blank line)
      if (line.trim().isEmpty) break;

      final text = line.trimLeft();

      if (!inBlock) {
        if (text.startsWith('//')) {
          cursor = prevStart; // include the line
          continue;
        }
        if (text.endsWith('*/')) {
          inBlock = true;
          cursor = prevStart; // include the '*/' line
          continue;
        }
        // Not a comment line: stop
        break;
      } else {
        // We are inside a /* ... */ block, include lines until we hit '/*'
        cursor = prevStart;
        if (text.startsWith('/*')) {
          inBlock = false;
          continue;
        }
        // keep going up
      }
    }

    // Slice begins at the first included comment/annotation/decl line **start**
    return cursor;
  }

  /// Start-of-line index for [offset]
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
