import 'package:dmc/home_screen.dart';
import 'package:dmc/login_screen.dart';
import 'package:dmc/services/biometric_login.dart';
import 'package:dmc/theme/app_theme.dart';
import 'package:dmc/widgets/brand_logo.dart';
import 'package:flutter/material.dart';

/// Shown every time the app is opened from scratch while fingerprint / face
/// login is on and a session exists. Unlocks into Home.
class BiometricLockScreen extends StatefulWidget {
  const BiometricLockScreen({super.key});

  @override
  State<BiometricLockScreen> createState() => _BiometricLockScreenState();
}

class _BiometricLockScreenState extends State<BiometricLockScreen> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
  }

  Future<void> _unlock() async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await BiometricLogin.authenticate();
    if (!mounted) return;
    if (ok != null) {
      Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => const HomeScreen()));
    } else {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const BrandLogo(width: 250),
                const SizedBox(height: 32),
                Icon(Icons.fingerprint, size: 72, color: AppColors.brand),
                const SizedBox(height: 12),
                Text('Softifex is locked',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 6),
                Text('Use your fingerprint or face to continue',
                    style: TextStyle(color: AppColors.textSecondary)),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    style: AppButtons.primary,
                    onPressed: _busy ? null : _unlock,
                    icon: const Icon(Icons.lock_open_rounded),
                    label: const Text('Unlock'),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (_) => const LoginScreen())),
                  child: const Text('Use password instead'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
