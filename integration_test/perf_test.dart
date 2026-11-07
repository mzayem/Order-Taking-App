// Frame timing of the Home list, meant for a PROFILE build (debug builds are
// 5-10x slower and say nothing about real phones):
//
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/perf_test.dart -d <device> --profile
//
// Frames are measured with a timings callback (no debugger connection
// needed). The summary is printed (PERF>>>) and written to
// build/integration_response_data.json.

import 'package:dmc/main.dart';
import 'package:dmc/theme/theme_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.reportData = <String, dynamic>{};

  for (final dark in [false, true]) {
    testWidgets('Home list scroll | ${dark ? 'dark' : 'light'}', (t) async {
      final db = await seed();
      final now = DateTime.now();
      final batch = db.batch();
      for (var i = 0; i < 400; i++) {
        batch.insert('"Transaction"', {
          'CustomerID': 1 + i % 2,
          'Type': ['Order', 'Cash', 'Return'][i % 3],
          'Date': now.subtract(Duration(minutes: i)).toIso8601String(),
          'TotalAmount': 100.0 + i,
          'CashAmount': 0.0,
          'Remarks': '',
          'UserID': kMe,
          'UserName': 'Test Salesman',
          'SyncStatus': i % 5 == 0 ? 'Synced' : 'Pending',
          'CreatedAt': now.toIso8601String(),
          'UpdatedAt': now.toIso8601String(),
        });
      }
      await batch.commit(noResult: true);
      await ThemeController.instance.init();
      await ThemeController.instance
          .setMode(dark ? ThemeMode.dark : ThemeMode.light);

      final sw = Stopwatch()..start();
      await t.pumpWidget(const MyApp());
      await waitFor(t, find.text('ALI MEDICAL STORE'),
          seconds: 60, reason: 'list loaded');
      final loadMs = sw.elapsedMilliseconds;

      final frames = <FrameTiming>[];
      void cb(List<FrameTiming> f) => frames.addAll(f);
      SchedulerBinding.instance.addTimingsCallback(cb);
      final list = find.byType(Scrollable).last;
      for (var i = 0; i < 4; i++) {
        await t.fling(list, const Offset(0, -700), 2500);
        await t.pump(const Duration(milliseconds: 900));
      }
      for (var i = 0; i < 3; i++) {
        await t.fling(list, const Offset(0, 700), 2500);
        await t.pump(const Duration(milliseconds: 900));
      }
      await t.pump(const Duration(seconds: 1));
      SchedulerBinding.instance.removeTimingsCallback(cb);

      double ms(Duration d) => d.inMicroseconds / 1000;
      List<double> sorted(Iterable<double> v) => v.toList()..sort();
      final total = sorted(frames.map((f) => ms(f.totalSpan)));
      final build = sorted(frames.map((f) => ms(f.buildDuration)));
      final raster = sorted(frames.map((f) => ms(f.rasterDuration)));
      double p(List<double> l, double q) =>
          l.isEmpty ? 0 : l[((l.length - 1) * q).round()];
      final over16 = total.where((x) => x > 16.7).length;
      final over33 = total.where((x) => x > 33.4).length;
      final label = dark ? 'dark' : 'light';
      final summary = {
        'frames': frames.length,
        'start_to_list_ms': loadMs,
        'total_p50': p(total, .5),
        'total_p90': p(total, .9),
        'total_p99': p(total, .99),
        'total_max': total.isEmpty ? 0 : total.last,
        'build_p90': p(build, .9),
        'raster_p90': p(raster, .9),
        'over_16ms': over16,
        'over_33ms': over33,
        'pct_over_16ms': frames.isEmpty ? 0 : 100 * over16 / frames.length,
      };
      binding.reportData![label] = summary;
      // ignore: avoid_print
      print('PERF>>> $label $summary');
      expect(t.takeException(), isNull);
    });
  }
}
