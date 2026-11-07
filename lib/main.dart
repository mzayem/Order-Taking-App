import 'package:dmc/db/database.dart';
import 'package:dmc/services/local_notifier.dart';
import 'package:dmc/services/transaction_export.dart';
import 'package:dmc/splash_screen.dart';
import 'package:dmc/theme/app_theme.dart';
import 'package:dmc/theme/theme_controller.dart';
import 'package:dmc/widgets/app_background.dart';
import 'package:dmc/widgets/skeleton.dart';
import 'package:flutter/material.dart';

// Lets non-widget code (ApiService) send the user to Login when the session expires.
final navigatorKey = GlobalKey<NavigatorState>();

// http://app.dmcgroup.pk:2004
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // await AppDatabase.deleteDatabaseFile();
  // The DB also opens lazily on first use, so a failure here must not stop
  // the app from reaching the first screen.
  try {
    await AppDatabase.init();
  } catch (_) {}
  // Downloads/softifex-orders: created on first launch, re-created if deleted
  // (ensureFolder runs again before every export too).
  try {
    await TransactionExport.ensureFolder();
  } catch (_) {}
  // Phone notifications (asks permission once). Never block startup on it.
  try {
    await LocalNotifier.init();
  } catch (_) {}
  try {
    await ThemeController.instance
        .init(); // light / dark / system, before first frame
  } catch (_) {}
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final _theme = ThemeController.instance;

  @override
  void initState() {
    super.initState();
    _theme.addListener(_onThemeChanged);
  }

  @override
  void dispose() {
    _theme.removeListener(_onThemeChanged);
    super.dispose();
  }

  void _onThemeChanged() {
    setState(() {});
    // Screens read AppColors while building, so repaint them all once.
    _theme.rebuildAllIfNeeded(context);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DMC App',
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.current(),
      // Short cross-fade between light and dark.
      themeAnimationDuration: const Duration(milliseconds: 200),
      // One shimmer ticker shared by every skeleton placeholder.
      // The fluid gradient sits behind every page (scaffolds are see-through).
      // Large phone fonts are honoured up to 1.3x; beyond that fixed-height
      // parts (tab bar, chips, headers) would overflow on small phones.
      builder: (context, child) => MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.3,
        child: AppBackground(child: ShimmerScope(child: child!)),
      ),
      home: const Splashscreen(),
    );
  }
}
