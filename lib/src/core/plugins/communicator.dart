part of polymorphic.bot;

typedef PluginRequestHandler(String plugin, Request request);

class PluginCommunicator {
  final CoreBot bot;
  final PluginHandler handler;

  PluginManager get pm => handler.pm;

  PluginCommunicator(this.bot, this.handler) {
    _handleEventListeners();
  }

  initialStart() async {
    if (bot.config["http"] == null || bot.config["http"]["port"] == null) {
      print("[HTTP] ERROR: No HTTP Port Configured.");
      exit(1);
    }

    var host = bot.config["http"]["host"] != null ? bot.config["http"]["host"] : "0.0.0.0";
    var port = bot.config["http"]["port"];

    var server = await HttpServer.bind(host, port);

    server.listen((HttpRequest request) {
      var segments = request.uri.pathSegments;

      if (segments.length >= 2 && (["plugin", "p", "script", "scripts", "endpoints"].contains(segments[0])) && _httpPorts.containsKey(segments[1])) {
        var name = segments[1];
        var segs = []
          ..addAll(segments)
          ..removeAt(0)
          ..removeAt(0);
        var path = "/" + segs.join("/");
        var target = request.uri.replace(
          scheme: "http",
          host: InternetAddress.ANY_IP_V4.address,
          port: _httpPorts[name],
          path: path
        );

        HttpHelper.forward(request, target);
        return;
      }

      var response = request.response;

      if (request.uri.path.trim() == "/plugins.json") {
        if (request.method != "GET") {
          response.statusCode = HttpStatus.METHOD_NOT_ALLOWED;
          response.writeln("ERROR: Only GET is allowed here.");
          response.close();
        } else {
          response.statusCode = 200;
          response.writeln(encodeJSON(pm.plugins));
          response.close();
        }
      } else if (request.uri.path.trim() == "/kill") {
        if (request.headers.value("Polymorphic-Key") == Globals.key) {
          Globals.kill();
          response.statusCode = 200;
          response.writeln("Success");
          response.close();
        } else {
          response.statusCode = 403;
          response.writeln("Not Allowed");
          response.close();
        }
      } else if (request.uri.path.trim() == "/reload") {
        if (request.headers.value("Polymorphic-Key") == Globals.key) {
          handler.reloadPlugins();
          response.statusCode = 200;
          response.writeln("Success");
          response.close();
        } else {
          response.statusCode = 403;
          response.writeln("Not Allowed");
          response.close();
        }
      } else {
        response.statusCode = 404;
        response.writeln("ERROR: 404 not found.");
        response.close();
      }
    });
  }

  Map<String, Polymorphic.RemoteCallHandler> _methods = {};
  Map<String, Polymorphic.RemoteMethodInfo> _methodInfo = {};

  void addBotMethod(String name, Polymorphic.RemoteCallHandler handler, {Map<String, dynamic> metadata: const {}, bool isVoid: false}) {
    _methods[name] = handler;
    _methodInfo[name] = new Polymorphic.RemoteMethodInfo(name, metadata: metadata, isVoid: isVoid);
  }

  JsonEncoder _jsonEncoder = new JsonEncoder.withIndent("  ");

  String encodeJSON(obj) {
    return _jsonEncoder.convert(obj);
  }

  Map<String, int> _httpPorts = {};

  void handle() {
    _addBotMethods();
    _handleRequests();

    pm.sendAll({
      "type": "event",
      "event": "initialize"
    });

    pm.listenAll((plugin, data) {
      /* We don't use this anymore, everything is a method call */
    });
  }

