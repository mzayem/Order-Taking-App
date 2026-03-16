import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class AppDatabase {
  static Database? _db;

  static Future<Database> init() async {
    if (_db != null) return _db!;

    final databasesPath = await getDatabasesPath();
    final path = join(databasesPath, 'app_local.db');

    _db = await openDatabase(
      path,
      version: 3,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON;');
      },
      onCreate: (db, version) async {
        // ================= SETTINGS =================
        await db.execute('''
        CREATE TABLE Settings(
          SettingsID TEXT PRIMARY KEY,
          CompanyName TEXT,
          ApiUrl TEXT,
          Payload TEXT,
          Signature TEXT,
          ExpDate INTEGER,
          CreatedAt TEXT,
          UpdatedAt TEXT
        )
        ''');

        // ================= CUSTOMER =================
        await db.execute('''
        CREATE TABLE Customer(
          CustomerID INTEGER PRIMARY KEY,
          Name TEXT NOT NULL,
          Town TEXT,
          IsNarcotics INTEGER DEFAULT 0
        )
        ''');

        // ================= USER =================
        await db.execute('''
        CREATE TABLE User(
          UserID INTEGER PRIMARY KEY,
          Name TEXT,
          Role TEXT
        )
        ''');

        // ================= USER TOWN =================
        await db.execute('''
        CREATE TABLE UserTown(
          UserTownID INTEGER PRIMARY KEY AUTOINCREMENT,
          UserID INTEGER,
          Town TEXT,
          FOREIGN KEY(UserID) REFERENCES User(UserID)
        )
        ''');

        // ================= PRODUCT =================
        await db.execute('''
        CREATE TABLE Product(
          ProductID INTEGER PRIMARY KEY,
          Name TEXT,
          Code TEXT,
          ProductType TEXT,
          UnitPrice REAL,
          AvailableQty INTEGER
        )
        ''');

        // ================= TRANSACTION =================
        await db.execute('''
        CREATE TABLE "Transaction"(
          TransactionID INTEGER PRIMARY KEY AUTOINCREMENT,
          CustomerID INTEGER,
          Type TEXT,
          Date TEXT,
          TotalAmount REAL,
          CashAmount REAL,
          Remarks TEXT,
          SyncStatus TEXT,
          RemoteTransactionID INTEGER,
          CreatedAt TEXT,
          UpdatedAt TEXT,
          FOREIGN KEY(CustomerID) REFERENCES Customer(CustomerID)
        )
        ''');

        // ================= TRANSACTION DETAIL =================
        await db.execute('''
        CREATE TABLE TransactionDetail(
          TransactionDetailID INTEGER PRIMARY KEY AUTOINCREMENT,
          TransactionID INTEGER,
          ProductID INTEGER,
          BatchNo TEXT,
          Qty INTEGER,
          UnitPrice REAL,
          TotalPrice REAL,
          FOREIGN KEY(TransactionID) REFERENCES "Transaction"(TransactionID),
          FOREIGN KEY(ProductID) REFERENCES Product(ProductID)
        )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 3) {
          // Add ProductType column if missing
          try {
            await db
                .execute('ALTER TABLE Product ADD COLUMN ProductType TEXT;');
          } catch (e) {
            print("ProductType column already exists or upgrade skipped: $e");
          }
        }
      },
    );

    return _db!;
  }

  // ================= CUSTOMER UPSERT =================
  static Future<void> upsertCustomer(Map<String, dynamic> customer) async {
    final db = await init();

    int count = await db.update(
      'Customer',
      {
        'Name': customer['Name'],
        'Town': customer['Town'] ?? '',
        'IsNarcotics': customer['IsNarcotics'] ?? 0,
      },
      where: 'CustomerID=?',
      whereArgs: [customer['CustomerID']],
    );

    if (count == 0) {
      await db.insert('Customer', {
        'CustomerID': customer['CustomerID'],
        'Name': customer['Name'],
        'Town': customer['Town'] ?? '',
        'IsNarcotics': customer['IsNarcotics'] ?? 0,
      });
    }
  }

  // ================= PRODUCT UPSERT =================
  static Future<void> upsertProduct(Map<String, dynamic> product) async {
    final db = await init();

    int count = await db.update(
      'Product',
      {
        'Name': product['Name'],
        'Code': product['Code'],
        'ProductType': product['ProductType'] ?? 'Medicine',
        'UnitPrice': (product['UnitPrice'] ?? 0.0).toDouble(),
        'AvailableQty': product['AvailableQty'] ?? 0,
      },
      where: 'ProductID=?',
      whereArgs: [product['ProductID']],
    );

    if (count == 0) {
      await db.insert('Product', {
        'ProductID': product['ProductID'],
        'Name': product['Name'],
        'Code': product['Code'],
        'ProductType': product['ProductType'] ?? 'Medicine',
        'UnitPrice': (product['UnitPrice'] ?? 0.0).toDouble(),
        'AvailableQty': product['AvailableQty'] ?? 0,
      });
    }
  }

  // ================= USER UPSERT =================
  static Future<void> upsertUser(Map<String, dynamic> user) async {
    final db = await init();

    int count = await db.update(
      'User',
      {
        'Name': user['Name'],
        'Role': user['Role'],
      },
      where: 'UserID=?',
      whereArgs: [user['UserID']],
    );

    if (count == 0) {
      await db.insert('User', {
        'UserID': user['UserID'],
        'Name': user['Name'],
        'Role': user['Role'],
      });
    }
  }

  // ================= INSERT USER TOWNS =================
  static Future<void> insertUserTowns(int userId, List<String> towns) async {
    final db = await init();

    await db.delete("UserTown", where: "UserID=?", whereArgs: [userId]);

    for (var town in towns) {
      await db.insert("UserTown", {"UserID": userId, "Town": town});
    }
  }

  // ================= SETTINGS METHODS =================
  static Future<void> upsertSettings({
    required String settingsId,
    required String companyName,
    required String apiUrl,
    required String payload,
    required String signature,
    required int expDate,
  }) async {
    final db = await init();
    final existing = await db.query(
      'Settings',
      where: 'SettingsID = ?',
      whereArgs: [settingsId],
    );

    final now = DateTime.now().millisecondsSinceEpoch;

    if (existing.isEmpty) {
      await db.insert('Settings', {
        'SettingsID': settingsId,
        'CompanyName': companyName,
        'ApiUrl': apiUrl,
        'Payload': payload,
        'Signature': signature,
        'ExpDate': expDate,
        'CreatedAt': now.toString(),
        'UpdatedAt': null,
      });
    } else {
      await db.update(
        'Settings',
        {
          'CompanyName': companyName,
          'ApiUrl': apiUrl,
          'Payload': payload,
          'Signature': signature,
          'ExpDate': expDate,
          'UpdatedAt': now.toString(),
        },
        where: 'SettingsID = ?',
        whereArgs: [settingsId],
      );
    }
  }

  static Future<bool> isLicenseExpired() async {
    final db = await init();
    final rows = await db.query('Settings', limit: 1);
    if (rows.isEmpty) return true;

    final expDate = rows.first['ExpDate'] as int? ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    return now > expDate;
  }

  static Future<void> clearSettings() async {
    final db = await init();
    await db.delete('Settings');
  }

  // ---------------------- HELPERS ----------------------
  static Future<int> insertCustomerIfNotExists(String name,
      {String? town}) async {
    final db = await init();
    final rows = await db.query('Customer',
        where: 'Name = ?', whereArgs: [name], limit: 1);
    if (rows.isNotEmpty) return rows.first['CustomerID'] as int;
    return await db.insert('Customer', {'Name': name, 'Town': town ?? ''});
  }

  static Future<int> insertProductIfNotExists(String name,
      {double unitPrice = 0.0,
      int availableQty = 0,
      String? code,
      String? type}) async {
    final db = await init();
    final rows = await db.query('Product',
        where: 'Name = ?', whereArgs: [name], limit: 1);
    if (rows.isNotEmpty) return rows.first['ProductID'] as int;
    return await db.insert('Product', {
      'Name': name,
      'Code': code ?? '',
      'UnitPrice': unitPrice,
      'AvailableQty': availableQty,
      'ProductType': type ?? 'Medicine',
    });
  }

  // ... KEEP ALL TRANSACTION FUNCTIONS SAME, ADD NULL-SAFE CASTS ...
  // For example:
  // final unitPrice = ((d['unitPrice'] ?? 0.0) as num).toDouble();

  static Future<int> createTransactionWithDetails({
    required int customerId,
    required String type, // 'Order'|'Return'|'Cash'|'Draft'
    required List<Map<String, dynamic>> details,
    double? cashAmount,
    String? remarks,
  }) async {
    final db = await init();

    return await db.transaction((txn) async {
      double totalAmount = 0.0;

      for (final d in details) {
        final qty = (d['qty'] ?? 0) as int;
        final unitPrice = ((d['unitPrice'] ?? 0.0) as num).toDouble();
        totalAmount += qty * unitPrice;
      }

      if (type == 'Cash') {
        totalAmount = cashAmount ?? 0.0;
      }

      final header = {
        'CustomerID': customerId,
        'Type': type,
        'Date': DateTime.now().toIso8601String(),
        'TotalAmount': totalAmount,
        'CashAmount': cashAmount ?? 0.0,
        'Remarks': remarks ?? '',
        'SyncStatus': 'Pending',
        'CreatedAt': DateTime.now().toIso8601String(),
        'UpdatedAt': DateTime.now().toIso8601String(),
      };

      final tId = await txn.insert('"Transaction"', header);

      for (final d in details) {
        int productId;

        if (d.containsKey('productId')) {
          productId = d['productId'] as int;
        } else {
          final name = d['productName'] as String;
          productId = await insertProductIfNotExists(
            name,
            unitPrice: ((d['unitPrice'] ?? 0.0) as num).toDouble(),
            availableQty: (d['availableQty'] ?? 0) as int,
          );
        }

        final qty = (d['qty'] ?? 0) as int;
        final unitPrice = ((d['unitPrice'] ?? 0.0) as num).toDouble();
        final totalPrice = qty * unitPrice;

        await txn.insert('TransactionDetail', {
          'TransactionID': tId,
          'ProductID': productId,
          'BatchNo': d['batchNo'],
          'Qty': qty,
          'UnitPrice': unitPrice,
          'TotalPrice': totalPrice,
        });
      }

      return tId;
    });
  }

  static Future<void> updateTransactionAndReplaceDetails({
    required int transactionId,
    required int customerId,
    required String type,
    required List<Map<String, dynamic>> details,
    double? cashAmount,
    String? remarks,
  }) async {
    final db = await init();

    await db.transaction((txn) async {
      double totalAmount = 0.0;

      for (final d in details) {
        final qty = (d['qty'] ?? 0) as int;
        final unitPrice = ((d['unitPrice'] ?? 0.0) as num).toDouble();
        totalAmount += qty * unitPrice;
      }

      if (type == 'Cash') {
        totalAmount = cashAmount ?? 0.0;
      }

      await txn.update(
        '"Transaction"',
        {
          'CustomerID': customerId,
          'Type': type,
          'TotalAmount': totalAmount,
          'CashAmount': cashAmount ?? 0.0,
          'Remarks': remarks ?? '',
          'UpdatedAt': DateTime.now().toIso8601String(),
        },
        where: 'TransactionID = ?',
        whereArgs: [transactionId],
      );

      await txn.delete(
        'TransactionDetail',
        where: 'TransactionID = ?',
        whereArgs: [transactionId],
      );

      for (final d in details) {
        int productId;

        if (d.containsKey('productId')) {
          productId = d['productId'] as int;
        } else {
          final name = d['productName'] as String;
          productId = await insertProductIfNotExists(
            name,
            unitPrice: ((d['unitPrice'] ?? 0.0) as num).toDouble(),
            availableQty: (d['availableQty'] ?? 0) as int,
          );
        }

        final qty = (d['qty'] ?? 0) as int;
        final unitPrice = ((d['unitPrice'] ?? 0.0) as num).toDouble();
        final totalPrice = qty * unitPrice;

        await txn.insert('TransactionDetail', {
          'TransactionID': transactionId,
          'ProductID': productId,
          'BatchNo': d['batchNo'],
          'Qty': qty,
          'UnitPrice': unitPrice,
          'TotalPrice': totalPrice,
        });
      }
    });
  }

  static Future<int?> findTransactionForCustomerOnDate(
      int customerId, String type, DateTime date) async {
    final db = await init();
    final dayStr =
        '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final rows = await db.query('"Transaction"',
        where: 'CustomerID = ? AND Type = ? AND date(Date) = ?',
        whereArgs: [customerId, type, dayStr],
        limit: 1);
    if (rows.isNotEmpty) return rows.first['TransactionID'] as int;
    return null;
  }

  static Future<List<Map<String, dynamic>>> getAllTransactionsForOverview(
      {int limit = 500}) async {
    final db = await init();
    return await db.query('"Transaction"', orderBy: 'Date DESC', limit: limit);
  }

  static Future<List<Map<String, dynamic>>> getTransactionWithDetails(
      int transactionId) async {
    final db = await init();
    final rows = await db.rawQuery('''
      SELECT t.TransactionID, t.CustomerID, t.Type, t.Date, t.TotalAmount, 
             t.CashAmount, t.Remarks, t.SyncStatus, t.UpdatedAt,
             td.TransactionDetailID, td.ProductID, td.BatchNo, td.Qty, 
             td.UnitPrice, td.TotalPrice, p.Name AS ProductName
      FROM "Transaction" t
      LEFT JOIN TransactionDetail td ON td.TransactionID = t.TransactionID
      LEFT JOIN Product p ON p.ProductID = td.ProductID
      WHERE t.TransactionID = ?
    ''', [transactionId]);

    return rows;
  }

  static Future<void> markTransactionSynced(int transactionId,
      {int? remoteId}) async {
    final db = await init();
    await db.update(
        '"Transaction"',
        {
          'SyncStatus': 'Synced',
          'RemoteTransactionID': remoteId,
          'UpdatedAt': DateTime.now().toIso8601String(),
        },
        where: 'TransactionID = ?',
        whereArgs: [transactionId]);
  }

  static Future<void> markTransactionFailed(int transactionId) async {
    final db = await init();
    await db.update(
        '"Transaction"',
        {
          'SyncStatus': 'Failed',
          'UpdatedAt': DateTime.now().toIso8601String(),
        },
        where: 'TransactionID = ?',
        whereArgs: [transactionId]);
  }

  // ================= DATABASE FILE & CLOSE =================
  static Future<void> deleteDatabaseFile() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'app_local.db');
    await deleteDatabase(path);
    _db = null;
  }

  static Future<void> close() async {
    if (_db != null) {
      await _db!.close();
      _db = null;
    }
  }
}
