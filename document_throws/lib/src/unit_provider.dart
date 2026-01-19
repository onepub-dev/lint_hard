import 'package:analyzer/dart/ast/ast.dart';

abstract class UnitProvider {
  CompilationUnit? unitForPath(String path);
}

class MapUnitProvider implements UnitProvider {
  final Map<String, CompilationUnit> unitsByPath;

  const MapUnitProvider(this.unitsByPath);

  @override
  CompilationUnit? unitForPath(String path) => unitsByPath[path];
}