  void _addBotMethods() {
    String getPluginName() => Zone.current["bot.plugin.method.plugin"];

    addBotMethod("__initialized", (call) {
      /* Plugin was initialized */
      var name = getPluginName();
      pm.sendAll({
        "type": "event",
        "event": "plugin-initialized",
        "plugin": name
      });
      _initialized.add(getPluginName());
      _checkInitialized();
    }, isVoid: true);

    addBotMethod("getNetworks", (call) {
      call.reply(bot.bots);
    });

    addBotMethod("getConfig", (call) {
      call.reply(bot.config);
    });

    addBotMethod("getVersion", (call) {
      call.reply(Globals.version);
    });

    addBotMethod("makePluginRequest", (call) {
      var plugin = call.getArgument("plugin");
      var command = call.getArgument("command");
      var data = call.getArgument("data");

      pm.get(plugin, command, data).then((response) {
        call.request.reply(response);
      });
    });

    addBotMethod("getPlugins", (call) {
      call.reply(pm.plugins.toList());
    });

    addBotMethod("getBotNickname", (call) {
      call.reply(bot[call.getArgument("value")].client.nickname);
    });

    addBotMethod("isUserABot", (call) {
      var network = call.getArgument('network');
      var user = call.getArgument('user');
      bot[network].isUserBot(user).then((isBot) {
        call.reply(isBot);
      });
    });

    addBotMethod("restart", (call) {
      bot.restart();
    });

    addBotMethod("doesCommandExist", (call) {
      var name = call.getArgument("value");

      List<String> cmdNames = [];

      for (var pluginName in pm.plugins) {
        var plugin = pm.plugin(pluginName);

        var pubspec = plugin.pubspec;

        if (pubspec['plugin'] == null || pubspec['plugin']['commands'] == null) {
          call.reply(null);
        } else {
          Map<String, Map<String, dynamic>> commands = pubspec['plugin']['commands'];

          for (var name in commands.keys) {
            cmdNames.add(name);
          }
        }
      }

      var exists = cmdNames.contains(name);

      call.reply(exists);
    });

    addBotMethod("forwardHttpPort", (call) {
      var port = call.getArgument("value");

      _httpPorts[getPluginName()] = port;
    }, isVoid: true);

    addBotMethod("getPrefix", (call) {
      var network = call.getArgument("network");
      var channel = call.getArgument("channel");

      var prefix = bot[network].getPrefixes(channel);

      if (prefix is Pattern) {
        prefix = "${bot[network].client.nickname}: ";
      }

      call.reply(prefix);
    });

    addBotMethod("unforwardHttpPort", (call) {
      _httpPorts.remove(getPluginName());
    }, isVoid: true);

    addBotMethod("getCommandInfo", (Polymorphic.RemoteCall call) {
      if (call.getArgument("plugin") != null) {
        pm.get(call.getArgument("plugin"), "__getRegisteredCommands", {}).then((result) {
          call.reply(result["value"]);
        });
      } else if (call.getArgument("command") != null) {
        var allCommands = {};
        var group = new FutureGroup();

        for (var p in pm.plugins) {
          group.add(pm.get(p, "__getRegisteredCommands", {}).then((result) {
            return result["value"];
          }));
        }

        group.future.then((all) {
          for (var a in all) {
            for (var c in a) {
              allCommands[c["name"]] = c;
            }
          }

          call.reply(allCommands[call.getArgument("command")]);
        });
      } else {
        var allCommands = {};
        var group = new FutureGroup();

        for (var p in pm.plugins) {
          group.add(pm.get(p, "__getRegisteredCommands", {}).then((result) {
            return result["value"];
          }));
        }

        group.future.then((all) {
          for (var a in all) {
            for (var c in a) {
              allCommands[c["name"]] = c;
            }
          }

          call.reply(allCommands);
        });
      }
    });

    addBotMethod("getChannelBuffer", (call) {
      var network = call.getArgument("network");
      var channel = call.getArgument("channel");

      call.reply(Buffer.get("${network}${channel}").map((it) {
        return it.toData();
      }).toList());
    });

    addBotMethod("appendChannelBuffer", (call) {
      var network = call.getArgument("network");
      var from = call.getArgument("from");
      var target = call.getArgument("target");
      var message = call.getArgument("message");
      Buffer.handle(network, new IRC.MessageEvent(bot[network].client, from, target, message));
    });

    addBotMethod("checkPermission", (call) {
      var node = call.getArgument('node');
      var net = call.getArgument('network');
      var user = call.getArgument('user');
      var target = call.getArgument('target');
      var notify = call.getArgument("notify", defaultValue: true);

      bot[net].authManager.hasPermission(getPluginName(), user, node).then((bool has) {
        if (!has) {
          var b = bot[net];
          if (notify == null || notify) {
            b.client.sendMessage(target, "$user> You are not authorized to perform this action (missing ${getPluginName()}.${node})");
          }
        }
        call.reply(has);
      });
    });

    addBotMethod("hasPermission", (call) {
      var plugin = call.getArgument("plugin");
      var node = call.getArgument("node");
      var network = call.getArgument("network");
      var user = call.getArgument("user");

      bot[network].authManager.hasPermission(plugin, user, node).then((bool has) {
        call.reply(has);
      });
    });

    addBotMethod("getUsername", (call) {
      var network = call.getArgument("network");
      var user = call.getArgument("user");

      var b = bot[network];

      if (b.authManager._authenticated.containsKey(user)) {
        call.reply(b.authManager._authenticated[user]);
      } else {
        b.client.whois(user).then((info) {
          call.reply(info.username != null ? info.username : user);
        });
      }
    });

    addBotMethod("isUserAway", (call) {
      var network = call.getArgument("network");
      var user = call.getArgument("user");

      var b = bot[network];

      b.client.whois(user).then((info) {
        call.reply(info.away);
      });
    });

    addBotMethod("getRealName", (call) {
      var network = call.getArgument("network");
      var user = call.getArgument("user");

      var b = bot[network];

      b.client.whois(user).then((info) {
        call.reply(info.realname);
      });
    });

    addBotMethod("getAwayMessage", (call) {
      var network = call.getArgument("network");
      var user = call.getArgument("user");

      var b = bot[network];

      b.client.whois(user).then((info) {
        call.reply(info.awayMessage);
      });
    });

    addBotMethod("executeCommand", (call) {
      var network = call.getArgument("network");
      var channel = call.getArgument("channel");
      var user = call.getArgument("user");
      var command = call.getArgument("command");
      var args = call.getArgument("args");
      var client = bot[network].client;
      var b = bot[network];
      var message = "${b.getPrefixes(channel)}${command}${args.isNotEmpty ? ' ' + args.join(' ') : ""}";
      client.post(new IRC.CommandEvent(new IRC.MessageEvent(client, user, channel, message), command, args));
    }, isVoid: true);

    addBotMethod("getChannel", (call) {
      var net = call.getArgument('network');
      var chan = call.getArgument('channel');
      var channel = bot._clients[net].client.getChannel(chan);

      if (channel == null) {
        call.reply(null);
        return;
      }

      call.reply({
        "name": channel.name,
        "ops": channel.ops,
        "voices": channel.voices,
        "members": channel.members,
        "owners": channel.owners,
        "halfops": channel.halfops,
        "topic": channel.topic,
        "topicUser": channel.topicUser
      });
    });

    addBotMethod("isInChannel", (call) {
      var network = call.getArgument("network");
      var channel = call.getArgument("channel");

      call.reply(bot[network].client.channels.any((it) => it.name == channel));
    });

    addBotMethod("changeBotNickname", (call) {
      var network = call.getArgument("network");
      var nick = call.getArgument("nickname");

      bot[network].client.changeNickname(nick);
    }, isVoid: true);

    addBotMethod("listChannels", (call) {
      var network = call.getArgument("network");

      call.reply(bot[network].client.channels.map((it) => it.name).toList());
    });

    addBotMethod("getChannelUsers", (call) {
      var network = call.getArgument("network");
      var channel = call.getArgument("channel");

      call.reply(bot[network].client.getChannel(channel).allUsers);
    });

    addBotMethod("setChannelTopic", (call) {
      var network = call.getArgument("network");
      var channel = call.getArgument("channel");
      var topic = call.getArgument("topic");

      bot[network].client.setChannelTopic(channel, topic);
    }, isVoid: true);

    addBotMethod("getChannelTopic", (call) {
      var network = call.getArgument("network");
      var channel = call.getArgument("channel");

      bot[network].client.getChannelTopic(channel).then((topic) {
        call.reply(topic);
      });
    });

    addBotMethod("getChannelMembers", (call) {
      var network = call.getArgument("network");
      var channel = call.getArgument("channel");

      call.reply(bot[network].client.getChannel(channel).members);
    });

    addBotMethod("getChannelVoices", (call) {
      var network = call.getArgument("network");
      var channel = call.getArgument("channel");

      call.reply(bot[network].client.getChannel(channel).voices);
    });

    addBotMethod("getChannelOps", (call) {
      var network = call.getArgument("network");
      var channel = call.getArgument("channel");

      call.reply(bot[network].client.getChannel(channel).ops);
    });

    addBotMethod("getChannelOwners", (call) {
      var network = call.getArgument("network");
      var channel = call.getArgument("channel");

      call.reply(bot[network].client.getChannel(channel).owners);
    });

    addBotMethod("getChannelHalfOps", (call) {
      var network = call.getArgument("network");
      var channel = call.getArgument("channel");

      call.reply(bot[network].client.getChannel(channel).halfops);
    });

    addBotMethod("whois", (call) {
      var net = call.getArgument('network');
      var user = call.getArgument('user');
      bot[net].client.whois(user).then((event) {
        var memberIn = () {
          var list = <String>[];
          list.addAll(event.builder.channels.where((i) =>
            !event.builder.opIn.contains(i) &&
            !event.builder.voiceIn.contains(i) &&
            !event.builder.halfOpIn.contains(i) &&
            !event.builder.ownerIn.contains(i)
          ));
          return list;
        }();

        call.reply({
          "away": event.away,
          "awayMessage": event.awayMessage,
          "isServerOperator": event.isServerOperator,
          "hostname": event.hostname,
          "idle": event.idle,
          "idleTime": event.idleTime,
          "memberIn": memberIn,
          "operatorIn": event.builder.opIn,
          "channels": event.builder.channels,
          "ownerIn": event.builder.ownerIn,
          "halfOpIn": event.builder.halfOpIn,
          "voiceIn": event.builder.voiceIn,
          "nickname": event.builder.nickname,
          "realname": event.builder.realname,
          "username": event.builder.username
        });
      });
    });

    addBotMethod("kick", (call) {
      var user = call.getArgument("user");
      var channel = call.getArgument("channel");
      var network = call.getArgument("network");
      var reason = call.getArgument("reason");

      bot[network].client.kick(bot[network].client.getChannel(channel), user, reason);
    });

    addBotMethod("setMode", (call) {
      var user = call.getArgument("user");
      var channel = call.getArgument("channel");
      var network = call.getArgument("network");
      var mode = call.getArgument("mode");

      if (channel == null) {
        if (user != null) {
          bot[network].client.setMode(mode, user: user);
        } else {
          bot[network].client.setMode(mode);
        }
      } else {
        if (user != null) {
          bot[network].client.getChannel(channel).setMode(mode, user);
        } else {
          bot[network].client.getChannel(channel).setMode(mode);
        }
      }
    }, isVoid: true);

    addBotMethod("sendMessage", (call) {
      var network = call.getArgument("network");
      var target = call.getArgument("target");
      var message = call.getArgument("message");
      var ping = call.getArgument("ping");

      var b = bot[network];

      if (ping != null) {
        if (b.isSlackBot) {
          message = "@${ping}: ${message}";
        } else {
          message = "${ping}: ${message}";
        }
      }

      bot[network].client.sendMessage(target, message);
    }, isVoid: true);

    addBotMethod("sendNotice", (call) {
      var network = call.getArgument("network");
      var target = call.getArgument("target");
      var message = call.getArgument("message");

      bot[network].client.sendNotice(target, message);
    }, isVoid: true);

    addBotMethod("sendAction", (call) {
      var network = call.getArgument("network");
      var target = call.getArgument("target");
      var message = call.getArgument("message");

      bot[network].client.sendAction(target, message);
    }, isVoid: true);

    addBotMethod("emit", (call) {
      var e = call.getArgument("value");

      pm.sendAll({
        "type": "event"
      }..addAll(e));
    }, isVoid: true);

    addBotMethod("fakeMessage", (call) {
      var e = call.getArgument("value");
      var network = e["network"];
      var user = e["user"];
      var target = e["target"];
      var message = e["message"];
      var event = new IRC.MessageEvent(bot[network].client, user, target, message);
      bot[network].client.post(event);
    });

    addBotMethod("getMOTD", (call) {
      var network = call.getArgument("network");

      call.reply(bot[network].client.motd);
    });

    addBotMethod("getSupported", (call) {
      var network = call.getArgument("network");

      call.reply(bot[network].client.supported);
    });

    addBotMethod("getNetworkName", (call) {
      var network = call.getArgument("network");

      call.reply(bot[network].client.networkName);
    });

    addBotMethod("isConnected", (call) {
      var network = call.getArgument("network");

      call.reply(bot[network].client.connected);
    });

    addBotMethod("getLastCommand", (call) {
      var network = call.getArgument("network");
      var channel = call.getArgument("channel");
      var not = call.getArgument("not");
      var user = call.getArgument("user");

      var buff = Buffer.get("${network}${channel}");

      var b = bot[network];

      for (var e in buff) {
        var p = b.getMessagePrefix(channel, e.message);
        if (p != null) {
          var m = e.message.substring(p.length);
          if (not != null && (m.trim() == not || m.trim().startsWith("${not} ")) || (user != null && user != e.user)) {
            continue;
          }

          call.reply(e.message.substring(p.length));
          return;
        }
      }

      call.reply(null);
    });

    addBotMethod("sendCTCP", (call) {
      var network = call.getArgument("network");
      var target = call.getArgument("target");
      var message = call.getArgument("message");

      bot[network].client.sendCTCP(target, message);
    }, isVoid: true);

    addBotMethod("joinChannel", (call) {
      var network = call.getArgument("network");
      var channel = call.getArgument("channel");

      bot[network].client.join(channel);
    }, isVoid: true);

    addBotMethod("partChannel", (call) {
      var network = call.getArgument("network");
      var channel = call.getArgument("channel");

      bot[network].client.part(channel);
    }, isVoid: true);

    addBotMethod("isUserOn", (call) {
      var network = call.getArgument("network");
      var user = call.getArgument("user");

      bot[network].client.isUserOn(user).then((isOn) {
        call.reply(isOn);
      });
    });

    addBotMethod("clearBotMemory", (call) {
      var network = call.getArgument("network");

      bot[network].clearBotMemory();
    }, isVoid: true);

    addBotMethod("sendRawLine", (call) {
      var network = call.getArgument("network");
      var line = call.getArgument("line");

      bot[network].client.send(line);
    }, isVoid: true);

    addBotMethod("reloadPlugins", (call) {
      handler.reloadPlugins();
    }, isVoid: true);

    addBotMethod("quit", (call) {
      var network = call.getArgument("network");
      var reason = call.getArgument("reason", defaultValue: "Bot Quitting");

      bot[network].client.disconnect(reason: reason);
    }, isVoid: true);

    addBotMethod("stop", (call) {
      var futures = [];

      for (var botname in bot.bots) {
        var completer = new Completer();
        futures.add(completer.future);
        var it = bot._clients[botname];
        it.client.pollEvent(IRC.DisconnectEvent).then((_) {
          completer.complete();
        });
        it.client.disconnect();
      }

      Future.wait(futures).then((_) {
        handler.killPlugins();
        exit(0);
      });

      new Future.delayed(new Duration(seconds: 5), () {
        exit(0);
      });
    }, isVoid: true);
  }

