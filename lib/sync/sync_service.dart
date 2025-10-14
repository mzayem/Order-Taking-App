// lib/sync/sync_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;

/// Lightweight sync service -- adapts easily once you provide real API contract.
class SyncService {
  final String baseUrl;
  SyncService(this.baseUrl);

  /// Upload a single transaction payload to the server.
  /// Expected to return { 'ok': true, 'remoteId': 123 } on success.
  Future<Map<String, dynamic>> uploadTransaction(
      int localTransactionId, Map<String, dynamic> payload) async {
    if (baseUrl.isEmpty) return {'ok': false, 'error': 'No API URL configured'};

    try {
      final uri = Uri.parse('$baseUrl/transactions'); // adapt to your API path
      final resp = await http.post(uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(payload));
      if (resp.statusCode == 200 || resp.statusCode == 201) {
        final body = resp.body.isNotEmpty ? jsonDecode(resp.body) : {};
        final remoteId = body['id'] ?? body['transaction_id'];
        return {'ok': true, 'remoteId': remoteId};
      } else {
        return {'ok': false, 'error': 'HTTP ${resp.statusCode}: ${resp.body}'};
      }
    } catch (e) {
      return {'ok': false, 'error': e.toString()};
    }
  }
}
