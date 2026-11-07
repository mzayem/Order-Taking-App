import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../db/database.dart';
import '../login_screen.dart';
import '../main.dart' show navigatorKey;

class ApiService {
  /// -----------------------------
  /// AUTH HEADERS (token from login)
  /// -----------------------------
  static Future<Map<String, String>> headers() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ?? '';
    return {
      'accept': '*/*',
      'Content-Type': 'application/json',
      if (token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  /// Session expired or revoked (password reset / user blocked): drop the
  /// session and go to Login. Local transactions are kept for upload later.
  static Future<void> handleUnauthorized(http.Response response) async {
    if (response.statusCode != 401) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    await prefs.remove('userId');
    navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  /// -----------------------------
  /// CONVERT LOCAL TYPE → API TYPE
  /// -----------------------------
  static int convertType(String type) {
    switch (type) {
      case 'Order':
        return 0;
      case 'Cash':
        return 1;
      case 'Return':
        return 2;
      default:
        return 0;
    }
  }

  /// -----------------------------
  /// FETCH CUSTOMERS
  /// -----------------------------
  static Future<List<String>> fetchCustomers() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final baseUrl = prefs.getString('baseUrl') ?? '';
      final userId = prefs.getString('userId') ?? '';
      final townIds = prefs.getStringList('townIds') ?? [];
      print("baseUrl = $baseUrl");
      print("townIds = $townIds");
      if (baseUrl.isEmpty || userId.isEmpty || townIds.isEmpty) {
        return await _customersFromDB();
      }

      final url = Uri.parse('$baseUrl/api/Customer/customerFetch');

      final response = await http.post(
        url,
        headers: await headers(),
        body: jsonEncode({
          "userId": userId,
          "townIds": townIds.map(int.parse).toList(),
        }),
      );
      await handleUnauthorized(response);
      print("Customer API Status = ${response.statusCode}");
      print("Customer API Body = ${response.body}");
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        final List list = data['customers'] ?? [];

        Set<String> customers = {};

        for (var c in list) {
          // print("API CUSTOMER => $c");

          customers.add(c['customerName'] ?? '');

          await AppDatabase.upsertCustomer({
            'customerId': c['customerId'],
            'customerName': c['customerName'],
            'address': c['address'] ?? '', // FIXED
            'townID': c['townID'],
            'isNarcoticsAllowed': c['isNarcoticsAllowed'] ?? false,
          });

          final db = await AppDatabase.init();

          final row = await db.query(
            'Customer',
            where: 'CustomerID = ?',
            whereArgs: [c['customerId']],
          );

          // if (row.isNotEmpty) {
          //   print("DB CUSTOMER => ${row.first}");
          // }
        }

        return customers.toList();
      }

      return await _customersFromDB();
    } catch (e, stackTrace) {
      print("================================");
      print("Customer Fetch Error");
      print(e);
      print(stackTrace);
      print("================================");

      return await _customersFromDB();
    }
  }

  /// -----------------------------
  /// FETCH PRODUCTS
  /// -----------------------------
  static Future<List<Map<String, dynamic>>> fetchProducts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final baseUrl = prefs.getString('baseUrl') ?? '';
      final userId = prefs.getString('userId') ?? '';

      if (baseUrl.isEmpty) {
        return await _productsFromDB();
      }

      final url = Uri.parse('$baseUrl/api/Products/getProduct');

      final response = await http.post(
        url,
        headers: await headers(),
        body: jsonEncode({
          "userId": userId,
        }),
      );
      await handleUnauthorized(response);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        final List list = data['products'] ?? [];

        Map<String, Map<String, dynamic>> products = {};

        // Product Type from API should be added like Narcotics || Medicine
        for (var p in list) {
          products[p['productName']] = {
            "name": p['productName'],
            "price": (p['latestPrice'] as num).toDouble(),
            "type": p['productType'],
            "availableQty": p['totalQty']
          };

          await AppDatabase.upsertProduct({
            'ProductID': p['productId'],
            'Name': p['productName'],
            'Code': '', // why?
            'UnitPrice': (p['latestPrice'] as num).toDouble(),
            'AvailableQty': p['totalQty'],
            'Type': p['productType'], // need to be added
          });
        }

