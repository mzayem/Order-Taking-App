import 'dart:convert';
import 'dart:async';
import 'package:dmc/url_setup.dart';
import 'package:flutter/material.dart';
import 'package:dmc/widgets/app_toast.dart';
import 'package:dmc/theme/app_theme.dart';
import 'package:dmc/widgets/brand_logo.dart';
import 'package:dmc/services/app_log.dart';
import 'package:dmc/services/biometric_login.dart';
import 'package:dmc/services/session_policy.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.message});

  /// Shown once on arrival, e.g. why the user has to sign in again.
  final String? message;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  bool isPasswordVisible = false;
  bool isLoggingIn = false;
  bool _bioReady = false; // fingerprint / face login is switched on

  @override
  void initState() {
    super.initState();
    _initBiometric();
    if (widget.message != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          AppToast.show(context, widget.message!, type: ToastType.info);
        }
      });
    }
  }

  Future<void> _initBiometric() async {
    final ready = await BiometricLogin.isAvailable() &&
        await BiometricLogin.isEnabled();
    if (!mounted) return;
    setState(() => _bioReady = ready);
    if (ready) _biometricLogin(); // prompt straight away
  }

  Future<void> _biometricLogin() async {
    if (isLoggingIn) return;
    final saved = await BiometricLogin.authenticate();
    if (saved == null || !mounted) return; // cancelled: type the password
    emailController.text = saved.username;
    await _performLogin(
        username: saved.username, password: saved.password, viaBiometric: true);
  }

  /// Offered once after a normal login, if the phone supports it.
  Future<void> _offerBiometric(String username, String password) async {
    if (!await BiometricLogin.isAvailable()) return;
    final prefs = await SharedPreferences.getInstance();

    if (await BiometricLogin.isEnabled()) {
      // Keep the saved password current if it was changed.
      await BiometricLogin.enable(username, password);
      return;
    }
    if (prefs.getBool('bioAsked') == true || !mounted) return;
    await prefs.setBool('bioAsked', true);

    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.fingerprint, size: 40, color: AppColors.brand),
        title: const Text('Sign in faster?'),
        content: const Text(
            'Use your fingerprint or face to sign in next time, instead of '
            'typing your password. You can turn this off in Profile.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Not now')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Enable')),
        ],
      ),
    );
    if (yes == true) await BiometricLogin.enable(username, password);
  }

  Future<void> _performLogin(
      {String? username, String? password, bool viaBiometric = false}) async {
    username ??= emailController.text.trim();
    password ??= passwordController.text.trim();

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

      /// ALWAYS try to decode message
      Map<String, dynamic> data = {};

      try {
        data = jsonDecode(response.body);
      } catch (e) {
        print("JSON decode error: $e");
      }

      /// =========================
      /// SUCCESS LOGIN
      /// =========================
      if (response.statusCode == 200 && data['status'] == 'success') {
        final userId = data['userId'] ?? "";

        if (userId.isEmpty) {
          _showMessage("Invalid user ID from server");
          return;
        }

        await prefs.setString("userId", userId);
        await prefs.setString("token", data['token'] ?? "");
        await prefs.setString("username", data['username'] ?? "");

        List towns = data['towns'] ?? [];

        List<String> townIds = towns.map((t) => t['id'].toString()).toList();

        List<String> townNames =
            towns.map((t) => t['name'].toString()).toList();

        await prefs.setStringList("townIds", townIds);
        await prefs.setStringList("townNames", townNames);

        AppLog.info(LogCategory.auth, 'Signed in: $username');
        if (!mounted) return;

        // A typed password (not a fingerprint) restarts the 30-day clock.
        if (!viaBiometric) {
          await SessionPolicy.markPasswordLogin();
          await _offerBiometric(username, password);
        }
        if (!mounted) return;

        AppToast.show(context, "Login Successful", type: ToastType.success);

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => const HomeScreen(),
          ),
        );

        return;
      }

      /// =========================
      /// SHOW API MESSAGE FIRST
      /// =========================
      if (data.containsKey('message') &&
          data['message'] != null &&
          data['message'].toString().isNotEmpty) {
        // Saved password no longer accepted (changed on the server).
        if (viaBiometric && response.statusCode < 500) {
          await BiometricLogin.disable();
          if (mounted) setState(() => _bioReady = false);
        }
        _showMessage(data['message']);
        return;
      }

      /// =========================
      /// FALLBACK ERROR
      /// =========================
      _showMessage(
        "Server error : ${response.statusCode}",
      );
    } on TimeoutException catch (e) {
      print("TIMEOUT ERROR: $e");
      _showMessage(
        "Connection timeout. Server not responding.",
      );
    } on http.ClientException catch (e) {
      print("CLIENT ERROR: $e");
      _showMessage(
        "Unable to connect to server.",
      );
    } catch (e) {
      print("LOGIN ERROR: $e");
      _showMessage(
        "Unexpected error occurred.",
      );
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

    AppToast.show(context, msg, type: ToastType.error);
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            tooltip: 'Change API URL',
            icon: Icon(Icons.settings_ethernet_rounded,
                color: AppColors.textPrimary),
            onPressed: () {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const UrlSetupScreen()),
              );
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                const BrandLogo(width: 250),

                const SizedBox(height: 20),

                // InkWell(
                //   onTap: () {
                //     loginUser();
                //   },
                // child:
                const Text(
                  "Login",
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w600,
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
                    style: AppButtons.primary,
                    onPressed: isLoggingIn ? null : _performLogin,
                    child: isLoggingIn
                        ? SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              color: AppColors.onBrand,
                              strokeWidth: 2,
                            ),
                          )
                        : Text(
                            "Login",
                            style: TextStyle(
                                fontSize: 16, color: AppColors.onBrand),
                          ),
                  ),
                ),
                if (_bioReady) ...[
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: isLoggingIn ? null : _biometricLogin,
                    icon: const Icon(Icons.fingerprint, size: 26),
                    label: const Text('Use fingerprint / face'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      foregroundColor: AppColors.brand,
                      side: BorderSide(
                          color: AppColors.brand.withValues(alpha: 0.6)),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