  Completer _completer;

  void _checkInitialized() {
    var names = handler.pm.plugins.toList();
    if (names.every((x) => _initialized.contains(x))) {
      debug(() => print("[Plugin Manager] All Plugins have been initialized."));
      pm.sendAll({
        "type": "event",
        "event": "plugins-initialized"
      });
      if (_completer != null && !_completer.isCompleted) {
        _completer.complete();
      }
    }
  }

  List<String> _initialized = [];

  void _handleRequests() {
    pm.listenAllRequest((plugin, request) {
      if (_methods.containsKey(request.command)) {
        var handler = _methods[request.command];
        var call = new Polymorphic.RemoteCall(request);
        Zone.current.fork(specification: new ZoneSpecification(handleUncaughtError:
          (Zone self, ZoneDelegate parent, Zone zone, error, StackTrace stackTrace) {
            pm.send(plugin, {
              "exception": {
                "message": "Error while calling method '${request.command}' for '${plugin}' \n\n${error}"
              }
            });
        }), zoneValues: {
          "bot.plugin.method.plugin": plugin
        }).run(() {
          try {
            handler(call);

            if (_methodInfo[request.command].isVoid) {
              call.reply(null);
            }
          } catch (e) {
            call.error("Error while calling method '${request.command}' for '${plugin}'\n\n${e}");
          }
        });
      } else {
        var call = new Polymorphic.RemoteCall(request);
        call.error("The plugin '${plugin}' tried to call the method '${request.command}', however it does not exist.");
      }
    });
  }

  void _handleEventListeners() {
    bot.bots.forEach((String network) {
      var nel = new IrcEventListener(network, this);
      nel.handle();
    });
  }
}

class TimedEntry<T> {
  Timer timer;
  final T value;

  TimedEntry(this.value);

  TimedEntry<T> start(int dur, void handleTimeout()) {
    timer = new Timer(new Duration(seconds: dur), handleTimeout);
    return this;
  }
}
