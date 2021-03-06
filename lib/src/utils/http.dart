part of polymorphic.utils;

class HttpHelper {
  static Future notFound(HttpRequest request) {
    var response = request.response;
    response.statusCode = 404;
    response.writeln("ERROR: Not Found.");
    return response.close();
  }
  
  static Future forward(HttpRequest request, Uri target) {
    debug(() => print("Forwarding ${request.uri} to ${target}"));
    
    var response = request.response;
    var client = new HttpClient();
    
    return client.openUrl(request.method, target).then((req) {
      request.cookies.addAll(req.cookies);
      request.headers.forEach((name, value) {
        for (var v in value) {
          req.headers.add(name, v);
        }
      });

      return request.pipe(req);
    }).then((HttpClientResponse res) {
      // Special Handling for WebSockets
      if (res.statusCode == HttpStatus.SWITCHING_PROTOCOLS) {
        return proxyWebSocket(request, res);
      }

      response.statusCode = res.statusCode;

      res.headers.forEach((name, value) {
        for (var v in value) {
          response.headers.add(name, v);
        }
      });

      response.cookies.addAll(res.cookies);

      return res.pipe(response);
    }).then((_) {
      client.close();
    }).catchError((e, stack) {
      print(e);
      print(stack);
      
      response.statusCode = 500;
      response.writeln("Internal Server Error");
      return response.close();
    });
  }

  static Future proxyWebSocket(HttpRequest request, HttpClientResponse response) {
    WebSocket requestSocket;
    WebSocket responseSocket;

    return WebSocketTransformer.upgrade(request).then((socket) {
      requestSocket = socket;
      return response.detachSocket();
    }).then((socket) {
      return new WebSocket.fromUpgradedSocket(socket, serverSide: false);
    }).then((socket) {
      responseSocket = socket;

      return WebSocketHelper.proxy(requestSocket, responseSocket);
    });
  }
  
  static String buildQueryString(Map<String, String> query) {
    if (query == null) {
      return "";
    }
    
    var m = "?";
    var first = true;
    for (var x in query.keys) {
      m += "${first ? "" : "&"}${x}=${Uri.encodeComponent(query[x])}";
      first = false;
    }
    return m;
  }
}

class WebSocketHelper {
  static Future echo(WebSocket socket) {
    return socket.listen((data) {
      socket.add(data);
    }).asFuture();
  }
  
  static Future transform(WebSocket client, StreamTransformer transformer) {
    return transformer.bind(client).listen((out) {
      client.add(out);
    }).asFuture();
  }

  static Future proxy(WebSocket client, WebSocket target) {
    var completer = new Completer();

    client.listen((data) {
      target.add(data);
    });

    target.listen((data) {
      client.add(data);
    });

    target.done.then((_) {
      return client.close(target.closeCode, target.closeReason);
    }).then((_) {
      if (!completer.isCompleted) {
        completer.complete();
      }
    });

    client.done.then((_) {
      return target.close(client.closeCode, client.closeReason);
    }).then((_) {
      if (!completer.isCompleted) {
        completer.complete();
      }
    });

    return completer.future;
  }
}
