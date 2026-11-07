// Runs on a real device / emulator with the real SQLite database, real fonts
// and no server (the API URL points at a closed port, so the app runs in
// offline mode, which is how salesmen often use it).
//
//   flutter test integration_test/app_flow_test.dart -d <device id>

import 'dart:async';
import 'dart:io';

import 'fake_api.dart';
import 'package:dmc/db/database.dart';
import 'package:dmc/services/api_service.dart';
import 'package:dmc/services/app_log.dart';
import 'package:dmc/services/transaction_export.dart';
import 'package:dmc/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late FakeApi api;
  setUpAll(() async {
    api = FakeApi();
    await api.start();
  });
  tearDownAll(() => api.stop());

  setUp(() async {
    api.reset();
    AppColors.setDark(false);
  });

  // ---------------------------------------------------------------------
  group('database + business logic', () {
    testWidgets('range query is inclusive by whole days', (t) async {
      final db = await seed();
      final d1 = DateTime(2026, 10, 1, 0, 0, 0);
      final d1end = DateTime(2026, 10, 1, 23, 59, 59);
      final d2 = DateTime(2026, 10, 2, 0, 0, 0);
      final a = await insertTx(db, customerId: 1, type: 'Order', date: d1);
      final b = await insertTx(db, customerId: 1, type: 'Cash', date: d1end);
      await insertTx(db, customerId: 1, type: 'Order', date: d2);

      final rows = await AppDatabase.getTransactionsInRange(
          DateTime(2026, 10, 1), DateTime(2026, 10, 1));
      expect(rows.map((r) => r['TransactionID']), [a, b]);

      final both = await AppDatabase.getTransactionsInRange(
          DateTime(2026, 10, 1), DateTime(2026, 10, 2));
      expect(both.length, 3);
    });

    testWidgets('range query ignores other salesmen', (t) async {
      final db = await seed();
      final day = DateTime(2026, 10, 5, 12);
      await insertTx(db, customerId: 1, type: 'Order', date: day);
      await insertTx(db,
          customerId: 1, type: 'Order', date: day, userId: 'someone-else');
      final rows = await AppDatabase.getTransactionsInRange(
          DateTime(2026, 10, 5), DateTime(2026, 10, 5));
      expect(rows.length, 1);
    });

    testWidgets('deleteTransactions removes headers and details together',
        (t) async {
      final db = await seed();
      final day = DateTime(2026, 10, 5, 12);
      final id = await insertTx(db,
          customerId: 1,
          type: 'Order',
          date: day,
          total: 100,
          details: [(productId: 10, qty: 5, price: 20.0, batch: '')]);
      final keep = await insertTx(db,
          customerId: 2,
          type: 'Order',
          date: day,
          details: [(productId: 11, qty: 1, price: 35.5, batch: '')]);

      await AppDatabase.deleteTransactions([id]);

      expect(
          await db.query('"Transaction"',
              where: 'TransactionID = ?', whereArgs: [id]),
          isEmpty);
      expect(
          await db.query('TransactionDetail',
              where: 'TransactionID = ?', whereArgs: [id]),
          isEmpty,
          reason: 'no orphan detail rows');
      expect(
          await db.query('TransactionDetail',
              where: 'TransactionID = ?', whereArgs: [keep]),
          hasLength(1));
      await AppDatabase.deleteTransactions([]); // no-op, must not throw
    });

    testWidgets('unsynced list = Pending + Failed of this user only',
        (t) async {
      final db = await seed();
      final now = DateTime.now();
      final p = await insertTx(db, customerId: 1, type: 'Order', date: now);
      final f = await insertTx(db,
          customerId: 1, type: 'Cash', date: now, status: 'Failed');
      await insertTx(db,
          customerId: 1, type: 'Order', date: now, status: 'Synced');
      await insertTx(db,
          customerId: 1, type: 'Order', date: now, userId: 'someone-else');
      final ids = await AppDatabase.getUnsyncedTransactionIds();
      expect(ids.toSet(), {p, f});

      await AppDatabase.markTransactionSynced(p, remoteId: 99);
      await AppDatabase.markTransactionFailed(f); // stays unsynced
      expect((await AppDatabase.getUnsyncedTransactionIds()).toSet(), {f});
    });

    testWidgets('same customer + same day merges into one pending order',
        (t) async {
      final db = await seed();
      final now = DateTime.now();
      final id = await insertTx(db, customerId: 1, type: 'Order', date: now);
      expect(await AppDatabase.findTransactionForCustomerOnDate(1, 'Order', now),
          id);
      expect(await AppDatabase.findTransactionForCustomerOnDate(2, 'Order', now),
          isNull);
      // A synced order is closed: a new one must be created instead.
      await AppDatabase.markTransactionSynced(id);
      expect(await AppDatabase.findTransactionForCustomerOnDate(1, 'Order', now),
          isNull);
    });

    testWidgets('offline upload keeps rows pending and logs the failure',
        (t) async {
      final db = await seed();
      final id = await insertTx(db,
          customerId: 1,
          type: 'Order',
          date: DateTime.now(),
          total: 100,
          details: [(productId: 10, qty: 5, price: 20.0, batch: '')]);
      final res = await ApiService.uploadTransactionIds([id]);
      expect(res['ok'], isFalse);
      expect(res['message'], contains('connect'));
      final row = (await db.query('"Transaction"',
              where: 'TransactionID = ?', whereArgs: [id]))
          .single;
      expect(row['SyncStatus'], 'Pending', reason: 'retry later, not lost');
      await Future.delayed(const Duration(milliseconds: 300));
      final logs = await AppLog.page(category: LogCategory.sync);
      expect(logs.any((l) => l.level == LogLevel.error), isTrue);
    });

    testWidgets('offline requests: how long until they give up?', (t) async {
      await seed();
      // Hard 30 s cap so a call that never returns is reported, not frozen.
      Future<String> timed(String name, Future<Object?> Function() call) async {
        final sw = Stopwatch()..start();
        try {
          final r = await call().timeout(const Duration(seconds: 30));
          return '$name -> ${r == null ? 'null' : 'data'} in ${sw.elapsedMilliseconds} ms';
        } on TimeoutException {
          return '$name -> STILL WAITING after 30 s (no timeout in the app)';
        }
      }

      final a = await timed('fetchNotifications', ApiService.fetchNotifications);
      final b = await timed('fetchVendorGroups', ApiService.fetchVendorGroups);
      // ignore: avoid_print
      print('NET>>> $a | $b');
    });

    testWidgets('CSV: columns, quoting, multi-line items, status',
        (t) async {
      final db = await seed();
      final now = DateTime.now();
      final a = await insertTx(db,
          customerId: 1,
          type: 'Order',
          date: now,
          total: 100 + 71,
          status: 'Synced',
          remarks: 'Deliver, fast "urgent"',
          details: [
            (productId: 10, qty: 5, price: 20.0, batch: ''),
            (productId: 11, qty: 2, price: 35.5, batch: ''),
          ]);
      final b = await insertTx(db,
          customerId: 2,
          type: 'Cash',
          date: now,
          total: 1500,
          status: 'Failed');

      final csv = (await TransactionExport.buildCsv([a, b]))!;
      final lines = csv.trim().split('\n');
      expect(lines.first, TransactionExport.header);
      expect(lines.first.split(',').last, 'syncStatus',
          reason: 'new column goes last so old sheets keep working');
      expect(lines.length, 1 + 2 + 1, reason: '2 items + 1 cash line');
      expect(csv, contains('"Deliver, fast ""urgent"""'));
      expect(lines[1].endsWith(',Synced'), isTrue);
      expect(lines[3].endsWith(',Failed'), isTrue);
      expect(await TransactionExport.buildCsv([]), isNull);
    });

    testWidgets('export folder: where do files really go on this phone?',
        (t) async {
      final dir = await TransactionExport.ensureFolder();
      final probe = File('${dir.path}/probe.txt');
      await probe.writeAsString('ok');
      expect(await probe.exists(), isTrue);
      await probe.delete();
      final publicDownloads =
          dir.path.startsWith('/storage/emulated/0/Download');
      // ignore: avoid_print
      print('EXPORT_DIR>>> ${dir.path} (public Downloads: $publicDownloads)');
    });

    testWidgets('activity log: paging 50, filters, clear', (t) async {
      await seed();
      for (var i = 0; i < 120; i++) {
        await AppLog.add(
            i % 4 == 0 ? LogLevel.error : LogLevel.info,
            i.isEven ? LogCategory.sync : LogCategory.api,
            'entry $i');
      }
      expect(await AppLog.count(), 120);
      expect((await AppLog.page(page: 0)).length, 50);
      expect((await AppLog.page(page: 2)).length, 20);
      expect((await AppLog.page(page: 3)).length, 0);
      expect(await AppLog.count(level: LogLevel.error), 30);
      expect(await AppLog.count(category: LogCategory.api), 60);
      expect(
          await AppLog.count(
              level: LogLevel.error, category: LogCategory.api),
          0,
          reason: 'errors are on even entries = sync only');
      final newest = (await AppLog.page(page: 0)).first;
      expect(newest.message, 'entry 119', reason: 'newest first');
      await AppLog.clear();
      expect(await AppLog.count(), 0);
    });
  });

  // ---------------------------------------------------------------------
  group('app flows (offline)', () {
    testWidgets('cold start lands on Home; every tab opens without errors',
        (t) async {
      await seed();
      final sw = Stopwatch()..start();
      await launch(t);
      // ignore: avoid_print
      print('STARTUP>>> splash to Home in ${sw.elapsedMilliseconds} ms');
      for (final tab in ['Order', 'Cash', 'Return', 'Profile', 'Home']) {
        await tapNav(t, tab);
        expect(t.takeException(), isNull, reason: 'tab $tab');
      }
    });

    testWidgets('Order: keyboard flow, save, clear, back to customer',
        (t) async {
      final db = await seed();
      await launch(t);
      await tapNav(t, 'Order');

      await typeIn(t, 'Customer', 'ali');
      await pressEnter(t, TextInputAction.next);
      expect(focusedLabel(), 'Product', reason: 'customer chosen -> product');

      await typeIn(t, 'Product', 'pana');
      await pressEnter(t, TextInputAction.next);
      expect(focusedLabel(), 'QTY', reason: 'product chosen -> quantity');

      await typeIn(t, 'QTY', '5');
      await pressEnter(t, TextInputAction.done);
      expect(find.text('Selected Products'), findsOneWidget);
      expect(focusedLabel(), 'Product', reason: 'added -> ready for next item');

      // second product through the same chain
      await typeIn(t, 'Product', 'brufen');
      await pressEnter(t, TextInputAction.next);
      await typeIn(t, 'QTY', '2');
      await pressEnter(t, TextInputAction.done);
      expect(focusedLabel(), 'Product');

      await t.ensureVisible(find.widgetWithText(ElevatedButton, 'Save'));
      await t.tap(find.widgetWithText(ElevatedButton, 'Save'));
      await eventually(t, () async => (await db.query('"Transaction"')).isNotEmpty,
          reason: 'order saved');
      await settle(t);

      final rows = await db.query('"Transaction"');
      expect(rows, hasLength(1));
      expect(rows.single['Type'], 'Order');
      expect(rows.single['SyncStatus'], 'Pending');
      expect(rows.single['TotalAmount'], 5 * 20.0 + 2 * 35.5);
      expect(rows.single['UserID'], kMe);
      expect(await db.query('TransactionDetail'), hasLength(2));

      expect(find.text('Selected Products'), findsNothing, reason: 'form cleared');
      expect(focusedLabel(), 'Customer', reason: 'ready for the next customer');
    });

    testWidgets('Order: same customer again updates, never duplicates',
        (t) async {
      final db = await seed();
      await launch(t);
      await tapNav(t, 'Order');
      for (var round = 0; round < 2; round++) {
        await typeIn(t, 'Customer', 'ali');
        await pressEnter(t, TextInputAction.next);
        await typeIn(t, 'Product', 'pana');
        await pressEnter(t, TextInputAction.next);
        await typeIn(t, 'QTY', '${round + 1}');
        await pressEnter(t, TextInputAction.done);
        await t.ensureVisible(find.widgetWithText(ElevatedButton, 'Save'));
        await t.tap(find.widgetWithText(ElevatedButton, 'Save'));
        await settle(t, 1500); // save + form reset
      }
      expect(await db.query('"Transaction"'), hasLength(1),
          reason: 'one pending order per customer per day');
    });

    testWidgets('Cash: Enter chain, save, clear, back to customer', (t) async {
      final db = await seed();
      await launch(t);
      await tapNav(t, 'Cash');

      await typeIn(t, 'Select Customer', 'bilal');
      await pressEnter(t, TextInputAction.next);
      expect(focusedLabel(), 'Enter Amount (Rs)');

      await typeIn(t, 'Enter Amount (Rs)', '1500');
      await pressEnter(t, TextInputAction.next);
      expect(focusedLabel(), 'Remarks (optional)');

      await t.ensureVisible(find.text('Save Cash Payment'));
      await t.tap(find.text('Save Cash Payment'));
      await eventually(t, () async => (await db.query('"Transaction"')).isNotEmpty,
          reason: 'cash saved');
      await settle(t);

      final rows = await db.query('"Transaction"');
      expect(rows, hasLength(1));
      expect(rows.single['Type'], 'Cash');
      expect(rows.single['TotalAmount'], 1500.0);
      expect(rows.single['CustomerID'], 2);
      expect(focusedLabel(), 'Select Customer', reason: 'ready for next');
    });

    testWidgets('Cash: rejects empty and zero amounts', (t) async {
      final db = await seed();
      await launch(t);
      await tapNav(t, 'Cash');
      await typeIn(t, 'Select Customer', 'ali');
      await pressEnter(t, TextInputAction.next);
      await t.ensureVisible(find.text('Save Cash Payment'));
      await t.tap(find.text('Save Cash Payment'));
      await settle(t);
      expect(find.text('Enter amount'), findsOneWidget);
      await typeIn(t, 'Enter Amount (Rs)', '0');
      await t.tap(find.text('Save Cash Payment'));
      await settle(t);
      expect(find.text('Enter valid positive number'), findsOneWidget);
      expect(await db.query('"Transaction"'), isEmpty);
    });

    testWidgets('Return: Enter chain Customer > Product > QTY > Batch',
        (t) async {
      final db = await seed();
      await launch(t);
      await tapNav(t, 'Return');

      await typeIn(t, 'Select Customer...', 'ali');
      await pressEnter(t, TextInputAction.next);
      expect(focusedLabel(), 'Select Product....');

      await typeIn(t, 'Select Product....', 'pana');
      await pressEnter(t, TextInputAction.next);
      expect(focusedLabel(), 'QTY');

      await typeIn(t, 'QTY', '2');
      await pressEnter(t, TextInputAction.next);
      expect(focusedLabel(), 'Batch No');

      // Batch check needs the server: offline it must refuse, not crash,
      // and nothing may be added.
      await typeIn(t, 'Batch No', 'B-1');
      await pressEnter(t, TextInputAction.done);
      await settle(t, 2000); // offline batch check fails -> toast
      expect(t.takeException(), isNull);
      expect(await db.query('"Transaction"'), isEmpty);
    });

    testWidgets('Home: hero totals, chips, selection, day navigation',
        (t) async {
      final db = await seed();
      final now = DateTime.now();
      await insertTx(db,
          customerId: 1,
          type: 'Order',
          date: now,
          total: 1000,
          status: 'Synced',
          details: [(productId: 10, qty: 50, price: 20.0, batch: '')]);
      await insertTx(db,
          customerId: 2,
          type: 'Order',
          date: now,
          total: 300,
          details: [(productId: 10, qty: 15, price: 20.0, batch: '')]);
      await insertTx(db,
          customerId: 1, type: 'Cash', date: now, total: 500);
      await insertTx(db,
          customerId: 2, type: 'Return', date: now, total: 200, status: 'Failed');

      await launch(t);
      await waitFor(t, find.text('ALI MEDICAL STORE'), reason: 'list loaded');
      await settle(t, 1200); // totals count up
      expect(find.text('Rs 1,300'), findsOneWidget, reason: 'orders = 1000+300');
      expect(find.text('Rs 500'), findsOneWidget, reason: 'cash');
      expect(find.text('3 not synced'), findsOneWidget,
          reason: 'pending order + pending cash + failed return');
      expect(find.text('4 entries'), findsOneWidget);
      expect(find.text('ALI MEDICAL STORE'), findsWidgets);
      // long-press selects, "All (n)" selects everything
      await t.longPress(find.text('ALI MEDICAL STORE').first);
      await settle(t);
      expect(find.text('All (1)'), findsOneWidget);
      await t.tap(find.text('All (1)'));
      await settle(t);
      expect(find.text('All (4)'), findsOneWidget);
      await t.tap(find.byTooltip('Cancel Selection'));
      await settle(t);

      // status chips are further down the list
      final listScroll = find.byType(Scrollable).last;
      await t.scrollUntilVisible(find.text('Uploaded'), 120,
          scrollable: listScroll);
      await t.scrollUntilVisible(find.text('Upload Failed'), 120,
          scrollable: listScroll);
      await t.scrollUntilVisible(find.text('ALI MEDICAL STORE').first, -120,
          scrollable: listScroll);

      // yesterday has nothing; back to today shows everything again
      await t.tap(find.byTooltip('Previous day'));
      await settle(t);
      expect(find.text('No Orders Yet'), findsOneWidget);
      await t.tap(find.byTooltip('Next day'));
      await settle(t);
      expect(find.text('4 entries'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('Notification bell: offline panel opens and closes',
        (t) async {
      await seed();
      await launch(t);
      await t.tap(find.byTooltip('Notifications'));
      try {
        await waitFor(t, find.text('Could not reach the server.'),
            seconds: 25, reason: 'offline message');
      } catch (_) {
        dumpTexts('bell panel');
        rethrow;
      }
      expect(find.text('Notifications'), findsOneWidget);
      expect(find.text('View all'), findsOneWidget);
      await t.tapAt(const Offset(5, 400)); // outside the panel
      await settle(t);
      expect(find.text('Could not reach the server.'), findsNothing);
    });

    testWidgets('Settings: counts for the date range', (t) async {
      final db = await seed();
      final now = DateTime.now();
      await insertTx(db,
          customerId: 1,
          type: 'Order',
          date: now.subtract(const Duration(days: 10)),
          status: 'Synced');
      await insertTx(db,
          customerId: 1,
          type: 'Cash',
          date: now.subtract(const Duration(days: 9)),
          status: 'Synced');
      await insertTx(db,
          customerId: 2,
          type: 'Order',
          date: now.subtract(const Duration(days: 5)));
      await insertTx(db, // outside the default 30 day range
          customerId: 2,
          type: 'Order',
          date: now.subtract(const Duration(days: 90)),
          status: 'Synced');

      await launch(t);
      await tapNav(t, 'Profile');
      await tapScrolling(t, find.text('Settings'));
      await waitFor(t, find.text('Not synced'), reason: 'counts loaded');
      await settle(t, 1000);
      expect(find.text('Total'), findsOneWidget);
      // 3 in range: 2 synced, 1 not (the 90 day old one is outside)
      Finder stat(String label, String value) => find.descendant(
          of: find
              .ancestor(of: find.text(label), matching: find.byType(Container))
              .first,
          matching: find.text(value));
      expect(stat('Total', '3'), findsOneWidget);
      expect(stat('Synced', '2'), findsOneWidget);
      expect(stat('Not synced', '1'), findsOneWidget);
      expect(find.text('Not synced'), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, 'Export'), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, 'Export & clear'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('Insights: compares with yesterday and shows 7 days', (t) async {
      final db = await seed();
      final now = DateTime.now();
      await insertTx(db, customerId: 1, type: 'Order', date: now, total: 500);
      await insertTx(db,
          customerId: 1,
          type: 'Order',
          date: now.subtract(const Duration(days: 1)));
      await launch(t);
      await tapNav(t, 'Profile');
      await tapScrolling(t, find.text('Insights'));
      await waitFor(t, find.text('Last 7 days'), reason: 'insights loaded');
      expect(find.text('Orders'), findsWidgets);
      expect(find.textContaining('vs yesterday'), findsWidgets);
      expect(find.textContaining('Top customers'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('Back on a tab goes to Home first', (t) async {
      await seed();
      await launch(t);
      await tapNav(t, 'Cash');
      expect(find.text('Cash payment'), findsWidgets);
      await t.binding.handlePopRoute();
      await settle(t);
      expect(find.text('Overview'), findsWidgets);
      expect(t.takeException(), isNull);
    });

    testWidgets('About: shows your developer details, hides empty fields',
        (t) async {
      await seed();
      await launch(t);
      await tapNav(t, 'Profile');
      await tapScrolling(t, find.text('About'));
      await settle(t);
      for (final s in [
        'Product of Techstersol Ltd',
        'Muhammad Zayem',
        'Techstersol Ltd',
        'https://techstersol.com/',
        'https://softifex.techstersol.com/',
      ]) {
        expect(find.text(s), findsWidgets, reason: s);
      }
      expect(find.text('Phone'), findsNothing, reason: 'empty -> hidden');
      expect(find.text('Email'), findsNothing);
    });

    testWidgets('Theme: switch is instant everywhere and survives restart',
        (t) async {
      await seed();
      await launch(t);
      await tapNav(t, 'Profile');
      final lightGlass = AppColors.glassFill;

      await tapScrolling(t, find.widgetWithText(SwitchListTile, 'Match system'));
      await settle(t);
      await tapScrolling(t, find.widgetWithText(SwitchListTile, 'Dark mode'));
      await settle(t);

      expect(AppColors.isDark, isTrue);
      // Card gets its colour from the theme, so read what is really painted.
      final paint = t
          .widget<Material>(find
              .descendant(
                  of: find.byType(Card).first, matching: find.byType(Material))
              .first)
          .color;
      expect(paint, isNot(lightGlass),
          reason: 'cards on THIS page must not keep the light colour');
      expect(paint, AppColors.glassFill);
      expect(
          (await SharedPreferences.getInstance()).getString('themeMode'),
          'dark');

      // "restart": rebuild the app from saved settings
      await t.pumpWidget(const SizedBox());
      await launch(t);
      expect(AppColors.isDark, isTrue);
    });
  });

  // ---------------------------------------------------------------------
  group('with a server (fake API)', () {
    /// Customer + product + qty typed with the keyboard, ending on Batch.
    Future<void> returnUntilBatch(WidgetTester t,
        {String customer = 'ali', String batch = 'B-100'}) async {
      await typeIn(t, 'Select Customer...', customer);
      await pressEnter(t, TextInputAction.next);
      await typeIn(t, 'Select Product....', 'pana');
      await pressEnter(t, TextInputAction.next);
      await typeIn(t, 'QTY', '2');
      await pressEnter(t, TextInputAction.next);
      await typeIn(t, 'Batch No', batch);
    }

    testWidgets('Return: a batch the customer really bought is accepted + saved',
        (t) async {
      final db = await seed(baseUrl: api.baseUrl);
      api.sold(1, 10, 'B-100'); // Ali bought Panadol batch B-100
      await launch(t);
      await tapNav(t, 'Return');

      await returnUntilBatch(t);
      await pressEnter(t, TextInputAction.done);
      await waitFor(t, find.textContaining('Batch: B-100'),
          reason: 'server said yes -> row with the batch is shown');
      expect(find.text('No products added'), findsNothing);
      expect(focusedLabel(), 'Select Product....',
          reason: 'ready for the next item');

      // the app asked the server the right question
      final ask = api.calls('/batchCheck').single;
      expect(ask.body['userId'], kMe);
      expect(ask.body['productId'], 10);
      expect(ask.body['batchno'], 'B-100');
      expect(ask.body['customerId'], 1);
      expect(ask.auth, 'Bearer test-token');

      await t.ensureVisible(find.widgetWithText(ElevatedButton, 'Save'));
      await t.tap(find.widgetWithText(ElevatedButton, 'Save'));
      await eventually(t, () async => (await db.query('"Transaction"')).isNotEmpty,
          reason: 'return saved');
      await settle(t);

      final head = (await db.query('"Transaction"')).single;
      expect(head['Type'], 'Return');
      expect(head['CustomerID'], 1);
      expect(head['SyncStatus'], 'Pending');
      final line = (await db.query('TransactionDetail')).single;
      expect(line['BatchNo'], 'B-100');
      expect(line['Qty'], 2);
      expect(line['ProductID'], 10);
      expect(focusedLabel(), 'Select Customer...', reason: 'ready for next');
    });

    testWidgets('Return: a batch that was never sold is refused with the reason',
        (t) async {
      final db = await seed(baseUrl: api.baseUrl);
      api.sold(1, 10, 'B-100');
      await launch(t);
      await tapNav(t, 'Return');

      await returnUntilBatch(t, batch: 'B-999');
      await pressEnter(t, TextInputAction.done);
      await waitFor(t, find.text('Batch B-999 was not sold to this customer'),
          reason: "server's message is shown to the salesman");
      expect(find.text('No products added'), findsOneWidget);
      expect(find.textContaining('Batch: '), findsNothing);
      expect(focusedLabel(), 'Batch No', reason: 'stay on the field to fix it');
      expect(await db.query('"Transaction"'), isEmpty);
    });

    testWidgets('Return: the rule is per customer (same batch, other customer)',
        (t) async {
      await seed(baseUrl: api.baseUrl);
      api.sold(1, 10, 'B-100'); // sold to Ali only
      await launch(t);
      await tapNav(t, 'Return');

      await returnUntilBatch(t, customer: 'bilal', batch: 'B-100');
      await pressEnter(t, TextInputAction.done);
      await waitFor(t, find.text('Batch B-100 was not sold to this customer'));
      expect(api.calls('/batchCheck').single.body['customerId'], 2,
          reason: 'Bilal (id 2) is what the app asked about');
      expect(find.text('No products added'), findsOneWidget);
    });

    testWidgets('sync: success marks rows Synced and keeps the server id',
        (t) async {
      final db = await seed(baseUrl: api.baseUrl);
      final now = DateTime.now();
      final a = await insertTx(db,
          customerId: 1,
          type: 'Order',
          date: now,
          total: 100,
          details: [(productId: 10, qty: 5, price: 20.0, batch: '')]);
      final b = await insertTx(db, customerId: 2, type: 'Cash', date: now, total: 500);

      final res = await ApiService.syncAllTransactions();
      expect(res['ok'], isTrue);
      expect(res['synced'], 2);
      for (final id in [a, b]) {
        final row = (await db.query('"Transaction"',
                where: 'TransactionID = ?', whereArgs: [id]))
            .single;
        expect(row['SyncStatus'], 'Synced');
        expect(row['RemoteTransactionID'], isNotNull);
      }
      expect(await AppDatabase.getUnsyncedTransactionIds(), isEmpty);

      // what went over the wire
      final up = api.calls('/createTransaction').single;
      expect(up.body['userId'], kMe);
      final sent = (up.body['data'] as List).cast<Map<String, dynamic>>();
      expect(sent.map((e) => e['clientId']).toSet(), {a, b});
      expect(sent.firstWhere((e) => e['clientId'] == a)['type'], 0, reason: 'Order');
      expect(sent.firstWhere((e) => e['clientId'] == b)['type'], 1, reason: 'Cash');
      expect(sent.first['date'].toString().endsWith('Z'), isTrue,
          reason: 'sent as UTC');

      final again = await ApiService.syncAllTransactions();
      expect(again['message'], 'Everything is already synced.');
      expect(api.calls('/createTransaction'), hasLength(1),
          reason: 'nothing left, so no second request');
    });

    testWidgets('sync: one rejected row stays for retry, the rest go through',
        (t) async {
      final db = await seed(baseUrl: api.baseUrl);
      final now = DateTime.now();
      final ok = await insertTx(db, customerId: 1, type: 'Cash', date: now, total: 100);
      final bad = await insertTx(db, customerId: 2, type: 'Cash', date: now, total: 200);
      api.rejectClientIds = {bad};

      final res = await ApiService.syncAllTransactions();
      expect(res['ok'], isFalse);
      expect(res['synced'], 1);
      expect(res['message'], contains('failed 1'));
      expect(res['message'], contains('Customer is blocked'));
      Future<String?> status(int id) async => (await db.query('"Transaction"',
              where: 'TransactionID = ?', whereArgs: [id]))
          .single['SyncStatus'] as String?;
      expect(await status(ok), 'Synced');
      expect(await status(bad), 'Failed');
      expect((await AppDatabase.getUnsyncedTransactionIds()).toSet(), {bad});

      api.rejectClientIds = {}; // server fixed
      final retry = await ApiService.syncAllTransactions();
      expect(retry['ok'], isTrue);
      expect(await status(bad), 'Synced');
    });

    testWidgets('sync: expired session (401) keeps the data, drops the token',
        (t) async {
      final db = await seed(baseUrl: api.baseUrl);
      final id = await insertTx(db, customerId: 1, type: 'Cash', date: DateTime.now(), total: 10);
      api.unauthorized = true;

      final res = await ApiService.syncAllTransactions();
      expect(res['ok'], isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('token'), isNull, reason: 'must log in again');
      expect(
          (await db.query('"Transaction"',
                  where: 'TransactionID = ?', whereArgs: [id]))
              .single['SyncStatus'],
          'Pending',
          reason: 'nothing lost, uploads after the next login');
    });

    testWidgets('Notification bell: 5 latest from the server + View all',
        (t) async {
      await seed(baseUrl: api.baseUrl);
      api.notifications = [
        for (var i = 7; i >= 1; i--)
          {
            'id': i,
            'type': 'info',
            'title': 'Notice $i',
            'body': 'Body $i',
            'date': '07 Nov 2026',
            'unread': i.isOdd,
          },
      ];
      await launch(t);
      await t.tap(find.byTooltip('Notifications'));
      await waitFor(t, find.text('Notice 7'), reason: 'server list shown');
      expect(find.textContaining('Notice '), findsNWidgets(5),
          reason: 'only the 5 latest');
      expect(find.text('View all (7)'), findsOneWidget);
      expect(find.text('4 new'), findsOneWidget);

      await t.tap(find.text('Mark all read'));
      await eventually(t, () async => api.calls('/markRead').isNotEmpty,
          reason: 'server told');
      await settle(t);
      expect(find.text('Mark all read'), findsNothing);
      expect(find.text('4 new'), findsNothing);

      await t.tap(find.text('View all (7)'));
      await waitFor(t, find.text('All caught up'),
          reason: 'full screen shows the read state');
      expect(t.takeException(), isNull);
    });
    testWidgets('Notification bell: latest 5 even if the server sends oldest first',
        (t) async {
      await seed(baseUrl: api.baseUrl);
      api.notifications = [
        for (var i = 1; i <= 7; i++) // oldest first
          {
            'id': i,
            'type': 'info',
            'title': 'Notice $i',
            'body': 'Body $i',
            'date': '07 Nov 2026',
            'unread': true,
          },
      ];
      await launch(t);
      await t.tap(find.byTooltip('Notifications'));
      await waitFor(t, find.text('Notice 7'), reason: 'newest is on top');
      for (final n in [7, 6, 5, 4, 3]) {
        expect(find.text('Notice $n'), findsOneWidget, reason: 'latest five');
      }
      expect(find.text('Notice 2'), findsNothing);
      expect(find.text('Notice 1'), findsNothing);
      expect(find.text('View all (7)'), findsOneWidget,
          reason: 'the rest is one tap away');
      // newest really first (top to bottom)
      expect(t.getTopLeft(find.text('Notice 7')).dy,
          lessThan(t.getTopLeft(find.text('Notice 3')).dy));
    });
  });

  // ---------------------------------------------------------------------
  group('small phone / large text', () {
    for (final dark in [false, true]) {
      testWidgets('no overflow on 320x568 at 1.5x text | ${dark ? 'dark' : 'light'}',
          (t) async {
        final db = await seed();
        await (await SharedPreferences.getInstance())
            .setString('themeMode', dark ? 'dark' : 'light');
        final now = DateTime.now();
        await insertTx(db,
            customerId: 1,
            type: 'Order',
            date: now,
            total: 123456789,
            remarks: 'long remarks ' * 6,
            details: [(productId: 10, qty: 5, price: 20.0, batch: '')]);
        await insertTx(db,
            customerId: 2, type: 'Cash', date: now, total: 98765432);
        await insertTx(db,
            customerId: 2,
            type: 'Return',
            date: now,
            total: 5,
            status: 'Failed');

        t.view.physicalSize = const Size(320, 568);
        t.view.devicePixelRatio = 1;
        t.platformDispatcher.textScaleFactorTestValue = 1.5;
        addTearDown(() {
          t.view.reset();
          t.platformDispatcher.clearAllTestValues();
        });

        await launch(t);
        final size = t.view.physicalSize / t.view.devicePixelRatio;
        // ignore: avoid_print
        print('VIEWPORT>>> ${size.width.toInt()}x${size.height.toInt()}');

        Future<void> check(String where) async {
          expect(t.takeException(), isNull, reason: where);
        }

        await check('Home');
        await t.tap(find.byTooltip('Notifications'));
        await settle(t);
        await check('bell dropdown');
        await t.tapAt(const Offset(5, 500));
        await settle(t);

        for (final tab in ['Order', 'Cash', 'Return']) {
          await tapNav(t, tab);
          await check(tab);
        }
        await tapNav(t, 'Profile');
        await check('Profile');
        for (final page in ['Activity', 'Settings', 'About']) {
          await tapScrolling(t, find.text(page));
          await settle(t);
          await check(page);
          await t.pageBack();
          await settle(t);
        }
      });
    }
  });

}
