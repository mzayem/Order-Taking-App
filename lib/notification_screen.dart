import 'package:flutter/material.dart';

import 'services/api_service.dart';

class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key});

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  bool _offline = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await ApiService.fetchNotifications();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _offline = res == null;
      if (res != null) {
        _items = List<Map<String, dynamic>>.from(
            (res['notifications'] as List).map((n) => Map<String, dynamic>.from(n)));
      }
    });
  }

  Future<void> _markRead(Map<String, dynamic> n) async {
    if (n['unread'] != true) return;
    setState(() => n['unread'] = false);
    await ApiService.markNotificationRead(n['id'] as int);
  }

  Future<void> _markAllRead() async {
    setState(() {
      for (final n in _items) {
        n['unread'] = false;
      }
    });
    await ApiService.markNotificationRead();
  }

  // Server types (NotificationType, lower-cased): info, success, warning, danger.
  (IconData, Color) _style(String? type) => switch (type) {
        'success' => (Icons.check_circle, Colors.green),
        'warning' => (Icons.warning_amber_rounded, Colors.orange),
        'danger' => (Icons.error, Colors.red),
        _ => (Icons.info, Colors.teal),
      };

  @override
  Widget build(BuildContext context) {
    final hasUnread = _items.any((n) => n['unread'] == true);

    // Hand the unread count back to the bell, so Home needs no extra API call.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          Navigator.pop(
              context,
              _offline
                  ? null
                  : _items.where((n) => n['unread'] == true).length);
        }
      },
      child: Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Notifications'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          if (hasUnread)
            TextButton(
              onPressed: _markAllRead,
              child: const Text('Mark all read',
                  style: TextStyle(color: Colors.white)),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _items.isEmpty
                  ? ListView(children: [
                      const SizedBox(height: 120),
                      Center(
                        child: Text(
                          _offline
                              ? 'Could not reach the server.\nPull down to retry.'
                              : 'No notifications',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.grey),
                        ),
                      ),
                    ])
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: _items.length,
                      itemBuilder: (context, i) {
                        final n = _items[i];
                        final unread = n['unread'] == true;
                        final (icon, color) = _style(n['type']?.toString());
                        return Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          child: ListTile(
                            onTap: () => _markRead(n),
                            leading: Icon(icon, color: color),
                            title: Text(
                              n['title']?.toString() ?? '',
                              style: TextStyle(
                                  fontWeight: unread
                                      ? FontWeight.bold
                                      : FontWeight.normal),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if ((n['body'] ?? '').toString().isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(n['body'].toString()),
                                  ),
                                const SizedBox(height: 4),
                                Text(n['date']?.toString() ?? '',
                                    style: const TextStyle(
                                        fontSize: 12, color: Colors.grey)),
                              ],
                            ),
                            trailing: unread
                                ? const Icon(Icons.circle,
                                    size: 10, color: Colors.teal)
                                : null,
                          ),
                        );
                      },
                    ),
            ),
      ),
    );
  }
}
