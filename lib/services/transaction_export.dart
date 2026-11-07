import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../db/database.dart';
import '../widgets/app_toast.dart';
import 'api_service.dart';
import 'app_log.dart';

/// CSV export of local transactions, shared by Home (one day) and
/// Settings (a date range). Same rows the upload sends, one line per detail.
class TransactionExport {
  TransactionExport._();

  /// Column order is fixed: new columns are only ever added at the end so
  /// sheets built on the older layout keep working.
  static const header =
      'clientId,date,customerId,type,remarks,totalAmount,productId,batchNo,qty,unitPrice,detailTotalAmount,vendorGroupId,vendorGroupName,userId,userName,syncStatus';

  /// Builds the CSV text, or null when none of [ids] has data.
  static Future<String?> buildCsv(List<int> ids) async {
    if (ids.isEmpty) return null;

    // Same payload the upload sends, so the file matches what the server gets.
    final dataList = <Map<String, dynamic>>[];
    for (final id in ids) {
      final payload = await ApiService.buildTransactionPayload(id);
      if (payload != null) dataList.add(payload);
    }
    if (dataList.isEmpty) return null;

    final vendorGroupNames = {
      for (final g in await AppDatabase.getVendorGroups())
        g['VendorGroupID']: g['Name']?.toString() ?? '',
    };

    // Salesman who took each transaction. Rows from before this was recorded
    // fall back to the logged-in user (the only user whose rows are listed).
    final prefs = await SharedPreferences.getInstance();
    final meId = prefs.getString('userId') ?? '';
    final meName = prefs.getString('username') ?? '';
    final ownerRows = await (await AppDatabase.init()).query('"Transaction"',
        columns: ['TransactionID', 'UserID', 'UserName', 'SyncStatus'],
        where: 'TransactionID IN (${List.filled(ids.length, '?').join(',')})',
        whereArgs: ids);
    final owners = {
      for (final r in ownerRows)
        r['TransactionID']: (
          (r['UserID'] as String?)?.isNotEmpty == true ? r['UserID'] : meId,
          (r['UserID'] as String?)?.isNotEmpty == true ? r['UserName'] : meName,
          // Synced / Pending / Failed, as stored on the phone
          (r['SyncStatus'] as String?) ?? 'Pending',
        ),
    };

    // Quotes a value when it holds a comma, quote or line break (standard CSV).
    String csv(Object? v) {
      final s = (v ?? '').toString();
      return RegExp(r'[",\r\n]').hasMatch(s)
          ? '"${s.replaceAll('"', '""')}"'
          : s;
    }

    final out = StringBuffer()..writeln(header);
    for (final data in dataList) {
      // Local time for people reading the sheet; the upload itself sends UTC.
      final date = DateTime.parse(data['date']).toLocal().toIso8601String();
      final vendorGroupId = data['vendorGroupId'];
      final head = [
        data['clientId'],
        date,
        data['customerId'],
        data['type'],
        data['remarks'],
        data['totalAmount'],
      ].map(csv).join(',');
      final owner = owners[data['clientId']] ?? (meId, meName, 'Pending');
      final tail = [
        vendorGroupId,
        vendorGroupNames[vendorGroupId],
        owner.$1,
        owner.$2,
        owner.$3,
      ].map(csv).join(',');

      final details = data['transactionDetails'] as List;
      if (details.isEmpty) {
        out.writeln('$head,,,,,,$tail');
      } else {
        for (final d in details) {
          final line = [
            d['productId'],
            d['batchNo'],
            d['qty'],
            d['unitPrice'],
            d['totalAmount'],
          ].map(csv).join(',');
          out.writeln('$head,$line,$tail');
        }
      }
    }
    return out.toString();
  }

  /// Public folder every export is saved in: Downloads/softifex-orders.
  static const folderName = 'softifex-orders';
  static const _androidDownloads = '/storage/emulated/0/Download';

  /// Returns the export folder, creating it again if it was deleted.
  /// Falls back to the app's own storage when Downloads is not writable, so
  /// an export never fails just because of the folder.
  static Future<Directory> ensureFolder() async {
    final candidates = <Directory>[
      if (Platform.isAndroid) Directory('$_androidDownloads/$folderName'),
      if (!Platform.isAndroid)
        if (await getDownloadsDirectory() case final d?)
          Directory('${d.path}/$folderName'),
    ];
    for (final dir in candidates) {
      try {
        await dir.create(recursive: true);
        return dir;
      } catch (e) {
        AppLog.warning(LogCategory.app, 'Export folder unavailable: $e');
      }
    }
    final base = await getExternalStorageDirectory() ??
        await getApplicationDocumentsDirectory();
    return Directory('${base.path}/$folderName').create(recursive: true);
  }

  /// Saves [csvText] in the export folder, tells the user where it went
  /// (toast), then opens the phone's share sheet.
  ///
  /// The toast shows first and stays up while the share sheet opens a moment
  /// later, so the user knows the file is already saved even if they close
  /// the share sheet. If Downloads was not writable, the toast says the file
  /// is in the app's own storage instead of claiming Downloads.
  ///
  /// Returns true when the file was saved and the share sheet opened.
  /// Throws if the file could not be saved at all (callers show the error).
  static Future<bool> saveAndShare(BuildContext context, String csvText,
      {String name = 'Transactions'}) async {
    final directory = await ensureFolder();
    final fileName =
        'Exported_${name}_${DateTime.now().millisecondsSinceEpoch}.csv';
    final path = '${directory.path}/$fileName';
    await File(path).writeAsString(csvText);
    AppLog.info(LogCategory.app, 'Exported $path');

    // Public Downloads (or the desktop downloads folder) vs app storage.
    final inDownloads = path.startsWith(_androidDownloads) ||
        (!Platform.isAndroid && path.contains('$folderName/'));

    if (context.mounted) {
      if (inDownloads) {
        AppToast.show(
          context,
          'Saved in Downloads/$folderName\n$fileName',
          type: ToastType.success,
          duration: const Duration(milliseconds: 4500),
        );
      } else {
        AppToast.show(
          context,
          'Saved in the app folder (Downloads is not available)\n$fileName',
          type: ToastType.warning,
          duration: const Duration(milliseconds: 4500),
        );
      }
    }

    // Let the toast be seen before the share sheet covers the screen.
    await Future.delayed(const Duration(milliseconds: 900));

    await SharePlus.instance.share(ShareParams(
      files: [XFile(path)],
      text: 'Transactions CSV Export',
    ));
    return true;
  }
}
