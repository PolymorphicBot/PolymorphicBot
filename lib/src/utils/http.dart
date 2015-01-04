part of polymorphic.utils;

class HttpHelper {
  static HttpClient client = new HttpClient();

  static void forward(HttpRequest request, String newPath, String host, int port) {
    var response = request.response;
    client.open(request.method, host, port, newPath).then((req) {
      var completer = new Completer();

      request.cookies.addAll(req.cookies);
      request.headers.forEach((name, value) {
        for (var v in value) {
          req.headers.add(name, v);
        }
      });

      request.listen((data) {
        req.add(data);
      }).onDone(() {
        completer.complete(req.close());
      });

      return completer.future;
    }).then((HttpClientResponse res) {
      // Special Handling for WebSockets
      if (res.statusCode == HttpStatus.SWITCHING_PROTOCOLS) {
        return proxyWebSocket(request, res);
      }

      var completer = new Completer();

      response.statusCode = res.statusCode;

      res.headers.forEach((name, value) {
        for (var v in value) {
          response.headers.add(name, v);
        }
      });

      response.cookies.addAll(res.cookies);

      res.listen((data) {
        response.add(data);
      }).onDone(() {
        completer.complete(response.close());
      });

      return completer.future;
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
      
      requestSocket.listen((data) {
        responseSocket.add(data);
      });
      
      responseSocket.listen((data) {
        requestSocket.add(data);
      });
    });
  }
}

class WebSocketHelper {
  static Future echo(WebSocket socket) {
    return socket.listen((data) {
      socket.add(data);
    }).asFuture();
  }
}
