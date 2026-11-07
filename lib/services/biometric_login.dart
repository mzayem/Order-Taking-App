import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

/// Fingerprint / face (or phone PIN) sign-in.
///
/// The username and password are kept in the Android Keystore through
/// secure storage, and only used after the phone confirms the owner.
/// Every call is safe: any failure just means "not available".
class BiometricLogin {
  BiometricLogin._();

  static final _auth = LocalAuthentication();
  static const _storage = FlutterSecureStorage();
  static const _kUser = 'bio_username';
  static const _kPass = 'bio_password';

  /// The phone has biometrics (or a screen lock) set up.
  static Future<bool> isAvailable() async {
    try {
      return await _auth.isDeviceSupported() &&
          (await _auth.getAvailableBiometrics()).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> isEnabled() async {
    try {
      return (await _storage.read(key: _kPass)) != null;
    } catch (_) {
      return false;
    }
  }

  static Future<void> enable(String username, String password) async {
    await _storage.write(key: _kUser, value: username);
    await _storage.write(key: _kPass, value: password);
  }

  static Future<void> disable() async {
    try {
      await _storage.delete(key: _kUser);
      await _storage.delete(key: _kPass);
    } catch (_) {}
  }

  /// Shows the system prompt; on success returns the saved login.
  static Future<({String username, String password})?> authenticate() async {
    try {
      final ok = await _auth.authenticate(
        localizedReason: 'Confirm it is you to sign in to Softifex',
        biometricOnly: true,
      );
      if (!ok) return null;
      final u = await _storage.read(key: _kUser);
      final p = await _storage.read(key: _kPass);
      if (u == null || p == null) return null;
      return (username: u, password: p);
    } catch (_) {
      return null;
    }
  }
}
