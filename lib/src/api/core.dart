part of polymorphic.api;

class BotConnector {
  final Plugin plugin;

  BotConnector(this.plugin);

  Future<Map<String, dynamic>> getConfig() => plugin.get("config").then((response) => response["config"]);

  Future<Map<String, dynamic>> get config => getConfig();

  /**
   * [target] is where to send the message if the node is not matched.
   * [callback] is not called if the [user] has no permissions.
   */
  void permission(void callback(Map data), String network, String target, String user, String node, [bool notify]) {
    Map params = {
      "node": node,
      "network": network,
      "nick": user,
      "target": target,
      "notify": notify
    };
    plugin.get("permission", params).callIf((data) => data['has']).then(callback);
  }

  void message(String network, String target, String message) {
    plugin.send("message", {
      "network": network,
      "message": message,
      "target": target
    });
  }

  Future<List<String>> getPlugins() {
    return plugin.get("plugins").then((data) => data['plugins']);
  }

  Future<List<String>> getNetworks() {
    return plugin.get("networks").then((data) => data['networks']);
  }

  void notice(String network, String target, String message) {
    plugin.send("notice", {
      "network": network,
      "message": message,
      "target": target
    });
  }

  void onMessage(MessageHandler handler, {Pattern pattern}) {
    var sub = plugin.on("message").where((data) {
      if (pattern != null) {
        return data['message'].allMatches(pattern).isNotEmpty;
      }
      return true;
    }).map((it) {
      var network = it["network"];
      var target = it["target"];
      var from = it["from"];
      var private = it["private"];
      var message = it["message"];

      return new MessageEvent(this, network, target, from, private, message);
    }).listen((event) {
      handler(event);
    });

    plugin.registerSubscription(sub);
  }
  
  void onJoin(JoinHandler handler, {String channel, String user, String network}) {
    var sub = plugin.on("join").where((data) {
      bool matches = true;
      if (channel != null && channel != data["channel"]) {
        matches = false;
      }
      
      if (network != null && network != data["network"]) {
        matches = false;
      }
      
      if (user != null && user != data["user"]) {
        matches = false;
      }
      
      return matches;
    }).listen((data) {
      String network = data['network'];
      String user = data['user'];
      String channel = data['channel'];
      
      var event = new JoinEvent(this, network, channel, user);
      
      handler(event);
    });
    
    plugin.registerSubscription(sub);
  }
  
  void onPart(PartHandler handler, {String channel, String user, String network}) {
    var sub = plugin.on("part").where((data) {
      bool matches = true;
      if (channel != null && channel != data["channel"]) {
        matches = false;
      }
      
      if (network != null && network != data["network"]) {
        matches = false;
      }
      
      if (user != null && user != data["user"]) {
        matches = false;
      }
      
      return matches;
    }).listen((data) {
      String network = data['network'];
      String user = data['user'];
      String channel = data['channel'];
      
      var event = new PartEvent(this, network, channel, user);
      
      handler(event);
    });
    
    plugin.registerSubscription(sub);
  }
  
  void onBotJoin(BotJoinHandler handler, {String network, String channel}) {
    var sub = plugin.on("bot-join").where((data) {
      bool matches = true;
      
      if (channel != null && channel != data["channel"]) {
        matches = false;
      }
      
      if (network != null && network != data["network"]) {
        matches = false;
      }
      
      return matches;
    }).listen((data) {
      String network = data['network'];
      String channel = data['channel'];
      
      var event = new BotJoinEvent(this, network, channel);
      
      handler(event);
    });
    
    plugin.registerSubscription(sub);
  }
  
  void onBotPart(BotPartHandler handler, {String network, String channel}) {
    var sub = plugin.on("bot-part").where((data) {
      bool matches = true;
      
      if (channel != null && channel != data["channel"]) {
        matches = false;
      }
      
      if (network != null && network != data["network"]) {
        matches = false;
      }
      
      return matches;
    }).listen((data) {
      String network = data['network'];
      String channel = data['channel'];
      
      var event = new BotPartEvent(this, network, channel);
      
      handler(event);
    });
    
    plugin.registerSubscription(sub);
  }
  
  Future<List<CommandInfo>> getCommands([String pluginName]) {
    return plugin.get(pluginName != null ? "plugin-commands" : "command-info", pluginName != null ? {
      "plugin": pluginName
    } : {}).then((response) {
      if (response == null) {
        return null;
      }
      
      var infos = [];
      
      for (var key in response.keys) {
        var i = response[key];
        infos.add(new CommandInfo(i["plugin"], key, i["usage"], i["description"]));
      }
      
      return infos;
    });
  }
  
  Future<bool> doesCommandExist(String name) {
    return plugin.get("command-exists", {
      "command": name
    }).then((response) {
      return response["exists"];
    });
  }

