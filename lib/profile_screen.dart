import 'package:dmc/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:dmc/widgets/app_toast.dart';
import 'package:dmc/about_screen.dart';
import 'package:dmc/activity_screen.dart';
import 'package:dmc/insights_screen.dart';
import 'package:dmc/services/app_log.dart';
import 'package:dmc/services/biometric_login.dart';
import 'package:dmc/settings_screen.dart';
import 'package:dmc/theme/app_theme.dart';
import 'package:dmc/theme/theme_controller.dart';
import 'package:dmc/widgets/logo_badge.dart';
import 'package:dmc/widgets/skeleton.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String _username = "Loading...";
  String _town = "Loading...";
  bool _loaded = false;
  bool _bioEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    BiometricLogin.isEnabled().then((v) {
      if (mounted) setState(() => _bioEnabled = v);
    });
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;

    setState(() {
      _loaded = true;
      _username = prefs.getString('username') ?? 'Unknown User';

      // assuming you saved towns like: [1,2,3] OR names
      final towns = prefs.getStringList('townNames') ?? [];
      _town = towns.isNotEmpty ? towns.join(", ") : "No Town Assigned";
    });
  }

  Future<void> _logout(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    await AppLog.info(LogCategory.auth, 'Signed out: $_username');

    // Session only: server setup (baseUrl, isUrlSaved, headerRef) stays.
    // Drafts go too, so the next user doesn't see this user's unfinished work.
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

    if (!context.mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const LoginScreen()),
      (route) => false,
    );

    AppToast.show(context, "You have been logged out.", type: ToastType.info);
  }

  void _open(Widget screen) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => screen));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Profile"),
        centerTitle: true,
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Column(
                children: [
                  // Header card: same navy gradient as the Home hero
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 28),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [AppColors.heroStart, AppColors.heroEnd],
                      ),
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      child: !_loaded
                          ? const ProfileCardSkeleton()
                          : Column(
                              children: [
                                const LogoBadge(size: 96),
                                const SizedBox(height: 14),
                                Text(
                                  _username,
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: AppText.semibold,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  "Signed in",
                                  style: TextStyle(
                                      fontSize: 13, color: AppColors.heroMuted),
                                ),
                              ],
                            ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Info card
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        ListTile(
                          leading: Icon(Icons.person_outline,
                              color: AppColors.brand),
                          title: const Text("Username"),
                          subtitle: Text(_username),
                        ),
                        const Divider(height: 1, indent: 56),
                        ListTile(
                          leading: Icon(Icons.location_city_outlined,
                              color: AppColors.brand),
                          title: const Text("Town"),
                          subtitle: Text(_town),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Fingerprint / face sign-in: turned on from the login
                  // screen (needs the password), turned off here.
                  if (_bioEnabled) ...[
                    Card(
                      clipBehavior: Clip.antiAlias,
                      child: SwitchListTile(
                        secondary:
                            Icon(Icons.fingerprint, color: AppColors.brand),
                        title: const Text("Fingerprint / face login"),
                        subtitle: const Text("Sign in without typing your password"),
                        value: true,
                        onChanged: (_) async {
                          await BiometricLogin.disable();
                          if (mounted) setState(() => _bioEnabled = false);
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Appearance (like the ERP's light / dark / system setting)
                  ListenableBuilder(
                    listenable: ThemeController.instance,
                    builder: (context, _) {
                      final theme = ThemeController.instance;
                      return Card(
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          children: [
                            SwitchListTile(
                              secondary: Icon(Icons.brightness_auto_outlined,
                                  color: AppColors.brand),
                              title: const Text("Match system"),
                              subtitle: const Text("Follow the phone's theme"),
                              value: theme.followsSystem,
                              onChanged: theme.setFollowSystem,
                            ),
                            const Divider(height: 1, indent: 56),
                            SwitchListTile(
                              secondary: Icon(Icons.dark_mode_outlined,
                                  color: AppColors.brand),
                              title: const Text("Dark mode"),
                              value: theme.isDark,
                              // Locked while following the system.
                              onChanged:
                                  theme.followsSystem ? null : theme.setDark,
                            ),
                          ],
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 16),

                  // Activity + About
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        ListTile(
                          leading: Icon(Icons.insights_rounded,
                              color: AppColors.accent),
                          title: const Text("Insights"),
                          subtitle:
                              const Text("Today vs yesterday, last 7 days"),
                          trailing: Icon(Icons.chevron_right,
                              color: AppColors.textTertiary),
                          onTap: () => _open(const InsightsScreen()),
                        ),
                        const Divider(height: 1, indent: 56),
                        ListTile(
                          leading: Icon(Icons.history, color: AppColors.blue),
                          title: const Text("Activity"),
                          subtitle: const Text("Sync results and errors"),
                          trailing: Icon(Icons.chevron_right,
                              color: AppColors.textTertiary),
                          onTap: () => _open(const ActivityScreen()),
                        ),
                        const Divider(height: 1, indent: 56),
                        ListTile(
                          leading:
                              Icon(Icons.tune_rounded, color: AppColors.brand),
                          title: const Text("Settings"),
                          subtitle:
                              const Text("Export and clear old transactions"),
                          trailing: Icon(Icons.chevron_right,
                              color: AppColors.textTertiary),
                          onTap: () => _open(const SettingsScreen()),
                        ),
                        const Divider(height: 1, indent: 56),
                        ListTile(
                          leading: Icon(Icons.info_outline,
                              color: AppColors.textSecondary),
                          title: const Text("About"),
                          trailing: Icon(Icons.chevron_right,
                              color: AppColors.textTertiary),
                          onTap: () => _open(const AboutScreen()),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverFillRemaining(
            hasScrollBody: false,
            fillOverscroll: true,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: ElevatedButton.icon(
                  onPressed: () => _logout(context),
                  style: ElevatedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 52))
                      .merge(AppButtons.dangerSoft),
                  icon: const Icon(Icons.logout),
                  label: const Text(
                    "Logout",
                    style: TextStyle(fontSize: 16),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
