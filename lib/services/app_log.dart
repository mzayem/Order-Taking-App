import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../db/database.dart';

enum LogLevel { info, warning, error }

/// Categories shown as filters on the Activity page.
class LogCategory {
  LogCategory._();
  static const sync = 'sync';
  static const api = 'api';
  static const auth = 'auth';
  static const notification = 'notification';
  static const app = 'app';

  static const all = [sync, api, auth, notification, app];
}

class LogEntry {
  const LogEntry({
    required this.id,
    required this.time,
    required this.level,
    required this.category,
    required this.message,
  });

  final int id;
  final DateTime time;
  final LogLevel level;
  final String category;
  final String message;

  static LogEntry fromRow(Map<String, Object?> r) => LogEntry(
        id: r['LogID'] as int,
        time: DateTime.fromMillisecondsSinceEpoch(r['Ts'] as int),
        level: LogLevel.values.firstWhere((l) => l.name == r['Level'],
            orElse: () => LogLevel.info),
        category: r['Category'] as String,
        message: r['Message'] as String,
      );
}

/// Writes to and reads from the local AppLog table. Logging never throws:
/// a failed write must not break the work being logged.
class AppLog {
  AppLog._();

  static const _maxMessage = 1000;
  static const _maxRows = 5000; // oldest rows are trimmed past this
  static int _writes = 0;

  static Future<void> add(
      LogLevel level, String category, String message) async {
    try {
      final db = await AppDatabase.init();
      final text = message.length > _maxMessage
          ? '${message.substring(0, _maxMessage)}...'
          : message;
      await db.insert('AppLog', {
        'Ts': DateTime.now().millisecondsSinceEpoch,
        'Level': level.name,
        'Category': category,
        'Message': text,
      });
      // Trim now and then, not on every write.
      if (++_writes % 100 == 0) {
        await db.execute(
            'DELETE FROM AppLog WHERE LogID <= (SELECT MAX(LogID) FROM AppLog) - ?',
            [_maxRows]);
      }
    } catch (e) {
      debugPrint('AppLog write failed: $e');
    }
  }

  static Future<void> info(String category, String message) =>
      add(LogLevel.info, category, message);
  static Future<void> warning(String category, String message) =>
      add(LogLevel.warning, category, message);
  static Future<void> error(String category, String message) =>
      add(LogLevel.error, category, message);

  static (String, List<Object>) _where(LogLevel? level, String? category) {
    final parts = <String>[];
    final args = <Object>[];
    if (level != null) {
      parts.add('Level = ?');
      args.add(level.name);
    }
    if (category != null) {
      parts.add('Category = ?');
      args.add(category);
    }
    return (parts.isEmpty ? '' : 'WHERE ${parts.join(' AND ')}', args);
  }

  /// Newest first, [pageSize] rows per page (page is 0-based).
  static Future<List<LogEntry>> page({
    LogLevel? level,
    String? category,
    int page = 0,
    int pageSize = 50,
  }) async {
    final db = await AppDatabase.init();
    final (where, args) = _where(level, category);
    final rows = await db.rawQuery(
        'SELECT * FROM AppLog $where ORDER BY Ts DESC, LogID DESC LIMIT ? OFFSET ?',
        [...args, pageSize, page * pageSize]);
    return rows.map(LogEntry.fromRow).toList();
  }

  static Future<int> count({LogLevel? level, String? category}) async {
    final db = await AppDatabase.init();
    final (where, args) = _where(level, category);
    return Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM AppLog $where', args)) ??
        0;
  }

  static Future<void> clear() async {
    final db = await AppDatabase.init();
    await db.delete('AppLog');
  }
}