  Future<CommandInfo> getCommand(String name) {
    return plugin.get("command-info", {
      "command": name
    }).then((response) {
      if (response == null) {
        return null;
      }
      
      var i = response;
      return new CommandInfo(i["plugin"], name, i["usage"], i["description"]);
    });
  }
  
  void command(String name, CommandHandler handler) {
    var sub = plugin.on("command").where((data) => data['command'] == name).listen((data) {
      var command = data['command'];
      var args = data['args'];
      var user = data['from'];
      var channel = data['target'];
      var network = data['network'];
      var message = data['message'];

      handler(new CommandEvent(this, network, command, message, user, channel, args));
    });

    plugin.registerSubscription(sub);
  }
}

typedef void PluginEventHandler(String plugin, Map<String, dynamic> data);

class Plugin {
  final String name;
  final SendPort _port;

  Plugin(this.name, this._port);

  Receiver _conn;
  BotConnector _bot;
  List<StreamSubscription> _subs = [];
  StreamSubscription _eventSub;
  List<ShutdownAction> _shutdown = [];
  Map<String, StreamController> _controllers = {};
  List<Storage> _storages = [];
  Map<String, RemoteCallHandler> _methods = {};
  List<PluginEventHandler> _pluginEventHandlers = [];

  bool _isShutdown = false;

  void disable() => _eventSub.pause();
  void enable() => _eventSub.resume();

  Stream<Map<String, dynamic>> on(String name) {
    _init();
    
    if (!_controllers.containsKey(name)) {
      _controllers[name] = new StreamController.broadcast();
    }

    return _controllers[name].stream;
  }
  
  void onShutdown(ShutdownAction action) {
    _init();
    
    _shutdown.add(action);
  }
  
  void registerSubscription(StreamSubscription sub) {
    _init();
    
    _subs.add(sub);
  }
  
  void _handleEvent(Map<String, dynamic> data) {
    _init();
    
    if (_isShutdown) {
      return;
    }

    String name = data['event'];

    if (_controllers.containsKey(name)) _controllers[name].add(data);
  }
  
  void _init() {
    if (_conn == null) {
      _conn = new Receiver(_port);
      
      _eventSub = _conn.listen((it) {
        _handleEvent(it);
      });
      
      var sub;
      sub = on("shutdown").listen((_) {
        for (var action in _shutdown) {
          action();
        }

        for (var controller in _controllers.values) {
          controller.close();
        }

        _eventSub.cancel();

        for (var s in _subs) {
          s.cancel();
        }

        sub.cancel();

        _isShutdown = true;
      });
      
      _conn.listenIntercom((plugin, data) {
        for (var handler in _pluginEventHandlers) {
          handler(plugin, data);
        }
      });
      
      _conn.listenRequest((request) {
        if (!request.command.startsWith("__") && _methods.containsKey(request.command)) {
          _methods[request.command](new RemoteCall(request));
        }
        
        if (request.command == "__getRemoteMethods") {
          request.reply({
            "methods": _methods.keys
          });
        }
      });
    }
    
    if (_bot == null) {
      _bot = new BotConnector(this);
    }
  }
  
  Storage getStorage(String storageName, {String group}) {
    _init();
    
    if (group == null) group = name;
    
    var file = new File("data/${group}/${storageName}.json");
    file.parent.createSync(recursive: true);

    var storage = new Storage(file);
    _storages.add(storage);
    return storage;
  }
  
  void addRemoteMethod(String name, RemoteCallHandler handler) {
    _init();
    
    _methods[name] = handler;
  }
  
  void onPluginEvent(PluginEventHandler handler, {String plugin}) {
    _init();
    
    _pluginEventHandlers.add((name, data) {
      if (plugin == null || name == plugin) {
        handler(name, data);
      }
    });
  }
  
  ConditionalFuture<Map<String, dynamic>> get(String command, [Map<String, dynamic> data]) {
    _init();
    
    if (data == null) data = {};
    return _conn.get(command, data);
  }
  
  void log(String message) {
    _init();
    
    print("[${name}] ${message}");
  }
  
  void send(String command, Map<String, dynamic> data, {String plugin}) {
    _init();
    
    var request = {
      "command": command
    };

    request.addAll(data);

    if (plugin != null) {
      _conn.intercom(plugin, request);
    } else {
      _conn.send(request);
    }
  }

  BotConnector getBot() {
    _init();
    return _bot;
  }
}

class RemoteCall {
  final Request request;
  
  RemoteCall(this.request);
  
  dynamic getArgument(String name, {dynamic defaultValue}) => request.data.containsKey(name) ? request.data[name] : defaultValue;
  void reply(dynamic value) => request.reply({
    "value": value
  });
  
  void replyMap(Map<String, dynamic> map) => request.reply(map);
}