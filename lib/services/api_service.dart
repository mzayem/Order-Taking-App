import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../db/database.dart';

class ApiService {
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

      if (baseUrl.isEmpty || userId.isEmpty || townIds.isEmpty) {
        return await _customersFromDB();
      }

      final url = Uri.parse('$baseUrl/api/Customer/customerFetch');

      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "userId": userId,
          "townIds": townIds.map(int.parse).toList(),
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        final List list = data['customers'] ?? [];

        List<String> customers = [];

        for (var c in list) {
          customers.add(c['customerName']);

          await AppDatabase.upsertCustomer({
            'CustomerID': c['customerId'],
            'Name': c['customerName'],
            'Town': c['townName'] ?? '',
          });
        }

        return customers;
      }

      return await _customersFromDB();
    } catch (e) {
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

      if (baseUrl.isEmpty) {
        return await _productsFromDB();
      }

      final url = Uri.parse('$baseUrl/api/Product/productFetch');

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        final List list = data['products'] ?? [];

        List<Map<String, dynamic>> products = [];

        for (var p in list) {
          products.add({
            "name": p['productName'],
            "price": (p['latestPrice'] as num).toDouble(),
            "availableQty": p['totalQty']
          });

          await AppDatabase.upsertProduct({
            'ProductID': p['productId'],
            'Name': p['productName'],
            'Code': '',
            'UnitPrice': (p['latestPrice'] as num).toDouble(),
            'AvailableQty': p['totalQty'],
          });
        }

        return products;
      }

      return await _productsFromDB();
    } catch (e) {
      return await _productsFromDB();
    }
  }

  /// -----------------------------
  /// UPLOAD SINGLE TRANSACTION
  /// -----------------------------
  static Future<bool> uploadTransaction(int transactionId) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final baseUrl = prefs.getString('baseUrl') ?? '';
      final userId = (prefs.getString("userId") ?? "").trim();

      print("USER ID: $userId");
      print("USER ID LENGTH: ${userId.length}");

      if (userId.isEmpty || baseUrl.isEmpty) {
        print("User ID or Base URL missing");
        return false;
      }

      final rows = await AppDatabase.getTransactionWithDetails(transactionId);

      if (rows.isEmpty) return false;

      final header = rows.first;

      List<Map<String, dynamic>> details = [];

      for (var r in rows) {
        if (r['TransactionDetailID'] != null) {
          details.add({
            "productId": r['ProductID'],
            "batchNo": r['BatchNo'] ?? "",
            "qty": r['Qty'],
            "unitPrice": (r['UnitPrice'] as num?)?.toDouble() ?? 0,
            "totalAmount": (r['TotalPrice'] as num?)?.toDouble() ?? 0,
          });
        }
      }
      final body = {
        "userId": userId,
        "date": DateTime.now().toUtc().toIso8601String(),
        "customerId": header['CustomerID'] as int,
        "type": convertType(header['Type'] as String),
        "remarks": header['Remarks'] ?? "",
        "totalAmount": (header['TotalAmount'] as num?)?.toDouble() ?? 0.0,
        "transactionDetails": details
      };

      print("UPLOAD BODY: ${jsonEncode(body)}");

      print("USER ID: $userId");
      print("TOKEN: ${prefs.getString("headerRef")}");
      print("DETAIL COUNT: ${details.length}");

      final url = Uri.parse('$baseUrl/api/Transaction/createTransaction');
      final response = await http.post(
        url,
        headers: {
          "accept": "*/*",
          "Content-Type": "application/json",
        },
        body: jsonEncode(body),
      );
      print("STATUS: ${response.statusCode}");
      print("RESPONSE: ${response.body}");

      if (response.statusCode == 200 || response.statusCode == 201) {
        await AppDatabase.markTransactionSynced(transactionId);
        return true;
      } else {
        await AppDatabase.markTransactionFailed(transactionId);
        return false;
      }
    } catch (e) {
      print("UPLOAD ERROR: $e");

      await AppDatabase.markTransactionFailed(transactionId);
      return false;
    }
  }

  /// -----------------------------

  /// -----------------------------
  /// LOCAL DB FALLBACK CUSTOMERS
  /// -----------------------------
  static Future<List<String>> _customersFromDB() async {
    final db = await AppDatabase.init();

    final rows = await db.query('Customer');

    return rows.map((r) => r['Name'] as String).toList();
  }

  /// -----------------------------
  /// LOCAL DB FALLBACK PRODUCTS
  /// -----------------------------
  static Future<List<Map<String, dynamic>>> _productsFromDB() async {
    final db = await AppDatabase.init();

    final rows = await db.query('Product');

    return rows.map((r) {
      return {
        "name": r['Name'],
        "price": (r['UnitPrice'] as num).toDouble(),
        "availableQty": r['AvailableQty']
      };
    }).toList();
  }

  static Future<int> syncAllTransactions() async {
    final db = await AppDatabase.init();

    final pendingTransactions = await db.query(
      '"Transaction"',
      where: 'SyncStatus = ?',
      whereArgs: ['Pending'],
    );

    int syncedCount = 0;

    for (var tx in pendingTransactions) {
      int transactionId = tx['TransactionID'] as int;

      bool success = await uploadTransaction(transactionId);

      if (success) {
        syncedCount++;
      }
    }

    return syncedCount;
  }
}
