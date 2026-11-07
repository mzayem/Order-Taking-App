import 'dart:async';
import 'package:dmc/db/database.dart';
import 'package:dmc/url_setup.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'login_screen.dart';
import 'home_screen.dart';

class Splashscreen extends StatefulWidget {
  const Splashscreen({super.key});

  @override
  State<Splashscreen> createState() => _SplashscreenState();
}

class _SplashscreenState extends State<Splashscreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    _controller =
        AnimationController(vsync: this, duration: const Duration(seconds: 3));
    _scaleAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));
    _fadeAnimation = Tween<double>(begin: 0, end: 1)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeIn));
    _controller.forward();

    _startAppFlow();
  }

  Future<void> _startAppFlow() async {
    await Future.delayed(const Duration(milliseconds: 1500));

    final prefs = await SharedPreferences.getInstance();
    final isUrlSaved = prefs.getBool('isUrlSaved') ?? false;
    // final isLoggedIn = prefs.getBool('isLoggedIn') ?? false;
    // Token, not userId: devices logged in before the token update log in once more.
    final isLoggedIn = prefs.getString('token') ?? "";

    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;

    if (!isUrlSaved) {
      Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => const UrlSetupScreen()));
    } else if (await AppDatabase.isLicenseExpired()) {
      // Saving the URL again fetches a fresh licence.
      if (!mounted) return;
      Navigator.pushReplacement(
          context,
          MaterialPageRoute(
              builder: (_) => const UrlSetupScreen(
                  message: "License expired. Tap Save to renew it.")));
    } else if (isLoggedIn.isNotEmpty) {
      Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => const HomeScreen()));
    } else {
      Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => const LoginScreen()));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: ScaleTransition(
          scale: _scaleAnimation,
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: ClipOval(
              child: Image.asset('assets/images/splash.png',
                  width: 250, fit: BoxFit.cover),
            ),
          ),
        ),
      ),
    );
  }
}
