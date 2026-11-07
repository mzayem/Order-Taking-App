import 'package:dmc/services/biometric_login.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Sign-in rules: a password login is required at least every [maxAge].
class SessionPolicy {
  SessionPolicy._();

  static const maxAge = Duration(days: 30);
  static const _kLastPassword = 'lastPasswordLogin';

  /// Call after a login with the typed password (not fingerprint / face).
  static Future<void> markPasswordLogin() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kLastPassword, DateTime.now().millisecondsSinceEpoch);
  }

  /// True when the last password login is more than [maxAge] ago. A session
  /// from before this rule existed starts its 30 days now.
  static Future<bool> passwordLoginDue() async {
    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getInt(_kLastPassword);
    if (last == null) {
      await markPasswordLogin();
      return false;
    }
    return DateTime.now()
            .difference(DateTime.fromMillisecondsSinceEpoch(last)) >
        maxAge;
  }

  /// Session only: server setup (baseUrl, isUrlSaved, headerRef) stays.
  /// Drafts go too, so the next user doesn't see this user's unfinished work.
  static Future<void> clearSession({bool forgetBiometric = false}) async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in [
      'token',
      'userId',
      'username',
      'townIds',
      'townNames',
      'order_draft',
      'return_draft',
      'lastAlertedNotificationId',
      'lastDataRefresh', // next user loads their own towns' customers
    ]) {
      await prefs.remove(key);
    }
    if (forgetBiometric) {
      await BiometricLogin.disable();
      await prefs.remove('bioAsked'); // offer it again after the next login
    }
  }
}
