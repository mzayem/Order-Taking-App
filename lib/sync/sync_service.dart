// lib/sync/sync_service.dart
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

/// Sync service for uploading transactions to the API
class SyncService {
  final String baseUrl;
  SyncService(this.baseUrl);

  /// Upload a single transaction payload to the server
  /// Expected to return { 'ok': true, 'remoteId': 123 } on success
  Future<Map<String, dynamic>> uploadTransactions(
      List<Map<String, dynamic>> payloadList) async {
    if (baseUrl.isEmpty) {
      return {'ok': false, 'error': 'No API URL configured'};
    }

    final url = '$baseUrl/transaction_604281180';

    try {
      final httpClient = HttpClient();
      final request = await httpClient.postUrl(Uri.parse(url));

      request.headers.set('content-type', 'application/json');
      request.headers.set('accept', 'application/json');

      request.add(utf8.encode(jsonEncode(payloadList)));
      final response = await request.close();

      final respBody = await response.transform(utf8.decoder).join();
      final respJson = respBody.isNotEmpty ? jsonDecode(respBody) : {};

      if (response.statusCode == 200 || response.statusCode == 201) {
        if (respJson['status'] == 'success') {
          return {'ok': true, 'data': respJson};
        } else {
          return {
            'ok': false,
            'error': respJson['msg'] ?? respJson['message'] ?? 'Upload failed'
          };
        }
      } else if (response.statusCode == 400) {
        return {
          'ok': false,
          'error':
              'Bad Request: ${respJson['msg'] ?? respJson['message'] ?? respBody}'
        };
      } else {
        return {'ok': false, 'error': 'HTTP ${response.statusCode}: $respBody'};
      }
    } catch (e) {
      return {'ok': false, 'error': e.toString()};
    }
  }

  /// Fetch sync data from server
  Future<Map<String, dynamic>> fetchSyncData() async {
    if (baseUrl.isEmpty) {
      return {'ok': false, 'error': 'No API URL configured'};
    }

    try {
      final uri = Uri.parse('$baseUrl/syncdata_604281180');
      final resp = await http.get(
        uri,
        headers: {
          'accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 30));

      if (resp.statusCode == 200) {
        final body = jsonDecode(resp.body);
        if (body['status'] == 'success') {
          return {'ok': true, 'data': body['result']};
        } else {
          return {
            'ok': false,
            'error': body['message'] ?? body['msg'] ?? 'Fetch failed'
          };
        }
      } else {
        return {'ok': false, 'error': 'HTTP ${resp.statusCode}'};
      }
    } catch (e) {
      return {'ok': false, 'error': e.toString()};
    }
  }

  /// Post sync data to server
  Future<Map<String, dynamic>> postSyncData(Map<String, dynamic> data) async {
    if (baseUrl.isEmpty) {
      return {'ok': false, 'error': 'No API URL configured'};
    }

    try {
      final uri = Uri.parse('$baseUrl/syncdata_604281180');
      final resp = await http
          .post(
            uri,
            headers: {
              'content-type': 'application/json', // Lowercase
              'accept': 'application/json',
            },
            body: jsonEncode(data),
          )
          .timeout(const Duration(seconds: 30));

      if (resp.statusCode == 200 || resp.statusCode == 201) {
        final body = jsonDecode(resp.body);
        return {'ok': true, 'data': body};
      } else if (resp.statusCode == 400) {
        final body = resp.body.isNotEmpty ? jsonDecode(resp.body) : {};
        return {
          'ok': false,
          'error': 'Bad Request: ${body['msg'] ?? body['message'] ?? resp.body}'
        };
      } else {
        return {'ok': false, 'error': 'HTTP ${resp.statusCode}'};
      }
    } catch (e) {
      return {'ok': false, 'error': e.toString()};
    }
  }
}
