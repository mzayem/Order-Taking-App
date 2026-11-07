import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Shows server notifications as phone notifications (with the default tone).
class LocalNotifier {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static const _lastKey = 'lastAlertedNotificationId';

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'softifex_alerts',
      'Alerts',
      channelDescription: 'Messages from the office',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
    ),
    iOS: DarwinNotificationDetails(presentSound: true),
  );

  static Future<void> init() async {
    await _plugin.initialize(const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    ));
    // Android 13+ asks the user once.
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  /// Alerts for unread notifications newer than the last one alerted, so
  /// each one rings only once. The first check after login just records
  /// where we are, instead of ringing for the whole backlog.
  static Future<void> alertNew(List notifications) async {
    if (notifications.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getInt(_lastKey);
    final newest = notifications
        .map((n) => n['id'] as int? ?? 0)
        .reduce((a, b) => a > b ? a : b);

    if (last != null) {
      for (final n in notifications) {
        final id = n['id'] as int? ?? 0;
        if (n['unread'] == true && id > last) {
          await _plugin.show(id, n['title']?.toString() ?? 'Notification',
              n['body']?.toString() ?? '', _details);
        }
      }
    }

    if (last == null || newest > last) await prefs.setInt(_lastKey, newest);
  }
}
