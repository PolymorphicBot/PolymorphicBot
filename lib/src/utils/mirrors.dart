part of polymorphic.utils;

class FunctionAnnotation<T> {
  T metadata;
  MethodMirror mirror;
  Function function;
  
  dynamic invoke(List<dynamic> args) {
    return function(args);  
  }
  
  List<ParameterMirror> get parameters => mirror.parameters;
}

class ClassAnnotation<T> {
  T metadata;
  ClassMirror mirror;
}

typedef InterceptionHandler(List<dynamic> positional, Map<Symbol, dynamic> named);

class Interceptor {
  final InterceptionHandler handler;
  
  Interceptor(this.handler);
  
  @override
  noSuchMethod(inv) {
    if (!inv.isAccessor && inv.memberName == #call) {
      var positional = inv.positionalArguments;
      var named = inv.namedArguments;
      
      return handler(positional, named);
    } else {
      return super.noSuchMethod(inv);
    }
  }
}

List<FunctionAnnotation> findFunctionAnnotations(Type type,
    {InstanceMirror instance, LibraryMirror lib}) {
  LibraryMirror l = (lib == null ? currentMirrorSystem().isolate.rootLibrary : lib);
  var result = [];
  var t = reflectType(type);
  var decl = instance != null ? instance.type.declarations.values :
      l.declarations.values;

  var mm = decl.where((it) =>
      it is MethodMirror && it.metadata.any((f) => t.isAssignableTo(f.type)));

  for (var m in mm) {
    var a = new FunctionAnnotation();
    a.metadata =
        m.metadata.firstWhere((it) => t.isAssignableTo(it.type)).reflectee;
    a.mirror = m;
    a.function = (List<dynamic> args) {
      if (instance != null) {
        return instance.invoke(m.simpleName, args).reflectee;
      } else {
        return l.invoke(m.simpleName, args).reflectee;
      }
    };
    result.add(a);
  }
  return result;
}

List<VariableMirror> findVariablesAnnotation(Type type) {
  var name = reflectType(type).simpleName;
  LibraryMirror lib = currentMirrorSystem().isolate.rootLibrary;
  
  return lib.declarations.values.where((it) =>
      it is VariableMirror
      && !it.isConst
      && !it.isFinal
      && !it.isPrivate 
      && it.isTopLevel
      && it.metadata.any((it) => name == it.type.simpleName)).map((it) => it as VariableMirror).toList();
}

List<ClassAnnotation> findClassesAnnotation(Type type, {LibraryMirror lib}) =>
    (lib == null ? currentMirrorSystem().isolate.rootLibrary :
        lib).declarations.values
    .where((it) => it is ClassMirror &&
        it.metadata.any((a) => reflectType(type).isAssignableTo(a.type)))
    .map((it) {
  return new ClassAnnotation()
    ..metadata = (it.metadata.firstWhere(
        (it) => reflectType(type).isAssignableTo(it.type)).reflectee)
    ..mirror = it;
});