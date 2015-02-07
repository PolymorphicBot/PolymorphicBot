part of polymorphic.utils;

typedef void Action();

void debug(Action action) {
  if (DEBUG) {
    action();
  }
}

bool get DEBUG {
  if (Zone.current["debug"] == true) {
    return true;
  }
  
  try {
    assert(false);
  } on AssertionError catch (e) {
    return true;
  }
  
  return false;
}

/**
 * Information about the current environment.
 */
class EnvironmentUtils {
  /**
   * Detects when the current isolate has been compiled by a compiler.
   */
  static bool isCompiled() {
    return new bool.fromEnvironment("compiled", defaultValue: false);
  }
  
  /**
   * Detects when the current isolate is more than likely a plugin.
   */
  static bool isPlugin() {
    try {
      currentMirrorSystem().findLibrary(#polymorphic.bot);
      return false;
    } catch (e) {
    }
    
    LibraryMirror lib;
    
    try {
      lib = currentMirrorSystem().findLibrary(#polymorphic.api);
    } catch (e) {
      return false;
    }
    
    InstanceMirror loadedM;
    
    try {
      loadedM = lib.getField(#_createdPlugin);
    } catch (e) {
      return false;
    }
    
    return lib != null && loadedM.reflectee == true;
  }
}

String yamlToString(data) {
  var buffer = new StringBuffer();

  _stringify(bool isMapValue, String indent, data) {
    // Use indentation for (non-empty) maps.
    if (data is Map && !data.isEmpty) {
      if (isMapValue) {
        buffer.writeln();
        indent += '  ';
      }

      // Sort the keys. This minimizes deltas in diffs.
      var keys = data.keys.toList();
      keys.sort((a, b) => a.toString().compareTo(b.toString()));

      var first = true;
      for (var key in keys) {
        if (!first) buffer.writeln();
        first = false;

        var keyString = key;
        
        if (key is! String || !_unquotableYamlString.hasMatch(key)) {
          keyString = JSON.encode(key);
        }

        buffer.write('$indent$keyString:');
        _stringify(true, indent, data[key]);
      }

      return;
    }

    // Everything else we just stringify using JSON to handle escapes in
    // strings and number formatting.
    var string = data;

    // Don't quote plain strings if not needed.
    if (data is! String || !_unquotableYamlString.hasMatch(data)) {
      string = JSON.encode(data);
    }

    if (isMapValue) {
      buffer.write(' $string');
    } else {
      buffer.write('$indent$string');
    }
  }

  _stringify(false, '', data);
  return buffer.toString();
}

final _unquotableYamlString = new RegExp(r"^[a-zA-Z_-][a-zA-Z_0-9-]*$");