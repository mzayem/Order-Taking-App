import 'package:dmc/db/database.dart';
import 'package:dmc/splash_screen.dart';
import 'package:flutter/material.dart';

// http://app.dmcgroup.pk:2004
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // await AppDatabase.deleteDatabaseFile();
  await AppDatabase.init(); // initialize DB
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DMC App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.teal),
      home: const Splashscreen(),
    );
  }
}
