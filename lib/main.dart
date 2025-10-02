import 'package:dmc/home_screen.dart';
import 'package:dmc/login_screen.dart';
import 'package:dmc/splash_screen.dart';
import 'package:dmc/url_setup.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  Future<Widget> _decideStartScreen() async {
    final prefs = await SharedPreferences.getInstance();
    final isLoggedIn = prefs.getBool('isLoggedIn') ?? false;
    final isUrlSaved = prefs.getBool('isUrlSaved') ?? false;

    if (isLoggedIn) {
      return const HomeScreen();
    } else if (isUrlSaved) {
      return const LoginScreen();
    } else {
      return const UrlSetupScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Flutter App',
      theme: ThemeData(primarySwatch: Colors.teal),
      home: const Splashscreen(),
    );
  }
}
