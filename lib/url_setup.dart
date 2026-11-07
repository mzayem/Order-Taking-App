import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:dmc/widgets/app_toast.dart';
import 'package:dmc/theme/app_theme.dart';
import 'package:dmc/widgets/brand_logo.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'login_screen.dart';

import '../db/database.dart';

class UrlSetupScreen extends StatefulWidget {
  /// Shown on open, e.g. when the licence has expired.
  final String? message;
  const UrlSetupScreen({super.key, this.message});

  @override
  State<UrlSetupScreen> createState() => _UrlSetupScreenState();
}

class _UrlSetupScreenState extends State<UrlSetupScreen> {
  final TextEditingController urlController = TextEditingController();
  final TextEditingController portController = TextEditingController();
  bool isLoading = false;
  bool _useIp = false; // tab: false = web address, true = IP address

  // 192.168.1.2, 192.168.1.2:2000, optionally followed by a path.
  static final _ipLike = RegExp(r'^\d{1,3}(\.\d{1,3}){3}(:\d+)?(/.*)?$');

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      final saved = prefs.getString('baseUrl') ?? '';
      final uri = Uri.tryParse(saved);
      if (!mounted || uri == null || uri.host.isEmpty) return;
      setState(() {
        _useIp = _ipLike.hasMatch(uri.host);
        // Host and port go in their own fields. Plain http on the IP tab is
        // implied, so only an https scheme is kept in the text.
        final keepScheme = uri.scheme == 'https' || !_useIp;
        urlController.text = keepScheme ? '${uri.scheme}://${uri.host}' : uri.host;
        portController.text = uri.hasPort ? '${uri.port}' : '';
      });
    });
    if (widget.message != null) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _showMessage(widget.message!));
    }
  }

  Future<void> saveUrl() async {
    String url = urlController.text.trim();
    if (url.isEmpty) {
      _showMessage("Please enter API URL");
      return;
    }
    final prefs = await SharedPreferences.getInstance();

    // Optional port, from its own field (unless the host already carries one).
    // It is added to the host part only, before any "/path".
    final port = portController.text.trim();
    var typedScheme = url.startsWith("http://") || url.startsWith("https://");
    final rest = url.replaceFirst(RegExp(r'^https?://'), '');
    var host = rest.split('/').first;
    final path = rest.substring(host.length);
    if (port.isNotEmpty && !host.contains(':')) host = "$host:$port";
    final scheme = url.startsWith("https://") ? "https" : "http";

    /// 🔹 Which scheme to use
    // IP addresses (typed on the IP tab, or recognised anywhere) are plain
    // http unless https was typed: they rarely have a certificate. A web
    // address with no scheme is tried over https first, then http.
    if (_useIp || _ipLike.hasMatch(host)) {
      url = "$scheme://$host$path";
      typedScheme = true; // no second attempt
    } else if (typedScheme) {
      url = "$scheme://$host$path";
    } else {
      url = "https://$host$path";
    }

    // Tolerate a trailing slash (or several) and a pasted "/api" suffix.
    var cleanUrl = url
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll(RegExp(r'/+$'), '')
        .replaceAll(RegExp(r'/api$', caseSensitive: false), '')
        .replaceAll(RegExp(r'/+$'), '');

    setState(() => isLoading = true);

    try {
      /// 🔹 STEP 1: GET SETTINGS
      http.Response settingRes;
      try {
        settingRes = await http
            .get(Uri.parse("$cleanUrl/api/Setting"))
            .timeout(const Duration(seconds: 10));
      } catch (_) {
        if (typedScheme) rethrow;
        cleanUrl = cleanUrl.replaceFirst("https://", "http://");
        settingRes = await http
            .get(Uri.parse("$cleanUrl/api/Setting"))
            .timeout(const Duration(seconds: 10));
      }

      print("TEST STATUS: ${settingRes.statusCode}");
      print("TEST BODY: ${settingRes.body}");
      if (settingRes.statusCode != 200) {
        _showMessage("Invalid API URL");
        return;
      }

      final settingBody = jsonDecode(settingRes.body);

      final settingsId = settingBody['settingsId'];
      final companyName = settingBody['companyName'];
      final headerRef = settingBody['headerRef'];

      if (settingsId == null || companyName == null || headerRef == null) {
        _showMessage("Invalid settings response");
        return;
      }

      await prefs.setString('headerRef', headerRef.toString());

      /// 🔹 STEP 2: GET LICENSE
      final licenseUrl = "https://softifex-admin.techstersol.com/api/license"
          "?machineIP=$cleanUrl&id=$settingsId&name=$companyName";

      final licenseRes = await http
          .get(Uri.parse(licenseUrl))
          .timeout(const Duration(seconds: 15));

      if (licenseRes.statusCode != 200) {
        _showMessage("License verification failed");
        return;
      }

      final licenseBody = jsonDecode(licenseRes.body);

      if (licenseBody['success'] != true) {
        _showMessage("License not valid");
        return;
      }

      final payload = licenseBody['license']['payload'];
      final signature = licenseBody['license']['signature'];

      /// 🔹 Decode payload to extract exp date
      final decodedPayload = utf8.decode(base64Decode(payload));
      final payloadJson = jsonDecode(decodedPayload);
      final expDate = payloadJson['exp'];

      /// 🔹 SAVE TO SQLITE
      await AppDatabase.upsertSettings(
        settingsId: settingsId,
        companyName: companyName,
        apiUrl: cleanUrl,
        payload: payload,
        signature: signature,
        expDate: expDate,
      );

      // Saved only once the server and licence are confirmed.
      await prefs.setString('baseUrl', cleanUrl);
      await prefs.setBool('isUrlSaved', true);

      if (!mounted) return;

      AppToast.show(context, 'Successfully connected with "$companyName"',
          type: ToastType.success);

      await Future.delayed(const Duration(seconds: 1));

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    } catch (e) {
      _showMessage("Connection failed");
      debugPrint(e.toString());
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  void _showMessage(String message) {
    AppToast.show(context, message, type: ToastType.error);
  }

  @override
  void dispose() {
    urlController.dispose();
    portController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const BrandLogo(width: 240),
            const SizedBox(height: 20),
            const Text("Setup App", style: TextStyle(fontSize: 28)),
            const SizedBox(height: 30),
            _ModeTabs(
              useIp: _useIp,
              onChanged: (ip) => setState(() {
                _useIp = ip;
                urlController.clear();
                portController.clear();
              }),
            ),
            const SizedBox(height: 20),
            // Address + optional port, on both tabs: static domains and static
            // IPs often run on their own port. (A number keypad has no ":" key,
            // so the port gets its own field.)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: urlController,
                    keyboardType: _useIp
                        ? const TextInputType.numberWithOptions(decimal: true)
                        : TextInputType.url,
                    decoration: InputDecoration(
                      labelText: _useIp ? "IP address" : "API URL",
                      hintText: _useIp ? "192.168.1.2" : "api.mycompany.com",
                      border: const OutlineInputBorder(),
                      prefixIcon:
                          Icon(_useIp ? Icons.lan_outlined : Icons.link),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: portController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: "Port (optional)",
                      hintText: "2001",
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: isLoading ? null : saveUrl,
              style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 50))
                  .merge(AppButtons.primary),
              child: isLoading
                  ? CircularProgressIndicator(color: AppColors.onBrand)
                  : const Text("Save"),
            )
          ],
        ),
      ),
    );
  }
}

/// "Web address | IP address" switch.
class _ModeTabs extends StatelessWidget {
  final bool useIp;
  final ValueChanged<bool> onChanged;
  const _ModeTabs({required this.useIp, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget tab(String label, IconData icon, bool selected, bool ip) {
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onChanged(ip),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: BoxDecoration(
              color: selected ? AppColors.brand : Colors.transparent,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon,
                    size: 18,
                    color: selected ? AppColors.onBrand : AppColors.brand),
                const SizedBox(width: 6),
                Text(label,
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color:
                            selected ? AppColors.onBrand : AppColors.brand)),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.brand.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Row(children: [
        tab('URL', Icons.link, !useIp, false),
        tab('IP address', Icons.lan_outlined, useIp, true),
      ]),
    );
  }
}
