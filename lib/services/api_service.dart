import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../db/database.dart';
import 'app_log.dart';
import '../login_screen.dart';
import '../main.dart' show navigatorKey;

class ApiService {
  /// Requests currently running, by key. A second caller with the same key
  /// gets the same Future instead of firing a duplicate request (Home, pull
  /// to refresh, resume and the daily refresh can all ask at once).
  static final Map<String, Future<Object?>> _inFlight = {};

  static Future<T> _dedupe<T>(String key, Future<T> Function() run) {
    final running = _inFlight[key];
    if (running != null) return running as Future<T>;
    // Block body on purpose: `() => _inFlight.remove(key)` RETURNS the future
    // being completed, and whenComplete waits for a returned future, so the
    // request would wait for itself and never finish.
    final future = run().whenComplete(() {
      _inFlight.remove(key);
    });
    _inFlight[key] = future;
    return future;
  }

  static String _today() {
    final d = DateTime.now();
    return '${d.year}-${d.month}-${d.day}';
  }

  /// Auth headers plus If-None-Match, so an unchanged list comes back as an
  /// empty 304. Skipped when the local table is empty (nothing to keep).
  static Future<Map<String, String>> _withETag(String key, String table) async {
    final h = await headers();
    final etag = (await SharedPreferences.getInstance()).getString(key);
    if (etag == null) return h;
    final db = await AppDatabase.init();
    final hasRows =
        (await db.rawQuery('SELECT 1 FROM $table LIMIT 1')).isNotEmpty;
    if (hasRows) h['If-None-Match'] = etag;
    return h;
  }

  static Future<void> _saveETag(String key, http.Response response) async {
    final etag = response.headers['etag'];
    final prefs = await SharedPreferences.getInstance();
    if (etag != null && etag.isNotEmpty) {
      await prefs.setString(key, etag);
    } else {
      await prefs.remove(key); // server without ETags: always download
    }
  }

