part of polymorphic.api;

/**
 * A Command Event.
 */
class CommandEvent {
  /**
   * The Bot
   */
  final BotConnector bot;
  
  /**
   * Network
   */
  final String network;
  
  /**
   * Command
   */
  final String command;
  
  /**
   * Message
   */
  final String message;
  
  /**
   * User
   */
  final String user;
  
  /**
   * Channel
   */
  final String channel;
  
  /**
   * Command Arguments
   */
  final List<String> args;

  CommandEvent(this.bot, this.network, this.command, this.message, this.user, this.channel, this.args);
  
  /**
   * Sends [message] as a message to [channel] on [network].
   *
   * If [prefix] is prefixed with [prefixContent].
   * If [prefixContent] is empty it becomes the display name of this plugin.
   */
  void reply(String message, {bool prefix, String prefixContent}) {
    if (prefix || (prefix == null && prefixContent != null)) {
      if (prefixContent == null) {
        prefixContent = bot.plugin.displayName;
      }

      message = "[${Color.BLUE}${prefixContent}${Color.RESET}] ${message}";
    }

    bot.sendMessage(network, channel, message);
  }

  /**
   * Calls [handle] if [user] has [permission].
   */
  void require(String permission, void handle()) {
    bot.checkPermission((it) => handle(), network, channel, user, permission);
  }

  /**
   * Joins the arguments by [sep].
   */
  String joinArgs([String sep = " "]) => args.join(sep);
  
  String joinArguments([String sep = " "]) => joinArgs(sep);

  bool get hasArguments => args.isNotEmpty;
  bool get hasNoArguments => args.isEmpty;
  bool get hasOneArgument => argc == 1;
  int get argc => args.length;

  /**
   * Replies with the command's usage. If you did not specify a usage it will output '> Usage: command-name'
   */
  void usage() {
    var cmd = bot._myCommands.firstWhere((it) => it.name == command);
    if (cmd.usage != null && cmd.usage.isNotEmpty) {
      var needCmd = !cmd.usage.startsWith(command);
      reply("> Usage: ${needCmd ? '${command} ' : ''}${cmd.usage}");
    }
  }
  
  void executeCommand(String command, [List<String> args = const []]) {
    bot.executeCommand(network, channel, user, command, args);
  }
  
  dynamic chooseAtRandom(List<dynamic> list) {
    return list[new Random().nextInt(list.length)];
  }
  
  List<String> copyArguments() => new List<String>.from(args);
  List<String> dropArguments(int x) {
    var a = copyArguments();
    for (var i = 1; i <= x; i++) {
      a.removeAt(0);
    }
    return a;
  }
  
  String dropJoinArguments(int x, [String sep = " "]) {
    return dropArguments(x).join(sep);
  }
  
  Future<BufferEntry> getLastChannelMessage() {
    return getChannelBuffer().then((entries) => entries.first);
  }
  
  Future<String> getChannelPrefix() {
    return bot.getPrefix(network, channel);
  }
  
  Future<String> getLastCommand([bool userOnly = true]) {
    return getChannelBuffer().then((entries) {
      return getChannelPrefix().then((prefix) {
        return entries.firstWhere((c) =>
            c.network == network &&
            c.target == channel &&
            c.message.startsWith(prefix) &&
            (userOnly ? c.user == user : true),
            orElse: () => null
        );
      });   
    });
  }
  
  Future<List<BufferEntry>> getChannelBuffer() => bot.getChannelBuffer(network, channel);

  StorageContainer getUserMetadata({String user, bool channelSpecific: false}) {
    if (user == null) {
      user = this.user;
    }
    
    return bot.getUserMetadata(network, channel, user, channelSpecific: channelSpecific);
  }
  
  StorageContainer getChannelMetadata() {
    return bot.getChannelMetadata(network, channel);
  }
  
  /**
   * Sends [message] as a message to [channel] on [network].
   *
   * If [prefix] is prefixed with [prefixContent].
   * If [prefixContent] is empty it becomes the display name of this plugin.
   */
  void replyNotice(String message, {bool prefix, String prefixContent}) {
    if (prefix || (prefix == null && prefixContent != null)) {
      if (prefixContent == null) {
        prefixContent = bot.plugin.displayName;
      }

      message = "[${Color.BLUE}${prefixContent}${Color.RESET}] ${message}";
    }

    bot.sendNotice(network, user, message);
  }
  
  /**
   * Replies with the output from [transformer].
   */
  void transform(transformer(String input), {prefix: false, bool notice: false, bool noSign: false}) {
    var p = null;
    if (prefix == true || (prefix != null && prefix is String)) {
      p = prefix == true ? bot.plugin.displayName : prefix;
    }
    
    new Future.value(transformer(joinArgs())).then((value) {
      if (value == null) return;
      
      (notice ? replyNotice : reply)(p != null ? value : "${noSign ? "" : "> "}${value}", prefixContent: p);
    });
  }
  
  Future<dynamic> fetchJSON(String url, {String transform(String input), Map<String, String> headers: const {}, Map<String, String> query}) {
    if (query != null) {
      url += HttpHelper.buildQueryString(query);
    }
    
    return bot.plugin.httpClient.get(url).then((response) {
      if (response.statusCode != 200) {
        throw new HttpException("failed to fetch JSON");
      }
      
      return JSON.decode(transform != null ? transform(response.body) : response.body);
    });
  }
  
  Future<dynamic> postJSON(String url, dynamic body, {Map<String, String> headers: const { "Content-Type": "application/json" }, Map<String, String> query}) {
    if (query != null) {
      url += HttpHelper.buildQueryString(query);
    }
    
    return bot.plugin.httpClient.post(url, body: JSON.encode(body), headers: headers).then((response) {
      if (!([200, 201].contains(response.statusCode))) {
        throw new HttpException("failed to fetch JSON");
      }
      
      return JSON.decode(response.body);
    });
  }
  
  Future<HtmlDocument> fetchHTML(String url, {Map<String, String> headers: const {}, Map<String, String> query}) {
    if (query != null) {
      url += HttpHelper.buildQueryString(query);
    }
    
    return bot.plugin.httpClient.get(url).then((response) {
      if (response.statusCode != 200) {
        throw new HttpException("failed to fetch HTML");
      }
      
      return new HtmlDocument(parseHtml(response.body));
    });
  }
  
  Future<String> getUsername() => whois().then((info) => info.username);
  
  Future<UserInfo> whois() {
    return bot.getUserInfo(network, user);
  }
  
  Future<Channel> getChannel() {
    return bot.getChannel(network, channel);
  }
}

class CommandInfo {
  final String plugin;
  final String name;
  final String usage;
  final String description;

  CommandInfo(this.plugin, this.name, this.usage, this.description);
}
