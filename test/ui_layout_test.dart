import 'dart:io';
import 'dart:typed_data';

import 'package:dmc/about_screen.dart';
import 'package:dmc/main.dart' show navigatorKey;
import 'package:dmc/theme/app_theme.dart';
import 'package:dmc/theme/theme_controller.dart';
import 'package:dmc/widgets/app_background.dart';
import 'package:dmc/widgets/app_toast.dart';
import 'package:dmc/widgets/brand_logo.dart';
import 'package:dmc/widgets/floating_nav_bar.dart';
import 'package:dmc/widgets/logo_badge.dart';
import 'package:dmc/widgets/motion.dart';
import 'package:dmc/widgets/notification_dropdown.dart';
import 'package:dmc/widgets/overview_hero.dart';
import 'package:dmc/widgets/page_hero.dart';
import 'package:dmc/widgets/skeleton.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Phone sizes the app must fit (logical px). Small + landscape are the ones
/// that usually break.
const sizes = <String, Size>{
  'small 320x568': Size(320, 568),
  'common 360x640': Size(360, 640),
  'large 411x891': Size(411, 891),
  'landscape 640x360': Size(640, 360),
};

/// 1.3 is the highest font scale the app allows (main.dart clamps there).
const scales = [1.0, 1.3];

/// Same wrapper the real app uses (background + shimmer scope + text clamp).
Future<void> pumpApp(
  WidgetTester t,
  Widget home, {
  Size size = const Size(360, 640),
  double scale = 1.0,
  bool dark = false,
  bool reduceMotion = false,
}) async {
  AppColors.setDark(dark);
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    navigatorKey: navigatorKey,
    debugShowCheckedModeBanner: false,
    theme: AppTheme.current(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(scale),
        disableAnimations: reduceMotion,
      ),
      child: AppBackground(child: ShimmerScope(child: child!)),
    ),
    home: home,
  ));
}

/// Runs [body] on every size x scale x theme combination.
void layoutMatrix(
  String name,
  Widget Function() build, {
  Future<void> Function(WidgetTester t)? after,
}) {
  for (final s in sizes.entries) {
    for (final scale in scales) {
      for (final dark in [false, true]) {
        testWidgets('$name | ${s.key} | x$scale | ${dark ? 'dark' : 'light'}',
            (t) async {
          SharedPreferences.setMockInitialValues({});
          await pumpApp(t, build(), size: s.value, scale: scale, dark: dark);
          await t.pumpAndSettle(const Duration(milliseconds: 100));
          if (after != null) await after(t);
          // A RenderFlex overflow shows up here as an exception.
          expectNoException(t);
        });
      }
    }
  }
}

/// Fails with the full widget path of an overflow, not just the summary.
void expectNoException(WidgetTester t) {
  final e = t.takeException();
  expect(
      e == null ? null : (e is FlutterError ? e.toStringDeep() : e.toString()),
      isNull);
}