  /// True when customers/products have not been refreshed yet today.
  static Future<bool> needsDailyRefresh() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('lastDataRefresh') != _today();
  }

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
    AppLog.warning(LogCategory.auth, 'Session expired (HTTP 401). Signed out.');
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
  static Future<List<String>> fetchCustomers() =>
      _dedupe('customers', _fetchCustomers);

  static Future<List<String>> _fetchCustomers() async {
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

      final etagKey = 'etag_customers_$userId'; // towns differ per user
      final response = await http.post(
        url,
        headers: await _withETag(etagKey, 'Customer'),
        body: jsonEncode({
          "userId": userId,
          "townIds": townIds.map(int.parse).toList(),
        }),
      );
      await handleUnauthorized(response);
      print("Customer API Status = ${response.statusCode}");

      if (response.statusCode == 304) {
        // Unchanged since the last download: local data is current.
        await prefs.setString('lastDataRefresh', _today());
        return await _customersFromDB();
      }

      if (response.statusCode == 200) {
        await _saveETag(etagKey, response);
        final data = jsonDecode(response.body);

        final List list = data['customers'] ?? [];

        // One batched write instead of a round trip per customer.
        await AppDatabase.upsertCustomers(list
            .map((c) => <String, dynamic>{
                  'customerId': c['customerId'],
                  'customerName': c['customerName'],
                  'address': c['address'] ?? '',
                  'townID': c['townID'],
                  'isNarcoticsAllowed': c['isNarcoticsAllowed'] ?? false,
                })
            .toList());

        // Lets Home skip the next "first open of the day" refresh.
        await prefs.setString('lastDataRefresh', _today());

        AppLog.info(LogCategory.sync, 'Customers downloaded: ${list.length}');
        return list
            .map((c) => (c['customerName'] ?? '').toString())
            .toSet()
            .toList();
      }

      return await _customersFromDB();
    } catch (e, stackTrace) {
      print("================================");
      print("Customer Fetch Error");
      AppLog.error(LogCategory.api, 'Customer fetch failed: $e');
      print(e);
      print(stackTrace);
      print("================================");

      return await _customersFromDB();
    }
  }

  /// -----------------------------
  /// FETCH PRODUCTS
  /// -----------------------------
  static Future<List<Map<String, dynamic>>> fetchProducts() =>
      _dedupe('products', _fetchProducts);

  static Future<List<Map<String, dynamic>>> _fetchProducts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final baseUrl = prefs.getString('baseUrl') ?? '';
      final userId = prefs.getString('userId') ?? '';

      if (baseUrl.isEmpty) {
        return await _productsFromDB();
      }

      final url = Uri.parse('$baseUrl/api/Products/getProduct');

      const etagKey = 'etag_products';
      final response = await http.post(
        url,
        headers: await _withETag(etagKey, 'Product'),
        body: jsonEncode({
          "userId": userId,
        }),
      );
      await handleUnauthorized(response);

      if (response.statusCode == 304) {
        return await _productsFromDB(); // unchanged: local data is current
      }

      if (response.statusCode == 200) {
        await _saveETag(etagKey, response);
        final data = jsonDecode(response.body);

        final List list = data['products'] ?? [];

        Map<String, Map<String, dynamic>> products = {};

        for (var p in list) {
          products[p['productName']] = {
            "name": p['productName'],
            "price": (p['latestPrice'] as num).toDouble(),
            "type": p['productType'],
            "availableQty": p['totalQty']
          };
        }

        // One batched write instead of a round trip per product.
        await AppDatabase.upsertProducts(list
            .map((p) => <String, dynamic>{
                  'ProductID': p['productId'],
                  'Name': p['productName'],
                  'Code': '',
                  'UnitPrice': (p['latestPrice'] as num).toDouble(),
                  'AvailableQty': p['totalQty'],
                  'ProductType': p['productType'], // Medicine, Narcotics, ...
                })
            .toList());

        AppLog.info(LogCategory.sync, 'Products downloaded: ${list.length}');
        return products.values.toList();
      }

      return await _productsFromDB();
    } catch (e) {
      AppLog.error(LogCategory.api, 'Product fetch failed: $e');
      return await _productsFromDB();
    }
  }

  /// ------------------------------------------------------------------
  /// BUILD A SINGLE TRANSACTION PAYLOAD (shared helper)
  /// ------------------------------------------------------------------
  static Future<Map<String, dynamic>?> buildTransactionPayload(
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

    // The day the transaction was taken, not the day it is uploaded.
    final taken =
        DateTime.tryParse(header['Date'] as String? ?? '') ?? DateTime.now();

    return {
      'clientId': transactionId, // local ID, echoed back in the results
      'date': taken.toUtc().toIso8601String(),
      'customerId': header['CustomerID'] as int,
      'type': convertType(header['Type'] as String),
      'remarks': header['Remarks'] ?? '',
      'totalAmount': (header['TotalAmount'] as num?)?.toDouble() ?? 0.0,
      if (header['VendorGroupID'] != null)
        'vendorGroupId': header['VendorGroupID'],
      'transactionDetails': details,
    };
  }

  /// -----------------------------
  /// VENDOR GROUPS (cached for offline Cash entry)
  /// -----------------------------
  /// Returns how many groups the server sent, or null when it couldn't be
  /// reached (the cached list is kept).
  static Future<int?> fetchVendorGroups() =>
      _dedupe('vendorGroups', _fetchVendorGroups);

  static Future<int?> _fetchVendorGroups() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final baseUrl = prefs.getString('baseUrl') ?? '';
      if (baseUrl.isEmpty) return null;

      final response = await http.post(
        Uri.parse('$baseUrl/api/VendorGroup/getVendorGroups'),
        headers: await headers(),
        body: jsonEncode({'userId': prefs.getString('userId') ?? ''}),
      );
      await handleUnauthorized(response);
      if (response.statusCode != 200) return null;

      final List list = jsonDecode(response.body)['vendorGroups'] ?? [];
      await AppDatabase.replaceVendorGroups(list
          .map((g) => <String, dynamic>{
                'VendorGroupID': g['vendorGroupId'],
                'Name': g['name'],
              })
          .toList());
      return list.length;
    } catch (e) {
      debugPrint('fetchVendorGroups ERROR: $e'); // keep the cached list
      AppLog.warning(LogCategory.api, 'Vendor groups fetch failed: $e');
      return null;
    }
  }

  /// -----------------------------
  /// NOTIFICATIONS
  /// -----------------------------
  /// Returns {'unread': int, 'notifications': List} or null when offline.
  static Future<Map<String, dynamic>?> fetchNotifications() =>
      _dedupe('notifications', _fetchNotifications);

  static Future<Map<String, dynamic>?> _fetchNotifications() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final baseUrl = prefs.getString('baseUrl') ?? '';
      if (baseUrl.isEmpty) return null;

      final response = await http
          .post(
            Uri.parse('$baseUrl/api/Notification/getNotifications'),
            headers: await headers(),
            body: jsonEncode({'userId': prefs.getString('userId') ?? ''}),
          )
          .timeout(const Duration(seconds: 15));
      await handleUnauthorized(response);
      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body);
      final List list = data['notifications'] ?? [];
      return {
        'unread':
            data['unread'] ?? list.where((n) => n['unread'] == true).length,
        'notifications': list,
      };
    } catch (e) {
      debugPrint('fetchNotifications ERROR: $e');
      AppLog.warning(
          LogCategory.notification, 'Notifications fetch failed: $e');
      return null;
    }
  }

  /// Marks one notification read, or all when [notificationId] is null.
  static Future<void> markNotificationRead([int? notificationId]) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final baseUrl = prefs.getString('baseUrl') ?? '';
      if (baseUrl.isEmpty) return;

      final response = await http.post(
        Uri.parse('$baseUrl/api/Notification/markRead'),
        headers: await headers(),
        body: jsonEncode({
          'userId': prefs.getString('userId') ?? '',
          if (notificationId != null) 'notificationId': notificationId,
        }),
      );
      await handleUnauthorized(response);
    } catch (e) {
      debugPrint('markNotificationRead ERROR: $e');
      AppLog.warning(LogCategory.notification, 'Mark read failed: $e');
    }
  }

  /// ------------------------------------------------------------------
  /// UPLOAD TRANSACTIONS BY LOCAL ID
  /// The API answers 200 (all ok), 207 (some failed) or 400 (all failed),
  /// each with a `results` entry per transaction. Each local row is marked
  /// from its own result. When no results come back (network error, 401,
  /// 500) statuses are left unchanged so the rows can be retried.
  ///
  /// Returns {'ok': bool, 'message': String}.
  /// ------------------------------------------------------------------
  static Future<Map<String, dynamic>> uploadTransactionIds(
      List<int> ids) async {
    final prefs = await SharedPreferences.getInstance();
    final baseUrl = prefs.getString('baseUrl') ?? '';
    final userId = (prefs.getString('userId') ?? '').trim();

    if (baseUrl.isEmpty || userId.isEmpty) {
      return {'ok': false, 'message': 'Base URL or User ID not configured'};
    }

    final dataList = <Map<String, dynamic>>[];
    for (final id in ids) {
      final payload = await buildTransactionPayload(id);
      if (payload != null) dataList.add(payload);
    }
    if (dataList.isEmpty) {
      return {'ok': false, 'message': 'No transactions to upload'};
    }

    final http.Response response;
    try {
      response = await http.post(
        Uri.parse('$baseUrl/api/Transaction/createTransaction'),
        headers: await headers(),
        body: jsonEncode({'userId': userId, 'data': dataList}),
      );
    } catch (e) {
      debugPrint('upload ERROR: $e');
      AppLog.error(LogCategory.sync, 'Upload could not reach the server: $e');
      return {'ok': false, 'message': 'Unable to connect to server.'};
    }
    await handleUnauthorized(response);

    debugPrint('upload STATUS: ${response.statusCode}');
    debugPrint('upload BODY: ${response.body}');

    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {}

    final results = decoded is Map ? decoded['results'] : null;
    if (results is! List) {
      final msg = decoded is Map ? decoded['message']?.toString() : null;
      AppLog.error(LogCategory.sync,
          'Upload failed (HTTP ${response.statusCode}): ${msg ?? 'no results'}');
      return {
        'ok': false,
        'message': msg ?? 'Upload failed (HTTP ${response.statusCode})',
      };
    }

    int synced = 0;
    final failures = <String>[];
    for (final r in results) {
      final clientId = int.tryParse('${r['clientId']}');
      if (clientId == null) continue;
      if (r['success'] == true) {
        await AppDatabase.markTransactionSynced(clientId,
            remoteId: int.tryParse('${r['serverId']}'));
        synced++;
      } else {
        await AppDatabase.markTransactionFailed(clientId);
        failures.add('#$clientId: ${r['message'] ?? 'failed'}');
      }
    }

    if (failures.isEmpty) {
      AppLog.info(LogCategory.sync, 'Uploaded $synced transaction(s)');
    } else {
      AppLog.warning(LogCategory.sync,
          'Uploaded $synced, failed ${failures.length}: ${failures.join('; ')}');
    }

    if (failures.isEmpty) {
      return {
        'ok': true,
        'synced': synced,
        'message': 'Uploaded $synced transaction(s)',
      };
    }
    return {
      'ok': false,
      'synced': synced,
      'message':
          'Uploaded $synced, failed ${failures.length}\n${failures.join('\n')}',
    };
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
          "availableQty": r['AvailableQty'],
          "type": r['ProductType'],
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
      AppLog.error(LogCategory.api, 'Batch check failed: $e');
      return {'valid': false, 'message': 'Network error: $e'};
    }
  }

  /// Uploads everything not yet synced, including earlier failures.
  static Future<Map<String, dynamic>> syncAllTransactions() async {
    // Only the logged-in salesman's work: never push another user's orders.
    final ids = await AppDatabase.getUnsyncedTransactionIds();

    if (ids.isEmpty) {
      return {'ok': true, 'message': 'Everything is already synced.'};
    }

    return uploadTransactionIds(ids);
  }
}
