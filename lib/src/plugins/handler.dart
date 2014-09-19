part of polymorphic.bot;

class PluginHandler {
  final CoreBot bot;
  
  PluginManager pm;
  PluginCommunicator _communicator;

  PluginHandler(this.bot);

  Future init() {
    pm = new PluginManager();
    _communicator = new PluginCommunicator(pm, bot, this);
    return load().then((List<Plugin> plugins) {
      print("[Plugins] Registered: ${plugins.join(" ")}");
      _communicator.handle();
      return plugins;
    });
  }

  Future load() {
    var requirements = {};
    var pluginNames = [];
    var pluginsDirectory = new Directory("plugins");
    if (!pluginsDirectory.existsSync()) pluginsDirectory.createSync();

    /* Patched loadAll() method */
    Future loadAll(Directory directory) {
      var loaders = [];

      directory.listSync(followLinks: true).forEach((entity) {
        if (!(entity is Directory)) return;
        var packagesDirectory = new Directory("${entity.path}/packages");
        var pubspec = new File("${entity.path}/pubspec.yaml");
        Map<String, dynamic> spec = yaml.loadYaml(pubspec.readAsStringSync());

        var info = {
          "dependencies": [],
          "main": "main.dart",
          "update_dependencies": false
        };

        if (spec["plugin"] != null) {
          info = spec["plugin"];
        }

        var plugin_name = spec["name"] as String;

        if (!packagesDirectory.existsSync() && pubspec.existsSync()) {
          /* Execute 'pub get' */
          print("[Plugins] Fetching Dependencies for Plugin '${plugin_name}'");
          var result = Process.runSync(Platform.isWindows ? "pub.bat" : "pub", ["get"], workingDirectory: entity.path);
          if (result.exitCode != 0) {
            print("[Plugins] Failed to Fetch Dependencies for Plugin '${plugin_name}'");
            if (result.stdout.trim() != "") {
              print("[STDOUT]");
              stdout.write(result.stdout);
            }
            if (result.stderr.trim() != "") {
              print("[STDERR]");
              stdout.write(result.stderr);
            }
            exit(1);
          }
        }

        if (info['update_dependencies'] != null ? info['update_dependencies'] : false) {
          var result = Process.runSync(Platform.isWindows ? "pub.bat" : "pub", ["upgrade"], workingDirectory: entity.path);
          if (result.exitCode != 0) {
            print("[Plugins] Failed to Update Dependencies for Plugin '${plugin_name}'");
            if (result.stdout.trim() != "") {
              print("[STDOUT]");
              stdout.write(result.stdout);
            }
            if (result.stderr.trim() != "") {
              print("[STDERR]");
              stdout.write(result.stderr);
            }
            exit(1);
          }
        }


        var loader = () => new BotPluginLoader(entity, info['main'] != null ? info['main'] : "main.dart");
        loaders.add(loader);

        requirements[spec['name']] = new List.from(info['dependencies'] == null ? [] : info['dependencies']);

        pluginNames.add(spec["name"]);
      });

      /* Resolve Plugin Requirements */
      {
        print("[Plugins] Resolving Plugin Requirements");
        for (var name in pluginNames) {
          List<String> requires = requirements[name];
          requires.removeWhere((it) => pluginNames.contains(it));
          if (requires.isNotEmpty) {
            print("[Plugins] Failed to resolve requirements for plugin '${name}'");
            var noun = requires.length == 1 ? "it" : "they";
            var verb = requires.length == 1 ? "was" : "were";
            print("[Plugins] '${name}' requires '${requires.join(", ")}', but ${noun} ${verb} not found");
            exit(1);
          }
        }
      }

      var futures = [];

      loaders.forEach((loader) {
        futures.add(pm.load(loader()));
      });

      return Future.wait(futures);
    }
    return loadAll(pluginsDirectory);
  }
  
  void killPlugins() {
    pm.sendAll({
      "event": "shutdown"
    });
    pm.killAll();
  }
  
  Future reloadPlugins() {
    killPlugins();
    return init();
  }
}

class BotPluginLoader extends PluginLoader {
  final String main;

  BotPluginLoader(Directory directory, [this.main = "main.dart"]) : super(directory);

  @override
  Future<Isolate> load(SendPort port, List<String> args) {
    args = args == null ? [] : args;
    var loc = path.joinAll([directory.absolute.path, main]);
    return Isolate.spawnUri(new Uri.file(loc), args, port).then((isolate) {
      return isolate;
    });
  }
}

class VerificationManager {
  final String plugin;
  final Map data;

  /**
   * The type of command to execute, if any
   */
  String type;

  VerificationManager(this.plugin, this.data);

  dynamic operator [](String field) {
    return verify(field);
  }

  dynamic verify(String field) {
    var info = data[field];
    if (info == null) {
      if (type != null) {
        throw new Exception("$plugin is missing field '$field' when sending command '$type'");
      } else {
        throw new Exception("$plugin is missing field '$field'");
      }
    }
    return info;
  }
}
