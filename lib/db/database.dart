// lib/db/database.dart
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
      version: 2, // incremented version for new column (userEmail)
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON;');
      },
      onCreate: (db, version) async {
        await _createTables(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        // add userEmail if coming from old db
        if (oldVersion < 2) {
          await db
              .execute('ALTER TABLE "Transaction" ADD COLUMN userEmail TEXT');
        }
      },
    );

    return _db!;
  }

  static Future<void> _createTables(Database db) async {
    final statements = <String>[
      // Customer
      '''
      CREATE TABLE Customer (
        CustomerID INTEGER PRIMARY KEY AUTOINCREMENT,
        Name TEXT NOT NULL UNIQUE,
        Town TEXT
      )
      ''',

      // User
      '''
      CREATE TABLE "User" (
        UserID INTEGER PRIMARY KEY AUTOINCREMENT,
        Name TEXT NOT NULL,
        Town TEXT,
        Role TEXT NOT NULL CHECK (Role IN ('Salesman','Customer'))
      )
      ''',

      // Product
      '''
      CREATE TABLE Product (
        ProductID INTEGER PRIMARY KEY AUTOINCREMENT,
        Name TEXT NOT NULL UNIQUE,
        Code TEXT,
        UnitPrice NUMERIC NOT NULL DEFAULT 0.0,
        AvailableQty INTEGER NOT NULL DEFAULT 0
      )
      ''',

      // Transaction header (✅ added userEmail)
      '''
      CREATE TABLE "Transaction" (
        TransactionID INTEGER PRIMARY KEY AUTOINCREMENT,
        CustomerID INTEGER NOT NULL,
        Type TEXT NOT NULL CHECK(Type IN ('Order','Return','Cash','Draft')),
        Date TEXT NOT NULL DEFAULT (datetime('now')),
        TotalAmount NUMERIC NOT NULL DEFAULT 0.0,
        CashAmount NUMERIC NOT NULL DEFAULT 0.0,
        Remarks TEXT,
        SyncStatus TEXT DEFAULT 'Pending' CHECK (SyncStatus IN ('Pending','Synced','Failed')),
        RemoteTransactionID INTEGER,
        CreatedAt TEXT DEFAULT (datetime('now')),
        UpdatedAt TEXT DEFAULT (datetime('now')),
        userEmail TEXT,
        FOREIGN KEY(CustomerID) REFERENCES Customer(CustomerID) ON DELETE RESTRICT
      )
      ''',

      // TransactionDetail
      '''
      CREATE TABLE TransactionDetail (
        TransactionDetailID INTEGER PRIMARY KEY AUTOINCREMENT,
        TransactionID INTEGER NOT NULL,
        ProductID INTEGER NOT NULL,
        BatchNo TEXT,
        Qty INTEGER NOT NULL CHECK (Qty > 0),
        UnitPrice NUMERIC NOT NULL,
        TotalPrice NUMERIC NOT NULL,
        FOREIGN KEY(TransactionID) REFERENCES "Transaction"(TransactionID) ON DELETE CASCADE,
        FOREIGN KEY(ProductID) REFERENCES Product(ProductID) ON DELETE RESTRICT
      )
      ''',
    ];

    for (final stmt in statements) {
      await db.execute(stmt);
    }

    // triggers & indexes
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_transaction_customer ON "Transaction"(CustomerID)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_transaction_date ON "Transaction"(Date)');
  }

  // ---------------------- HELPERS ----------------------

  static Future<int> insertCustomerIfNotExists(String name,
      {String? town}) async {
    final db = await init();
    final rows =
        await db.query('Customer', where: 'Name = ?', whereArgs: [name]);
    if (rows.isNotEmpty) return rows.first['CustomerID'] as int;
    return await db.insert('Customer', {'Name': name, 'Town': town ?? ''});
  }

  static Future<int> insertProductIfNotExists(String name,
      {double unitPrice = 0.0, int availableQty = 0, String? code}) async {
    final db = await init();
    final rows =
        await db.query('Product', where: 'Name = ?', whereArgs: [name]);
    if (rows.isNotEmpty) return rows.first['ProductID'] as int;
    return await db.insert('Product', {
      'Name': name,
      'Code': code,
      'UnitPrice': unitPrice,
      'AvailableQty': availableQty,
    });
  }

  /// ✅ Create transaction header + details with logged-in user info
  static Future<int> createTransactionWithDetails({
    required int customerId,
    required String type, // 'Order'|'Return'|'Cash'|'Draft'
    required List<Map<String, dynamic>> details,
    double? cashAmount,
    String? remarks,
  }) async {
    final db = await init();
    final prefs = await SharedPreferences.getInstance();
    final userEmail = prefs.getString('username') ?? 'unknown';

    return await db.transaction((txn) async {
      final header = {
        'CustomerID': customerId,
        'Type': type,
        'Date': DateTime.now().toIso8601String(),
        'TotalAmount': 0.0,
        'CashAmount': cashAmount ?? 0.0,
        'Remarks': remarks ?? '',
        'SyncStatus': 'Pending',
        'CreatedAt': DateTime.now().toIso8601String(),
        'UpdatedAt': DateTime.now().toIso8601String(),
        'userEmail': userEmail, // ✅
      };

      final tId = await txn.insert('"Transaction"', header);

      for (final d in details) {
        int productId;
        if (d.containsKey('productId')) {
          productId = d['productId'] as int;
        } else {
          final name = d['productName'] as String;
          productId = await insertProductIfNotExists(name,
              unitPrice: (d['unitPrice'] ?? 0.0) as double,
              availableQty: (d['availableQty'] ?? 0) as int);
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

  /// ✅ Get transactions for current logged-in user only
  static Future<List<Map<String, dynamic>>> getAllTransactionsForOverview(
      {int limit = 500}) async {
    final db = await init();
    final prefs = await SharedPreferences.getInstance();
    final userEmail = prefs.getString('username') ?? '';

    return await db.query(
      '"Transaction"',
      where: 'userEmail = ?',
      whereArgs: [userEmail],
      orderBy: 'Date DESC',
      limit: limit,
    );
  }

  static Future<List<Map<String, dynamic>>> getTransactionWithDetails(
      int transactionId) async {
    final db = await init();
    return await db.rawQuery('''
      SELECT t.TransactionID, t.CustomerID, t.Type, t.Date, t.TotalAmount, 
             t.CashAmount, t.Remarks, t.SyncStatus, t.UpdatedAt,
             td.TransactionDetailID, td.ProductID, td.BatchNo, td.Qty, 
             td.UnitPrice, td.TotalPrice, p.Name AS ProductName
      FROM "Transaction" t
      LEFT JOIN TransactionDetail td ON td.TransactionID = t.TransactionID
      LEFT JOIN Product p ON p.ProductID = td.ProductID
      WHERE t.TransactionID = ?
    ''', [transactionId]);
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
      whereArgs: [transactionId],
    );
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
      whereArgs: [transactionId],
    );
  }

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