        return products.values.toList();
      }

      return await _productsFromDB();
    } catch (e) {
      return await _productsFromDB();
    }
  }

  /// ------------------------------------------------------------------
  /// BUILD A SINGLE TRANSACTION PAYLOAD (shared helper)
  /// ------------------------------------------------------------------
  static Future<Map<String, dynamic>?> _buildTransactionPayload(
      int transactionId) async {
    final rows = await AppDatabase.getTransactionWithDetails(transactionId);
    if (rows.isEmpty) return null;

    final header = rows.first;

    final details = <Map<String, dynamic>>[];
    for (var r in rows) {
      if (r['TransactionDetailID'] != null) {
        final unitPrice = (r['UnitPrice'] as num?)?.toDouble() ?? 0.0;
        final qty = (r['Qty'] as num?)?.toInt() ?? 0;
        details.add({
          'productId': r['ProductID'],
          'batchNo': r['BatchNo'] ?? '',
          'qty': qty,
          'unitPrice': unitPrice,
          'totalAmount':
              (r['TotalPrice'] as num?)?.toDouble() ?? unitPrice * qty,
        });
      }
    }

    return {
      'clientId': transactionId.toString(), // local ID used for tracking
      'date': DateTime.now().toUtc().toIso8601String(),
      'customerId': header['CustomerID'] as int,
      'type': convertType(header['Type'] as String),
      'remarks': header['Remarks'] ?? '',
      'totalAmount': (header['TotalAmount'] as num?)?.toDouble() ?? 0.0,
      'transactionDetails': details,
    };
  }

  /// ------------------------------------------------------------------
  /// UPLOAD Multiple TRANSACTION
  /// Wraps the transaction in the `data` array as required by the API.
  /// ------------------------------------------------------------------
  static Future<bool> uploadTransaction(int transactionId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final baseUrl = prefs.getString('baseUrl') ?? '';
      final userId = (prefs.getString('userId') ?? '').trim();

      if (userId.isEmpty || baseUrl.isEmpty) {
        debugPrint('uploadTransaction: userId or baseUrl missing');
        return false;
      }

      final payload = await _buildTransactionPayload(transactionId);
      if (payload == null) {
        debugPrint('uploadTransaction: no rows found for id $transactionId');
        return false;
      }

      final body = {
        'userId': userId,
        'Data': [payload],
      };

      debugPrint('uploadTransaction BODY: ${jsonEncode(body)}');

      final url = Uri.parse('$baseUrl/api/Transaction/createTransaction');
      final response = await http.post(
        url,
        headers: await headers(),
        body: jsonEncode(body),
      );
      await handleUnauthorized(response);

      debugPrint('uploadTransaction STATUS: ${response.statusCode}');
      debugPrint('uploadTransaction RESPONSE: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        await AppDatabase.markTransactionSynced(transactionId);
        return true;
      } else {
        await AppDatabase.markTransactionFailed(transactionId);
        return false;
      }
    } catch (e) {
      debugPrint('uploadTransaction ERROR: $e');
      await AppDatabase.markTransactionFailed(transactionId);
      return false;
    }
  }

  /// ------------------------------------------------------------------
  /// UPLOAD MULTIPLE TRANSACTIONS (Bulk)
  /// ------------------------------------------------------------------
  static Future<Map<String, dynamic>> uploadTransactions({
    required String baseUrl,
    required String userId,
    required List<Map<String, dynamic>> dataList,
  }) async {
    if (baseUrl.isEmpty) {
      return {'ok': false, 'error': 'No API URL configured'};
    }
    if (dataList.isEmpty) {
      return {'ok': false, 'error': 'No transactions to upload'};
    }

    final url = Uri.parse('$baseUrl/api/Transaction/createTransaction');

    final body = {
      'userId': userId,
      'data': dataList,
    };

    debugPrint('======= API REQUEST =======');
    debugPrint('URL: $url');
    debugPrint('BODY: ${jsonEncode(body)}');

    try {
      final response = await http.post(
        url,
        headers: await headers(),
        body: jsonEncode(body),
      );
      await handleUnauthorized(response);

      debugPrint('======= API RESPONSE =======');
      debugPrint('STATUS: ${response.statusCode}');
      debugPrint('BODY: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final respJson =
            response.body.isNotEmpty ? jsonDecode(response.body) : {};
        return {'ok': true, 'data': respJson};
      } else {
        String errorMsg = response.body;
        try {
          final decoded = jsonDecode(response.body);
          if (decoded is Map) {
            errorMsg = (decoded['message'] ??
                    decoded['error'] ??
                    decoded['title'] ??
                    decoded['errors']?.toString() ??
                    errorMsg)
                .toString();
          }
        } catch (_) {}

        return {
          'ok': false,
          'error': 'HTTP ${response.statusCode}',
          'response': errorMsg,
        };
      }
    } catch (e) {
      debugPrint('======= API ERROR =======');
      debugPrint(e.toString());
      return {'ok': false, 'error': e.toString()};
    }
  }

  /// -----------------------------
  /// LOCAL DB FALLBACK CUSTOMERS
  /// -----------------------------
  static Future<List<String>> _customersFromDB() async {
    final db = await AppDatabase.init();

    final rows = await db.query('Customer');

    return rows.map((r) => r['Name'] as String).toSet().toList();
  }

  /// -----------------------------
  /// LOCAL DB FALLBACK PRODUCTS
  /// -----------------------------
  static Future<List<Map<String, dynamic>>> _productsFromDB() async {
    final db = await AppDatabase.init();

    final rows = await db.query('Product');
    final Map<String, Map<String, dynamic>> unique = {};

    for (var r in rows) {
      final name = r['Name'] as String;
      final id = r['ProductID'] as int;
      if (!unique.containsKey(name) || (unique[name]!['id'] ?? 0) < id) {
        unique[name] = {
          "id": id,
          "name": name,
          "price": (r['UnitPrice'] as num).toDouble(),
          "availableQty": r['AvailableQty']
        };
      }
    }

    return unique.values.toList();
  }

  /// -----------------------------
  /// CHECK PRODUCT BATCH
  /// -----------------------------
  /// Returns a map: {'valid': bool, 'message': String?}
  static Future<Map<String, dynamic>> checkBatch({
    required int productId,
    required String batchNo,
    required int customerId,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final baseUrl = prefs.getString('baseUrl') ?? '';
      final userId = prefs.getString('userId') ?? '';

      if (baseUrl.isEmpty || userId.isEmpty) {
        debugPrint('checkBatch: baseUrl or userId missing');
        return {
          'valid': false,
          'message': 'Base URL or User ID not configured'
        };
      }

      final url = Uri.parse('$baseUrl/api/Products/batchCheck');
      final body = {
        'userId': userId,
        'productId': productId,
        'batchno': batchNo,
        'customerId': customerId,
      };

      debugPrint('checkBatch REQUEST: ${jsonEncode(body)}');

      final response = await http.post(
        url,
        headers: await headers(),
        body: jsonEncode(body),
      );
      await handleUnauthorized(response);

      debugPrint('checkBatch STATUS: ${response.statusCode}');
      debugPrint('checkBatch RESPONSE: ${response.body}');

      if (response.statusCode == 200) {
        return {'valid': true, 'message': null};
      }

      // Try to extract an error message from the response body
      String errorMsg = 'Invalid batch number';
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map) {
          errorMsg = (decoded['message'] ??
                  decoded['error'] ??
                  decoded['title'] ??
                  errorMsg)
              .toString();
        } else if (decoded is String && decoded.isNotEmpty) {
          errorMsg = decoded;
        }
      } catch (_) {
        if (response.body.isNotEmpty) errorMsg = response.body;
      }

      return {'valid': false, 'message': errorMsg};
    } catch (e) {
      debugPrint('checkBatch ERROR: $e');
      return {'valid': false, 'message': 'Network error: $e'};
    }
  }

  static Future<Map<String, dynamic>> syncAllTransactions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final baseUrl = prefs.getString('baseUrl') ?? '';
      final userId = (prefs.getString('userId') ?? '').trim();

      if (baseUrl.isEmpty || userId.isEmpty) {
        return {'ok': false, 'error': 'Base URL or User ID not configured'};
      }

      final db = await AppDatabase.init();
      final pendingTransactions = await db.query(
        '"Transaction"',
        where: 'SyncStatus = ?',
        whereArgs: ['Pending'],
      );

      if (pendingTransactions.isEmpty) {
        return {'ok': true, 'message': 'Everything is already synced.'};
      }

      final dataList = <Map<String, dynamic>>[];
      final txIds = <int>[];

      for (var tx in pendingTransactions) {
        int transactionId = tx['TransactionID'] as int;
        final payload = await _buildTransactionPayload(transactionId);
        if (payload != null) {
          dataList.add(payload);
          txIds.add(transactionId);
        }
      }

      if (dataList.isEmpty) {
        return {
          'ok': false,
          'error': 'Could not build payload for pending transactions'
        };
      }

      final result = await uploadTransactions(
        baseUrl: baseUrl,
        userId: userId,
        dataList: dataList,
      );

      if (result['ok'] == true) {
        for (var id in txIds) {
          await AppDatabase.markTransactionSynced(id);
        }
        final Map<String, dynamic> data = result['data'] ?? {};
        String msg = 'Successfully synced ${txIds.length} transactions';
        if (data.containsKey('message')) {
          msg = data['message'].toString();
        } else if (data.containsKey('response')) {
          msg = data['response'].toString();
        }
        return {'ok': true, 'message': msg};
      } else {
        for (var id in txIds) {
          await AppDatabase.markTransactionFailed(id);
        }
        return result;
      }
    } catch (e) {
      return {'ok': false, 'error': e.toString()};
    }
  }
}
