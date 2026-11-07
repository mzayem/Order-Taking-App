import 'dart:async';
import 'dart:math' as math;

import 'package:dmc/db/database.dart';
import 'package:dmc/theme/app_theme.dart';
import 'package:dmc/url_setup.dart';
import 'package:dmc/widgets/brand_logo.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dmc/biometric_lock_screen.dart';
import 'package:dmc/services/biometric_login.dart';
import 'package:dmc/services/session_policy.dart';
import 'login_screen.dart';
import 'home_screen.dart';

class Splashscreen extends StatefulWidget {
  const Splashscreen({super.key});

  @override
  State<Splashscreen> createState() => _SplashscreenState();
}

class _SplashscreenState extends State<Splashscreen>
    with SingleTickerProviderStateMixin {
  // The full Softifex logo pops up in 750 ms; the hold + fade-out to the next
  // screen add about 500 ms, so the whole splash stays under 1.5 s.
  late final AnimationController _controller = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 750));

  // 0.55 -> 1.07 -> 1.0: a small overshoot, like a pop-up. The overshoot is
  // built into the sequence itself: feeding an overshooting curve such as
  // easeOutBack into a TweenSequence trips its "t must be 0..1" assertion.
  late final Animation<double> _pop = TweenSequence<double>([
    TweenSequenceItem(
        tween: Tween(begin: 0.55, end: 1.07)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 65),
    TweenSequenceItem(
        tween: Tween(begin: 1.07, end: 1.0)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 35),
  ]).animate(_controller);

  // Appears quickly, so the logo never looks like it is stuck half-visible.
  late final Animation<double> _fade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.4, curve: Curves.easeOut));

  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;

    // The route decision runs alongside the animation, not after it.
    final route = _decideRoute();
    final Future<void> animation;
    if (MediaQuery.of(context).disableAnimations) {
      _controller.value = 1; // reduce motion: logo is simply there
      animation = Future.value();
    } else {
      animation = _controller.forward().orCancel.catchError((_) {});
    }
    _go(route, animation);
  }

  Future<Widget> _decideRoute() async {
    final prefs = await SharedPreferences.getInstance();
    final isUrlSaved = prefs.getBool('isUrlSaved') ?? false;
    // Token, not userId: devices logged in before the token update log in once more.
    final isLoggedIn = prefs.getString('token') ?? "";

    if (!isUrlSaved) return const UrlSetupScreen();
    if (await AppDatabase.isLicenseExpired()) {
      // Saving the URL again fetches a fresh licence.
      return const UrlSetupScreen(
          message: "License expired. Tap Save to renew it.");
    }
    if (isLoggedIn.isNotEmpty) {
      // Every 30 days the password is needed again (the token is refreshed
      // by signing in), and fingerprint / face is switched off until then.
      if (await SessionPolicy.passwordLoginDue()) {
        await SessionPolicy.clearSession(forgetBiometric: true);
        return const LoginScreen(
            message: 'Please sign in with your password to continue.');
      }
      // With fingerprint / face login on, every fresh app start is locked.
      if (await BiometricLogin.isAvailable() &&
          await BiometricLogin.isEnabled()) {
        return const BiometricLockScreen();
      }
      return const HomeScreen();
    }
    return const LoginScreen();
  }

  Future<void> _go(Future<Widget> route, Future<void> animation) async {
    final results = await Future.wait<Object?>([route, animation]);
    // A short hold so the finished logo is actually seen.
    await Future.delayed(const Duration(milliseconds: 250));
    if (!mounted) return;
    final next = results[0] as Widget;
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 250),
        pageBuilder: (_, __, ___) => next,
        transitionsBuilder: (_, a, __, child) =>
            FadeTransition(opacity: a, child: child),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Fits any phone: up to 340 wide, never wider than the screen minus margins.
    final logoWidth = math.min(MediaQuery.sizeOf(context).width - 56, 340.0);

    return Scaffold(
      body: Center(
        child: RepaintBoundary(
          child: FadeTransition(
            opacity: _fade,
            child: ScaleTransition(
              scale: _pop,
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  // Soft light behind the logo (one static gradient).
                  Container(
                    width: logoWidth * 1.15,
                    height: logoWidth * 0.62,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(colors: [
                        AppColors.accent
                            .withValues(alpha: AppColors.isDark ? 0.28 : 0.18),
                        AppColors.accent.withValues(alpha: 0),
                      ]),
                    ),
                  ),
                  BrandLogo(width: logoWidth),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
