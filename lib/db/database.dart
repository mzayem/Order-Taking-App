// lib/db/database.dart
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
      version: 1,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON;');
      },
      onCreate: (db, version) async {
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

          // Transaction header
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

          // Indexes
          'CREATE INDEX IF NOT EXISTS idx_transaction_customer ON "Transaction"(CustomerID)',
          'CREATE INDEX IF NOT EXISTS idx_transaction_date ON "Transaction"(Date)',
          'CREATE INDEX IF NOT EXISTS idx_td_transaction ON TransactionDetail(TransactionID)',
          'CREATE INDEX IF NOT EXISTS idx_td_product ON TransactionDetail(ProductID)',

          // Require BatchNo for Return
          '''
          CREATE TRIGGER trg_td_require_batchno_before_insert
          BEFORE INSERT ON TransactionDetail
          WHEN (SELECT Type FROM "Transaction" WHERE TransactionID = NEW.TransactionID) = 'Return' AND NEW.BatchNo IS NULL
          BEGIN
            SELECT RAISE(ABORT, 'BatchNo is required for Return transaction details.');
          END
          ''',

          '''
          CREATE TRIGGER trg_td_require_batchno_before_update
          BEFORE UPDATE ON TransactionDetail
          WHEN (SELECT Type FROM "Transaction" WHERE TransactionID = NEW.TransactionID) = 'Return' AND NEW.BatchNo IS NULL
          BEGIN
            SELECT RAISE(ABORT, 'BatchNo is required for Return transaction details.');
          END
          ''',

          // Adjust product qty
          '''
          CREATE TRIGGER trg_td_after_insert_update_product_qty
          AFTER INSERT ON TransactionDetail
          BEGIN
            UPDATE Product
            SET AvailableQty = AvailableQty + CASE (SELECT Type FROM "Transaction" WHERE TransactionID = NEW.TransactionID)
                WHEN 'Order' THEN -NEW.Qty
                WHEN 'Return' THEN NEW.Qty
                ELSE 0 END
            WHERE ProductID = NEW.ProductID;
          END
          ''',

          // revert qty on delete
          '''
          CREATE TRIGGER trg_td_after_delete_product_qty
          AFTER DELETE ON TransactionDetail
          BEGIN
            UPDATE Product
            SET AvailableQty = AvailableQty + CASE (SELECT Type FROM "Transaction" WHERE TransactionID = OLD.TransactionID)
                WHEN 'Order' THEN OLD.Qty
                WHEN 'Return' THEN -OLD.Qty
                ELSE 0 END
            WHERE ProductID = OLD.ProductID;
          END
          ''',

          // update qty on update
          '''
          CREATE TRIGGER trg_td_after_update_product_qty
          AFTER UPDATE ON TransactionDetail
          BEGIN
            UPDATE Product
            SET AvailableQty = AvailableQty + CASE (SELECT Type FROM "Transaction" WHERE TransactionID = OLD.TransactionID)
                WHEN 'Order' THEN OLD.Qty
                WHEN 'Return' THEN -OLD.Qty
                ELSE 0 END
            WHERE ProductID = OLD.ProductID;

            UPDATE Product
            SET AvailableQty = AvailableQty + CASE (SELECT Type FROM "Transaction" WHERE TransactionID = NEW.TransactionID)
                WHEN 'Order' THEN -NEW.Qty
                WHEN 'Return' THEN NEW.Qty
                ELSE 0 END
            WHERE ProductID = NEW.ProductID;
          END
          ''',

          // recalc totals
          '''
          CREATE TRIGGER trg_td_after_insert_recalc_total
          AFTER INSERT ON TransactionDetail
          BEGIN
            UPDATE "Transaction"
            SET TotalAmount = IFNULL((SELECT SUM(TotalPrice) FROM TransactionDetail WHERE TransactionID = NEW.TransactionID), 0)
            WHERE TransactionID = NEW.TransactionID;
          END
          ''',

          '''
          CREATE TRIGGER trg_td_after_delete_recalc_total
          AFTER DELETE ON TransactionDetail
          BEGIN
            UPDATE "Transaction"
            SET TotalAmount = IFNULL((SELECT SUM(TotalPrice) FROM TransactionDetail WHERE TransactionID = OLD.TransactionID), 0)
            WHERE TransactionID = OLD.TransactionID;
          END
          ''',

          '''
          CREATE TRIGGER trg_td_after_update_recalc_total
          AFTER UPDATE ON TransactionDetail
          BEGIN
            UPDATE "Transaction"
            SET TotalAmount = IFNULL((SELECT SUM(TotalPrice) FROM TransactionDetail WHERE TransactionID = NEW.TransactionID), 0)
            WHERE TransactionID = NEW.TransactionID;
          END
          ''',
        ];

        for (final stmt in statements) {
          await db.execute(stmt);
        }
      },
    );

    return _db!;
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

  /// ✅ Create transaction header + details (handles CashAmount properly)
  static Future<int> createTransactionWithDetails({
    required int customerId,
    required String type, // 'Order'|'Return'|'Cash'|'Draft'
    required List<Map<String, dynamic>> details,
    double? cashAmount,
    String? remarks,
  }) async {
    final db = await init();
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

  static Future<List<Map<String, dynamic>>> getAllTransactionsForOverview(
      {int limit = 500}) async {
    final db = await init();
    return await db.query('"Transaction"', orderBy: 'Date DESC', limit: limit);
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
