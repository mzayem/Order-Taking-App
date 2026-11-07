// A tiny stand-in for softifex_api, running inside the test process on the
// phone/emulator (127.0.0.1, random port). It follows the same contract the
// app uses, so server-dependent flows can be tested for real:
//
//   POST /api/Products/batchCheck          200 = this customer bought this
//                                          batch of this product, else 400
//   POST /api/Transaction/createTransaction 200 / 207 (partial) / 400
//   POST /api/Notification/getNotifications
//   POST /api/Notification/markRead
//
// Every request is recorded so tests can check what the app really sent.

import 'dart:convert';
import 'dart:io';

typedef Call = ({String path, Map<String, dynamic> body, String? auth});

class FakeApi {
  late final HttpServer _server;

  /// Everything the app sent, oldest first.
  final List<Call> requests = [];

  /// "customerId|productId|batch" for every batch that was really sold.
  final Set<String> _sold = {};

  /// Notifications the server returns (newest first). Mutated by markRead.
  List<Map<String, dynamic>> notifications = [];

  /// createTransaction: clientIds the server refuses.
  Set<int> rejectClientIds = {};

  /// When true every route answers 401 (session expired).
  bool unauthorized = false;

  int _serverId = 1000;

  String get baseUrl => 'http://127.0.0.1:${_server.port}';

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen(_handle);
  }

  Future<void> stop() => _server.close(force: true);

  void reset() {
    requests.clear();
    _sold.clear();
    notifications = [];
    rejectClientIds = {};
    unauthorized = false;
  }

  /// Record that [customerId] bought [batch] of [productId].
  void sold(int customerId, int productId, String batch) =>
      _sold.add('$customerId|$productId|$batch');

  Iterable<Call> calls(String pathEnd) =>
      requests.where((r) => r.path.endsWith(pathEnd));

  Future<void> _handle(HttpRequest req) async {
    final raw = await utf8.decodeStream(req);
    final body = raw.isEmpty
        ? <String, dynamic>{}
        : (jsonDecode(raw) as Map).cast<String, dynamic>();
    requests.add((
      path: req.uri.path,
      body: body,
      auth: req.headers.value('authorization'),
    ));

    Future<void> send(int code, Object json) async {
      req.response
        ..statusCode = code
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(json));
      await req.response.close();
    }

    if (unauthorized) return send(401, {'message': 'Unauthorized'});

    switch (req.uri.path) {
      case '/api/Products/batchCheck':
        final key = '${body['customerId']}|${body['productId']}|${body['batchno']}';
        if (_sold.contains(key)) return send(200, {'valid': true});
        return send(400,
            {'message': 'Batch ${body['batchno']} was not sold to this customer'});

      case '/api/Transaction/createTransaction':
        final data = ((body['data'] as List?) ?? const [])
            .map((e) => (e as Map).cast<String, dynamic>())
            .toList();
        final results = [
          for (final d in data)
            if (rejectClientIds.contains(d['clientId']))
              {
                'clientId': d['clientId'],
                'success': false,
                'message': 'Customer is blocked',
              }
            else
              {
                'clientId': d['clientId'],
                'success': true,
                'serverId': _serverId++,
              },
        ];
        final failed = results.where((r) => r['success'] != true).length;
        final code =
            failed == 0 ? 200 : (failed == results.length ? 400 : 207);
        return send(code, {'results': results});

      case '/api/Notification/getNotifications':
        return send(200, {
          'unread': notifications.where((n) => n['unread'] == true).length,
          'notifications': notifications,
        });

      case '/api/Notification/markRead':
        final id = body['notificationId'];
        for (final n in notifications) {
          if (id == null || n['id'] == id) n['unread'] = false;
        }
        return send(200, {});

      default:
        return send(404, {'message': 'not found: ${req.uri.path}'});
    }
  }
}
