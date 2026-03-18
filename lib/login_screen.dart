import 'dart:convert';
import 'dart:async';
import 'package:dmc/url_setup.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
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
    final username = emailController.text.trim();
    final password = passwordController.text.trim();

    if (username.isEmpty || password.isEmpty) {
      _showMessage("Enter username and password");
      return;
    }

    setState(() {
      isLoggingIn = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final baseUrl = prefs.getString('baseUrl') ?? '';

      if (baseUrl.isEmpty) {
        _showMessage("API URL not configured");
        return;
      }

      final url = "$baseUrl/api/User/login";

      print("BASE URL: $baseUrl");
      print("LOGIN URL : $url");

      final response = await http
          .post(
            Uri.parse(url),
            headers: {
              "accept": "*/*",
              "Content-Type": "application/json",
            },
            body: jsonEncode({
              "username": username,
              "password": password,
            }),
          )
          .timeout(const Duration(seconds: 20));

      print("STATUS CODE : ${response.statusCode}");
      print("RESPONSE : ${response.body}");

      if (response.statusCode != 200) {
        _showMessage("Server error : ${response.statusCode}");
        return;
      }

      final data = jsonDecode(response.body);

      if (data['status'] == 'success') {
        final prefs = await SharedPreferences.getInstance();
        final userId = data['userId'] ?? "";
        if (userId.isEmpty) {
          _showMessage("Invalid user ID from server");
          return;
        }
        await prefs.setString("userId", userId);
        await prefs.setString("username", data['username'] ?? "");
        List towns = data['towns'] ?? [];

        List<String> townIds = towns.map((t) => t['id'].toString()).toList();
        List<String> townNames =
            towns.map((t) => t['name'].toString()).toList();
        await prefs.setStringList("townIds", townIds);
        await prefs.setStringList("townNames", townNames);
        print("Saved USER ID: $userId");
        print("Saved USER NAME: $username");
        print("Saved townIds: $townIds");

        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Login Successful"),
            backgroundColor: Colors.green,
          ),
        );

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      }

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    }

    /// Timeout
    on TimeoutException catch (e) {
      print("TIMEOUT ERROR: $e");
      _showMessage("Connection timeout. Server not responding.");
    }

    /// Network issue
    on http.ClientException catch (e) {
      print("CLIENT ERROR: $e");
      _showMessage("Unable to connect to server.");
    }

    /// Any other error
    catch (e) {
      print("LOGIN ERROR: $e");
      _showMessage("Unexpected error occurred.");
    } finally {
      if (mounted) {
        setState(() {
          isLoggingIn = false;
        });
      }
    }
  }

  void _showMessage(String msg) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  // Future<void> loginUser() async {
  //   final url = Uri.parse('http://app.dmcgroup.pk:2004/api/User/login');

  //   try {
  //     final response = await http.post(
  //       url,
  //       headers: {
  //         'accept': '*/*',
  //         'Content-Type': 'application/json',
  //       },
  //       body: jsonEncode({"username": "aliraza", "password": "Chmzayem789@"}),
  //     );

  //     // Log status code
  //     print("Status Code: ${response.statusCode}");

  //     // Log raw response
  //     print("Response Body: ${response.body}");

  //     // If JSON response
  //     final data = jsonDecode(response.body);
  //     print("Decoded Response: $data");
  //   } catch (e) {
  //     print("API Error: $e");
  //   }
  // }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const UrlSetupScreen()),
            );
          },
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                ClipOval(
                  child: Image.asset(
                    'assets/images/splash.png',
                    width: 250,
                    fit: BoxFit.cover,
                  ),
                ),

                const SizedBox(height: 20),

                // InkWell(
                //   onTap: () {
                //     loginUser();
                //   },
                // child:
                Text(
                  "Login",
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                // ),

                const SizedBox(height: 30),

                /// Username
                TextField(
                  controller: emailController,
                  decoration: InputDecoration(
                    hintText: "Username",
                    prefixIcon: const Icon(Icons.person_outline, size: 20),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                /// Password
                TextField(
                  controller: passwordController,
                  obscureText: !isPasswordVisible,
                  decoration: InputDecoration(
                    hintText: "Password",
                    prefixIcon: const Icon(Icons.lock_outline, size: 20),
                    suffixIcon: IconButton(
                      icon: Icon(
                        isPasswordVisible
                            ? Icons.visibility
                            : Icons.visibility_off,
                      ),
                      onPressed: () {
                        setState(() {
                          isPasswordVisible = !isPasswordVisible;
                        });
                      },
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),

                const SizedBox(height: 25),

                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                    ),
                    onPressed: isLoggingIn ? null : _performLogin,
                    child: isLoggingIn
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            "Login",
                            style: TextStyle(fontSize: 16, color: Colors.white),
                          ),
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
