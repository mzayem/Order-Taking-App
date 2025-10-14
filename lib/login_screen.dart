import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  bool isPasswordVisible = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
          child: Center(
              child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ClipOval(
                          child: Image.asset('assets/images/splash.png',
                              width: 200, height: 200, fit: BoxFit.cover)),
                      const SizedBox(height: 20),
                      const Text("Login",
                          style: TextStyle(
                              fontSize: 28, fontWeight: FontWeight.w500)),
                      const SizedBox(height: 30),
                      TextField(
                          controller: emailController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: InputDecoration(
                              hintText: "Email",
                              prefixIcon:
                                  const Icon(Icons.email_outlined, size: 20),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6)),
                              contentPadding: const EdgeInsets.symmetric(
                                  vertical: 14, horizontal: 12))),
                      const SizedBox(height: 20),
                      TextField(
                          controller: passwordController,
                          obscureText: !isPasswordVisible,
                          decoration: InputDecoration(
                              hintText: "Password",
                              prefixIcon:
                                  const Icon(Icons.lock_outline, size: 20),
                              suffixIcon: IconButton(
                                  icon: Icon(isPasswordVisible
                                      ? Icons.visibility
                                      : Icons.visibility_off),
                                  onPressed: () => setState(() =>
                                      isPasswordVisible = !isPasswordVisible)),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6)),
                              contentPadding: const EdgeInsets.symmetric(
                                  vertical: 14, horizontal: 12))),
                      const SizedBox(height: 25),
                      SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.black,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(6))),
                              onPressed: () async {
                                final email = emailController.text.trim();
                                final password = passwordController.text.trim();
                                if (email.isEmpty || password.isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content: Text(
                                              "Please enter email and password")));
                                } else {
                                  final prefs =
                                      await SharedPreferences.getInstance();
                                  await prefs.setBool('isLoggedIn', true);
                                  Navigator.pushReplacement(
                                      context,
                                      MaterialPageRoute(
                                          builder: (_) => const HomeScreen()));
                                }
                              },
                              child: const Text("Login",
                                  style: TextStyle(
                                      fontSize: 16, color: Colors.white))))
                    ],
                  )))),
    );
  }
}
