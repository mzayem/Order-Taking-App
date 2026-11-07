import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppDatabase {
  static Database? _db;

  static Future<Database> init() async {
    if (_db != null) return _db!;

    final databasesPath = await getDatabasesPath();
    final path = join(databasesPath, 'app_local.db');

    _db = await openDatabase(
      path,
      version: 7,
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
  Address TEXT,
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
          VendorGroupID INTEGER,
          UserID TEXT,
          UserName TEXT,
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

        await _createVendorGroupTable(db);
        await createAppLogTable(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 7) {
          await createAppLogTable(db); // new table only; no data touched
        }

        if (oldVersion < 3) {
          try {
            await db.execute('ALTER TABLE Product ADD COLUMN ProductType TEXT');
          } catch (_) {}
        }

        if (oldVersion < 4) {
          try {
            await db.execute('ALTER TABLE Customer ADD COLUMN Address TEXT');
          } catch (_) {}

          try {
            await db.execute('ALTER TABLE Customer ADD COLUMN Town TEXT');
          } catch (_) {}

          try {
            await db.execute(
                'ALTER TABLE Customer ADD COLUMN IsNarcotics INTEGER DEFAULT 0');
          } catch (_) {}
        }

        if (oldVersion < 6) {
          // Who took the transaction (salesman). Older rows stay NULL.
          for (final col in ['UserID', 'UserName']) {
            try {
              await db
                  .execute('ALTER TABLE "Transaction" ADD COLUMN $col TEXT');
            } catch (_) {}
          }
        }

        if (oldVersion < 5) {
          try {
            await db.execute(
                'ALTER TABLE "Transaction" ADD COLUMN VendorGroupID INTEGER');
          } catch (_) {}
          await _createVendorGroupTable(db);
        }
      },
    );

    return _db!;
  }

  /// Local activity log read by the Activity page (see services/app_log.dart).
  static Future<void> createAppLogTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS AppLog(
        LogID INTEGER PRIMARY KEY AUTOINCREMENT,
        Ts INTEGER NOT NULL,
        Level TEXT NOT NULL,
        Category TEXT NOT NULL,
        Message TEXT NOT NULL
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_applog_filter ON AppLog(Level, Category, Ts)');
  }

  static Future<void> _createVendorGroupTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS VendorGroup(
        VendorGroupID INTEGER PRIMARY KEY,
        Name TEXT
      )
    ''');
  }

  // ================= VENDOR GROUPS =================
  /// Replaces the cached list with what the server returned.
  static Future<void> replaceVendorGroups(
      List<Map<String, dynamic>> groups) async {
    final db = await init();
    await db.transaction((txn) async {
      await txn.delete('VendorGroup');
      for (final g in groups) {
        await txn.insert('VendorGroup', g);
      }
    });
  }

  static Future<List<Map<String, dynamic>>> getVendorGroups() async {
    final db = await init();
    return db.query('VendorGroup', orderBy: 'Name');
  }

  // ================= BULK UPSERTS (refresh) =================
  // One transaction + one batch for the whole list. Insert-or-ignore then
  // update: works on old Android SQLite and never deletes a row that
  // transactions reference.
  static Future<void> upsertCustomers(
      List<Map<String, dynamic>> customers) async {
    final db = await init();
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final c in customers) {
        final row = {
          'Name': c['customerName'],
          'Address': c['address'] ?? '',
          'Town': c['townID']?.toString() ?? '',
          'IsNarcotics': c['isNarcoticsAllowed'] == true ? 1 : 0,
        };
        batch.insert('Customer', {'CustomerID': c['customerId'], ...row},
            conflictAlgorithm: ConflictAlgorithm.ignore);
        batch.update('Customer', row,
            where: 'CustomerID = ?', whereArgs: [c['customerId']]);
      }
      await batch.commit(noResult: true);
    });
  }

  static Future<void> upsertProducts(
      List<Map<String, dynamic>> products) async {
    final db = await init();
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final p in products) {
        final row = {
          'Name': p['Name'],
          'Code': p['Code'],
          'ProductType': p['ProductType'] ?? 'Medicine',
          'UnitPrice': (p['UnitPrice'] ?? 0.0).toDouble(),
          'AvailableQty': p['AvailableQty'] ?? 0,
        };
        batch.insert('Product', {'ProductID': p['ProductID'], ...row},
            conflictAlgorithm: ConflictAlgorithm.ignore);
        batch.update('Product', row,
            where: 'ProductID = ?', whereArgs: [p['ProductID']]);
      }
      await batch.commit(noResult: true);
    });
  }

  // ================= CUSTOMER UPSERT =================
  static Future<void> upsertCustomer(Map<String, dynamic> customer) async {
    final db = await init();

    int count = await db.update(
      'Customer',
      {
        'Name': customer['customerName'],
        'Address': customer['address'] ?? '',
        'Town': customer['townID']?.toString() ?? '',
        'IsNarcotics': customer['isNarcoticsAllowed'] == true ? 1 : 0,
      },
      where: 'CustomerID=?',
      whereArgs: [customer['customerId']],
    );

    if (count == 0) {
      await db.insert('Customer', {
        'CustomerID': customer['customerId'],
        'Name': customer['customerName'],
        'Address': customer['address'] ?? '',
        'Town': customer['townID']?.toString() ?? '',
        'IsNarcotics': customer['isNarcoticsAllowed'] == true ? 1 : 0,
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
  /// Fallback only, for lines without a ProductID (drafts saved by older versions).
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

  // ================= OWNER (salesman) =================
  /// Logged-in user's id; transactions are stamped with it and each user
  /// only sees, edits and pushes their own (plus unstamped older rows).
  static Future<String> currentUserId() async =>
      (await SharedPreferences.getInstance()).getString('userId') ?? '';

  static const _ownerFilter = '(UserID = ? OR UserID IS NULL)';

  static Future<int> createTransactionWithDetails({
    required int customerId,
    required String type, // 'Order'|'Return'|'Cash'|'Draft'
    required List<Map<String, dynamic>> details,
    double? cashAmount,
    String? remarks,
    int? vendorGroupId, // Cash only
  }) async {
    final db = await init();
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('userId') ?? '';
    final userName = prefs.getString('username') ?? '';

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
        'VendorGroupID': type == 'Cash' ? vendorGroupId : null,
        'UserID': userId,
        'UserName': userName,
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
    int? vendorGroupId, // Cash only
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
          'VendorGroupID': type == 'Cash' ? vendorGroupId : null,
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
        where:
            'CustomerID = ? AND Type = ? AND date(Date) = ? AND SyncStatus != ? AND $_ownerFilter',
        whereArgs: [customerId, type, dayStr, 'Synced', await currentUserId()],
        limit: 1);
    if (rows.isNotEmpty) return rows.first['TransactionID'] as int;
    return null;
  }

  /// The logged-in user's transactions (and unstamped older ones).
  static Future<List<Map<String, dynamic>>> getAllTransactionsForOverview(
      {int limit = 500}) async {
    final db = await init();
    return await db.query('"Transaction"',
        where: _ownerFilter,
        whereArgs: [await currentUserId()],
        orderBy: 'Date DESC',
        limit: limit);
  }

  /// IDs of the logged-in user's transactions waiting to be pushed.
  static Future<List<int>> getUnsyncedTransactionIds() async {
    final db = await init();
    final rows = await db.query('"Transaction"',
        columns: ['TransactionID'],
        where: "SyncStatus IN ('Pending', 'Failed') AND $_ownerFilter",
        whereArgs: [await currentUserId()]);
    return rows.map((r) => r['TransactionID'] as int).toList();
  }

  static Future<List<Map<String, dynamic>>> getTransactionWithDetails(
      int transactionId) async {
    final db = await init();
    final rows = await db.rawQuery('''
      SELECT t.TransactionID, t.CustomerID, t.Type, t.Date, t.TotalAmount, 
             t.CashAmount, t.Remarks, t.VendorGroupID, t.UserID, t.UserName,
             t.SyncStatus, t.UpdatedAt,
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

  /// The logged-in user's transactions taken between [from] and [to]
  /// (whole days, inclusive): id, type and sync status, oldest first.
  static Future<List<Map<String, dynamic>>> getTransactionsInRange(
      DateTime from, DateTime to) async {
    final db = await init();
    final start = DateTime(from.year, from.month, from.day);
    final end =
        DateTime(to.year, to.month, to.day).add(const Duration(days: 1));
    return db.query('"Transaction"',
        columns: ['TransactionID', 'Type', 'SyncStatus', 'Date'],
        where: 'Date >= ? AND Date < ? AND $_ownerFilter',
        whereArgs: [
          start.toIso8601String(),
          end.toIso8601String(),
          await currentUserId(),
        ],
        orderBy: 'Date ASC');
  }

  /// Money per day and type for the last [days] days ending today, for the
  /// Insights screen. Keys are yyyy-MM-dd; values are {Order, Cash, Return}
  /// sums (Cash counts CashAmount, the others TotalAmount, like Home does).
  static Future<Map<String, Map<String, double>>> getDailyTotals(
      int days) async {
    final db = await init();
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day)
        .subtract(Duration(days: days - 1));
    final rows = await db.rawQuery('''
      SELECT date(Date) AS d, Type,
             SUM(CASE WHEN Type = 'Cash' THEN IFNULL(CashAmount, 0)
                      ELSE IFNULL(TotalAmount, 0) END) AS amt
      FROM "Transaction"
      WHERE Date >= ? AND $_ownerFilter
      GROUP BY d, Type
    ''', [start.toIso8601String(), await currentUserId()]);
    final out = <String, Map<String, double>>{};
    for (final r in rows) {
      final d = r['d'] as String?;
      final t = r['Type'] as String?;
      if (d == null || t == null) continue;
      (out[d] ??= {})[t] = (r['amt'] as num?)?.toDouble() ?? 0;
    }
    return out;
  }

  /// Best customers by order value over the last [days] days.
  static Future<List<Map<String, dynamic>>> getTopCustomers(int days,
      {int limit = 5}) async {
    final db = await init();
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day)
        .subtract(Duration(days: days - 1));
    return db.rawQuery('''
      SELECT c.Name AS name, SUM(IFNULL(t.TotalAmount, 0)) AS amt, COUNT(*) AS n
      FROM "Transaction" t JOIN Customer c ON c.CustomerID = t.CustomerID
      WHERE t.Type = 'Order' AND t.Date >= ? AND (t.UserID = ? OR t.UserID IS NULL)
      GROUP BY t.CustomerID
      ORDER BY amt DESC
      LIMIT ?
    ''', [start.toIso8601String(), await currentUserId(), limit]);
  }

  /// Deletes several transactions (and their details) in one DB transaction.
  static Future<void> deleteTransactions(List<int> ids) async {
    if (ids.isEmpty) return;
    final db = await init();
    final marks = List.filled(ids.length, '?').join(',');
    await db.transaction((txn) async {
      await txn.delete('TransactionDetail',
          where: 'TransactionID IN ($marks)', whereArgs: ids);
      await txn.delete('"Transaction"',
          where: 'TransactionID IN ($marks)', whereArgs: ids);
    });
  }

  static Future<void> deleteTransaction(int transactionId) async {
    final db = await init();
    await db.transaction((txn) async {
      await txn.delete('TransactionDetail',
          where: 'TransactionID = ?', whereArgs: [transactionId]);
      await txn.delete('"Transaction"',
          where: 'TransactionID = ?', whereArgs: [transactionId]);
    });
  }

  /// Deletes the logged-in user's transactions only; other salesmen's
  /// unpushed work, customers, products and settings stay.
  static Future<void> clearTransactions() async {
    final db = await init();
    final me = await currentUserId();
    await db.transaction((txn) async {
      await txn.delete('TransactionDetail',
          where: 'TransactionID IN (SELECT TransactionID FROM "Transaction" '
              'WHERE $_ownerFilter)',
          whereArgs: [me]);
      await txn.delete('"Transaction"', where: _ownerFilter, whereArgs: [me]);
    });
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
