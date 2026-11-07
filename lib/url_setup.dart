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
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      urlController.text = prefs.getString('baseUrl') ?? '';
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

    /// 🔹 ADD http automatically if user didn't type it
    if (!url.startsWith("http://") && !url.startsWith("https://")) {
      url = "http://$url";
    }

    final cleanUrl = url.replaceAll(RegExp(r'/+$'), '');

    setState(() => isLoading = true);

    try {
      /// 🔹 STEP 1: GET SETTINGS
      final settingRes = await http
          .get(Uri.parse("$cleanUrl/api/Setting"))
          .timeout(const Duration(seconds: 10));

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

      final licenseRes = await http.get(Uri.parse(licenseUrl));

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
            TextField(
              controller: urlController,
              decoration: const InputDecoration(
                labelText: "Enter API URL",
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.link),
              ),
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