List<Map<String, dynamic>> fakeNotifications(int n) => [
      for (var i = 0; i < n; i++)
        {
          'id': i + 1,
          'type': ['info', 'success', 'warning', 'danger'][i % 4],
          'title': 'Stock for Panadol Extra 500mg tablets is low (#$i)',
          'body':
              'Please check the warehouse and place a new request before Friday evening.',
          'date': '07 Nov 2026, 10:3$i',
          'unread': i.isEven,
        },
    ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // flutter test draws text in "Ahem" (every letter as wide as it is tall),
  // which is about twice the real width and gives false overflows. Load the
  // real Roboto that ships with the Flutter SDK (the font Android uses).
  setUpAll(() async {
    final root = Platform.environment['FLUTTER_ROOT'] ?? 'D:/Flutter/flutter';
    final loader = FontLoader('Roboto');
    for (final name in ['roboto-regular', 'roboto-medium', 'roboto-bold']) {
      final bytes =
          await File('$root/bin/cache/artifacts/material_fonts/$name.ttf')
              .readAsBytes();
      loader.addFont(Future.value(ByteData.view(bytes.buffer)));
    }
    await loader.load();
  });

  // About screen reads the app version through a plugin.
  setUpAll(() => PackageInfo.setMockInitialValues(
        appName: 'Softifex',
        packageName: 'com.example.dmc',
        version: '1.0.0',
        buildNumber: '1',
        buildSignature: '',
      ));

  group('layout: no overflow', () {
    layoutMatrix(
      'OverviewHero (long numbers)',
      () => SingleChildScrollView(
        child: OverviewHero(
          dateLabel: 'Wednesday, 30 September',
          orderTotal: 123456789,
          cashTotal: 98765432,
          entries: 128,
          notSynced: 12,
          onExport: () {},
          onPrevDay: () {},
          onNextDay: () {},
          onPickDate: () {},
        ),
      ),
    );

    layoutMatrix(
      'FloatingNavBar (5 tabs, badge)',
      () => Align(
        alignment: Alignment.bottomCenter,
        child: FloatingNavBar(
          currentIndex: 3,
          onTap: (_) {},
          items: const [
            NavItem(icon: Icons.home_outlined, label: 'Home'),
            NavItem(icon: Icons.shopping_cart_outlined, label: 'Order'),
            NavItem(icon: Icons.payments_outlined, label: 'Cash', badge: 120),
            NavItem(icon: Icons.assignment_return_outlined, label: 'Return'),
            NavItem(icon: Icons.person_outline, label: 'Profile'),
          ],
        ),
      ),
    );

    layoutMatrix(
      'PageHero (long text + trailing)',
      () => Padding(
        padding: const EdgeInsets.all(16),
        child: PageHero(
          icon: Icons.tune_rounded,
          title: 'A really long page title that must not overflow the card',
          subtitle:
              'And a long help line that explains what this page is for in detail',
          trailing: const Icon(Icons.chevron_right, color: Colors.white),
        ),
      ),
    );

    layoutMatrix(
      'FormSection + fields',
      () => Scaffold(
          body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FormSection(
            title: 'Customer and amount details for this payment',
            icon: Icons.person_outline,
            children: [
              TextField(
                  decoration: AppInput.decoration('Customer',
                      hint: 'Search customer...')),
              const SizedBox(height: 12),
              TextField(decoration: AppInput.decoration('Enter Amount (Rs)')),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: TextField(decoration: AppInput.decoration('QTY'))),
                const SizedBox(width: 12),
                Expanded(
                    child: TextField(
                        decoration: AppInput.decoration('Available',
                            hint: 'Available QTY'))),
              ]),
            ],
          ),
        ],
      )),
    );

    layoutMatrix(
      'About screen',
      () => const AboutScreen(),
      after: (t) async {
        // Developer details you provided must be on screen.
        expect(find.text('Muhammad Zayem', skipOffstage: false), findsOneWidget);
      },
    );
  });

  group('overlays', () {
    for (final s in sizes.entries) {
      for (final dark in [false, true]) {
        testWidgets('notification dropdown | ${s.key} | ${dark ? 'dark' : 'light'}',
            (t) async {
          SharedPreferences.setMockInitialValues({});
          late BuildContext ctx;
          await pumpApp(
            t,
            Scaffold(
              body: Builder(builder: (c) {
                ctx = c;
                return const SizedBox.expand();
              }),
            ),
            size: s.value,
            scale: 1.3,
            dark: dark,
          );
          // Bell sits in the middle of the action row, not the screen edge.
          final bell = Rect.fromLTWH(s.value.width - 150, 24, 48, 48);
          showNotificationDropdown(
            context: ctx,
            anchor: bell,
            initial: fakeNotifications(7),
            onChanged: (_, __) {},
          );
          await t.pumpAndSettle(const Duration(milliseconds: 100));

          expectNoException(t);
          // 5 latest only, and a way to see the rest.
          expect(find.textContaining('Stock for Panadol'), findsNWidgets(5));
          // The list is given OLDEST first (ids 1..7): the panel must still
          // show the latest five (ids 7..3) and hide the two oldest.
          expect(find.textContaining('(#6)'), findsOneWidget);
          expect(find.textContaining('(#2)'), findsOneWidget);
          expect(find.textContaining('(#1)'), findsNothing);
          expect(find.textContaining('(#0)'), findsNothing);
          expect(find.text('View all (7)'), findsOneWidget);
          // Panel is fully on screen.
          final r = t.getRect(find.text('Notifications').first);
          expect(r.left, greaterThanOrEqualTo(0));
          expect(r.right, lessThanOrEqualTo(s.value.width));
        });
      }
    }

    for (final s in sizes.entries) {
      testWidgets('toast (3 lines) | ${s.key}', (t) async {
        SharedPreferences.setMockInitialValues({});
        late BuildContext ctx;
        await pumpApp(
          t,
          Scaffold(body: Builder(builder: (c) {
            ctx = c;
            return const SizedBox.expand();
          })),
          size: s.value,
          scale: 1.3,
        );
        for (final type in ToastType.values) {
          AppToast.show(ctx,
              'Saved in Downloads/softifex-orders\nExported_Transactions_20261001_20261107_1762500000000.csv',
              type: type);
          await t.pump(const Duration(milliseconds: 600));
          expect(find.textContaining('Saved in Downloads'), findsOneWidget);
        }
        expectNoException(t);
        // Replaced, never stacked.
        expect(find.textContaining('Saved in Downloads'), findsOneWidget);
        await t.pump(const Duration(seconds: 6));
        await t.pumpAndSettle();
        expect(find.textContaining('Saved in Downloads'), findsNothing);
      });
    }
  });

  group('shimmer / motion', () {
    testWidgets('shared ticker sleeps when no skeleton is on screen',
        (t) async {
      late StateSetter set;
      var show = true;
      await pumpApp(
        t,
        Scaffold(
          body: StatefulBuilder(builder: (c, s) {
            set = s;
            return show
                ? const SkeletonBox(width: 80, height: 12)
                : const SizedBox(width: 80, height: 12);
          }),
        ),
      );
      await t.pump(const Duration(milliseconds: 400));
      expect(t.binding.hasScheduledFrame, isTrue, reason: 'shimmer running');
      set(() => show = false);
      // Would time out if the ticker kept running with nothing to animate.
      await t.pumpAndSettle(const Duration(milliseconds: 100),
          EnginePhase.sendSemanticsUpdate, const Duration(seconds: 3));
    });

    testWidgets('reduce motion: skeleton is static', (t) async {
      await pumpApp(t, const Scaffold(body: TransactionListSkeleton()),
          reduceMotion: true);
      await t.pumpAndSettle(const Duration(milliseconds: 100),
          EnginePhase.sendSemanticsUpdate, const Duration(seconds: 3));
      expectNoException(t);
    });

    testWidgets('reduce motion: FadeSlideIn shows at once', (t) async {
      await pumpApp(
          t, const Scaffold(body: FadeSlideIn(index: 5, child: Text('hi'))),
          reduceMotion: true);
      await t.pump();
      final fade = t.widget<FadeTransition>(find
          .ancestor(of: find.text('hi'), matching: find.byType(FadeTransition))
          .first);
      expect(fade.opacity.value, 1.0);
    });
  });

  group('theme + logos', () {
    for (final dark in [false, true]) {
      testWidgets('BrandLogo asset | ${dark ? 'dark' : 'light'}', (t) async {
        await pumpApp(t, const Scaffold(body: Center(child: BrandLogo())),
            dark: dark);
        final img = t.widget<Image>(find.byType(Image));
        final provider = (img.image as ResizeImage).imageProvider as AssetImage;
        expect(provider.assetName,
            dark ? 'assets/images/logo_dark.png' : 'assets/images/logo_light.png');
      });
    }

    testWidgets('LogoBadge: emblem sits on a white disc in dark mode',
        (t) async {
      await pumpApp(t, const Scaffold(body: Center(child: LogoBadge())),
          dark: true);
      final disc = t.widget<Container>(find
          .descendant(
              of: find.byType(LogoBadge), matching: find.byType(Container))
          .first);
      expect((disc.decoration as BoxDecoration).color, Colors.white);
    });

    test('ThemeController: saves, restores and follows the system', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({'themeMode': 'dark'});
      final c = ThemeController.instance;
      await c.init();
      expect(c.mode, ThemeMode.dark);
      expect(AppColors.isDark, isTrue);

      await c.setMode(ThemeMode.light);
      expect(AppColors.isDark, isFalse);
      expect((await SharedPreferences.getInstance()).getString('themeMode'),
          'light');

      await c.setFollowSystem(true);
      expect(c.followsSystem, isTrue);
      await c.setFollowSystem(false);
      expect(c.followsSystem, isFalse, reason: 'leaves system mode');
    });

    testWidgets('system brightness change is followed (system mode only)',
        (t) async {
      SharedPreferences.setMockInitialValues({});
      final c = ThemeController.instance;
      await c.init();
      await c.setMode(ThemeMode.system);
      t.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      c.didChangePlatformBrightness();
      expect(AppColors.isDark, isTrue);

      await c.setMode(ThemeMode.light);
      t.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      c.didChangePlatformBrightness();
      expect(AppColors.isDark, isFalse, reason: 'manual choice wins');
      t.platformDispatcher.clearPlatformBrightnessTestValue();
    });
  });
}
