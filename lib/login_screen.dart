import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';
import 'dart:convert';
import '../db/database.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  bool isPasswordVisible = false;
  bool isLoggingIn = false;

  Future<void> _performLogin() async {
    final email = emailController.text.trim();
    final password = passwordController.text.trim();
    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Please enter email and password")));
      return;
    }
    setState(() => isLoggingIn = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final baseUrl = prefs.getString('baseUrl') ?? '';
      if (baseUrl.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("API URL not configured")));
        setState(() => isLoggingIn = false);
        return;
      }

      final response = await http
          .get(Uri.parse('$baseUrl/user_604281180'))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == 'success' && data['result'] != null) {
          final users = data['result'] as List;
          final authenticatedUser = users.firstWhere(
            (u) => u['Name'].toString().toLowerCase() == email.toLowerCase(),
            orElse: () => <String, dynamic>{},
          );
          if (authenticatedUser.isNotEmpty) {
            await prefs.setBool('isLoggedIn', true);
            await prefs.setString('username', authenticatedUser['Name']);
            await prefs.setInt('userId', authenticatedUser['UserID']);
            await prefs.setString('userRole', authenticatedUser['Role']);
            await prefs.setString('userTown', authenticatedUser['Town'] ?? '');

            // Upsert user locally
            final db = await AppDatabase.init();
            await db.insert(
                'User',
                {
                  'UserID': authenticatedUser['UserID'],
                  'Name': authenticatedUser['Name'],
                  'Town': authenticatedUser['Town'] ?? '',
                  'Role': authenticatedUser['Role'],
                },
                conflictAlgorithm: ConflictAlgorithm.replace);

            // Fetch and upsert customers
            await _fetchAndCacheCustomers(baseUrl);

            if (!mounted) return;
            Navigator.pushReplacement(
                context, MaterialPageRoute(builder: (_) => const HomeScreen()));
          } else {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Invalid credentials")));
          }
        } else {
          if (!mounted) return;
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text("Login failed")));
        }
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Server error: ${response.statusCode}")));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      if (mounted) setState(() => isLoggingIn = false);
    }
  }

  Future<void> _fetchAndCacheCustomers(String baseUrl) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/customers_604281180'))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == 'success' && data['result'] != null) {
          final list = data['result'] as List;
          for (var cust in list) {
            await AppDatabase.upsertCustomer({
              'CustomerID': cust['CustomerId'],
              'Name': cust['Name'],
              'Town': cust['Town'] ?? '',
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Error fetching customers: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ClipOval(
                  child: Image.asset('assets/images/splash.png',
                      width: 200, height: 200, fit: BoxFit.cover),
                ),
                const SizedBox(height: 20),
                const Text("Login",
                    style:
                        TextStyle(fontSize: 28, fontWeight: FontWeight.w500)),
                const SizedBox(height: 30),
                TextField(
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                      hintText: "Email",
                      prefixIcon: const Icon(Icons.email_outlined, size: 20),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6)),
                      contentPadding: const EdgeInsets.symmetric(
                          vertical: 14, horizontal: 12)),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: passwordController,
                  obscureText: !isPasswordVisible,
                  decoration: InputDecoration(
                      hintText: "Password",
                      prefixIcon: const Icon(Icons.lock_outline, size: 20),
                      suffixIcon: IconButton(
                          icon: Icon(isPasswordVisible
                              ? Icons.visibility
                              : Icons.visibility_off),
                          onPressed: () => setState(
                              () => isPasswordVisible = !isPasswordVisible)),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6)),
                      contentPadding: const EdgeInsets.symmetric(
                          vertical: 14, horizontal: 12)),
                ),
                const SizedBox(height: 25),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6))),
                    onPressed: isLoggingIn ? null : _performLogin,
                    child: isLoggingIn
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : const Text("Login",
                            style:
                                TextStyle(fontSize: 16, color: Colors.white)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
