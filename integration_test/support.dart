// Shared helpers for the device tests: seeding the real SQLite database and
// driving the real app (waiting in real time for timers / DB / platform work).

import 'package:dmc/db/database.dart';
import 'package:dmc/main.dart';
import 'package:dmc/theme/theme_controller.dart';
import 'package:dmc/widgets/floating_nav_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

const kMe = 'user-1';

String todayKey() {
  final d = DateTime.now();
  return '${d.year}-${d.month}-${d.day}'; // same format as ApiService._today
}

/// Fresh state: logged in, valid licence, server unreachable, two customers
/// and three products. Everything else empty.
Future<Database> seed({String? baseUrl}) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.clear();
  await prefs.setBool('isUrlSaved', true);
  // Default: a closed port = no server. Pass a FakeApi url for online tests.
  await prefs.setString('baseUrl', baseUrl ?? 'http://127.0.0.1:9');
  await prefs.setString('token', 'test-token');
  await prefs.setString('userId', kMe);
  await prefs.setString('username', 'Test Salesman');
  await prefs.setStringList('townIds', ['1']);
  await prefs.setStringList('townNames', ['Karachi']);
  await prefs.setString('lastDataRefresh', todayKey()); // skip the daily sync

  final db = await AppDatabase.init();
  for (final t in [
    'TransactionDetail',
    '"Transaction"',
    'Customer',
    'Product',
    'Settings',
    'AppLog',
    'VendorGroup',
  ]) {
    await db.delete(t);
  }
  await AppDatabase.upsertSettings(
    settingsId: 's1',
    companyName: 'Test Co',
    apiUrl: baseUrl ?? 'http://127.0.0.1:9',
    payload: '{}',
    signature: 'sig',
    expDate:
        DateTime.now().add(const Duration(days: 30)).millisecondsSinceEpoch,
  );
  await AppDatabase.upsertCustomers([
    {
      'customerId': 1,
      'customerName': 'Ali Medical Store',
      'address': 'Main Road',
      'townID': 1,
      'isNarcoticsAllowed': true
    },
    {
      'customerId': 2,
      'customerName': 'Bilal Pharmacy',
      'address': 'Market',
      'townID': 1,
      'isNarcoticsAllowed': false
    },
  ]);
  await AppDatabase.upsertProducts([
    {
      'ProductID': 10,
      'Name': 'Panadol 500mg',
      'Code': '',
      'UnitPrice': 20.0,
      'AvailableQty': 500,
      'ProductType': 'Medicine'
    },
    {
      'ProductID': 11,
      'Name': 'Brufen 400mg',
      'Code': '',
      'UnitPrice': 35.5,
      'AvailableQty': 100,
      'ProductType': 'Medicine'
    },
    {
      'ProductID': 12,
      'Name': 'Calpol Syrup',
      'Code': '',
      'UnitPrice': 90.0,
      'AvailableQty': 40,
      'ProductType': 'Medicine'
    },
  ]);
  return db;
}

Future<int> insertTx(
  Database db, {
  required int customerId,
  required String type,
  required DateTime date,
  double total = 0,
  String status = 'Pending',
  String? userId = kMe,
  String remarks = '',
  List<({int productId, int qty, double price, String batch})> details =
      const [],
}) async {
  final id = await db.insert('"Transaction"', {
    'CustomerID': customerId,
    'Type': type,
    'Date': date.toIso8601String(),
    'TotalAmount': total,
    'CashAmount': type == 'Cash' ? total : 0.0,
    'Remarks': remarks,
    'UserID': userId,
    'UserName': 'Test Salesman',
    'SyncStatus': status,
    'CreatedAt': date.toIso8601String(),
    'UpdatedAt': date.toIso8601String(),
  });
  for (final d in details) {
    await db.insert('TransactionDetail', {
      'TransactionID': id,
      'ProductID': d.productId,
      'BatchNo': d.batch,
      'Qty': d.qty,
      'UnitPrice': d.price,
      'TotalPrice': d.qty * d.price,
    });
  }
  return id;
}

/// Pumps the whole app (skipping main() so the Android notification
/// permission dialog does not steal focus) and waits for the Home screen.
Future<void> launch(WidgetTester t) async {
  await ThemeController.instance.init();
  await t.pumpWidget(const MyApp());
  // Splash uses real timers + DB reads: wait for the result, not for
  // "no more frames".
  await waitFor(t, find.text('Overview'),
      reason: 'should land on Home (logged in, licence valid)');
  await settle(t);
}

/// Pumps for [ms] of real time (animations finish, async callbacks run).
/// Not pumpAndSettle: skeleton shimmers and timers never "settle".
Future<void> settle(WidgetTester t, [int ms = 900]) async {
  for (var i = 0; i < ms / 100; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

/// Scrolls the target into view first (Profile is taller than a 360x640
/// phone), then taps it.
Future<void> tapScrolling(WidgetTester t, Finder f) async {
  await t.ensureVisible(f.first);
  await t.pump(const Duration(milliseconds: 400));
  await t.tap(f.first);
}

/// Prints every visible text, to explain a failure.
void dumpTexts(String where) {
  final texts = find
      .byType(Text)
      .evaluate()
      .map((e) => (e.widget as Text).data ?? '')
      .where((x) => x.isNotEmpty)
      .toList();
  // ignore: avoid_print
  print('DUMP>>> $where: $texts');
}

Future<void> waitFor(WidgetTester t, Finder f,
    {int seconds = 20, String? reason}) async {
  final end = DateTime.now().add(Duration(seconds: seconds));
  while (DateTime.now().isBefore(end)) {
    await t.pump(const Duration(milliseconds: 100));
    if (f.evaluate().isNotEmpty) return;
  }
  fail(
      'Timed out after ${seconds}s waiting for ${f.describeMatch(Plurality.one)}'
      '${reason == null ? '' : ' ($reason)'}');
}

/// Polls [cond] (e.g. a DB query) while pumping frames.
Future<void> eventually(WidgetTester t, Future<bool> Function() cond,
    {int seconds = 15, String? reason}) async {
  final end = DateTime.now().add(Duration(seconds: seconds));
  while (DateTime.now().isBefore(end)) {
    await t.pump(const Duration(milliseconds: 100));
    if (await cond()) return;
  }
  fail(
      'Condition not met within ${seconds}s${reason == null ? '' : ' ($reason)'}');
}

Future<void> tapNav(WidgetTester t, String label) async {
  await t.tap(find.descendant(
      of: find.byType(FloatingNavBar), matching: find.text(label)));
  await settle(t);
}

/// Label of the text field that currently has the keyboard focus.
String? focusedLabel() {
  final ctx = FocusManager.instance.primaryFocus?.context;
  if (ctx == null) return null;
  String? label;
  ctx.visitAncestorElements((e) {
    final w = e.widget;
    if (w is TextField) {
      label = w.decoration?.labelText;
      return false;
    }
    return true;
  });
  return label;
}

Finder field(String label) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == label);

Future<void> typeIn(WidgetTester t, String label, String text) async {
  await t.ensureVisible(field(label));
  await t.enterText(field(label), text);
  await t.pump(const Duration(milliseconds: 150));
}

/// Presses the keyboard's Enter / Next / Done key.
Future<void> pressEnter(WidgetTester t, TextInputAction a) async {
  await t.testTextInput.receiveAction(a);
  await t.pump(const Duration(milliseconds: 300));
  await settle(t);
}
