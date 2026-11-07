import 'package:flutter/material.dart';
import 'package:dmc/widgets/app_toast.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'config/company_info.dart';
import 'theme/app_theme.dart';
import 'widgets/logo_badge.dart';
import 'widgets/motion.dart';
import 'widgets/skeleton.dart';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  String? _version;

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) {
        setState(() => _version = '${info.version} (${info.buildNumber})');
      }
    }).catchError((_) {
      if (mounted) setState(() => _version = '');
    });
  }

  void _copy(String label, String value) {
    Clipboard.setData(ClipboardData(text: value));
    AppToast.show(context, '$label copied', type: ToastType.success);
  }

  static List<_Field> _present(List<_Field> f) =>
      f.where((x) => x.value.trim().isNotEmpty).toList();

  @override
  Widget build(BuildContext context) {
    final developer = _present(const [
      _Field(Icons.business_outlined, 'Company', CompanyInfo.companyName),
      _Field(Icons.code, 'Developer', CompanyInfo.developerName),
      _Field(Icons.language, 'Company website', CompanyInfo.website),
      _Field(Icons.public, 'Softifex website', CompanyInfo.productWebsite),
      _Field(Icons.location_on_outlined, 'Address', CompanyInfo.address),
    ]);
    final contact = _present(const [
      _Field(Icons.call_outlined, 'Phone', CompanyInfo.phone),
      _Field(Icons.chat_outlined, 'WhatsApp', CompanyInfo.whatsapp),
      _Field(Icons.mail_outline, 'Email', CompanyInfo.email),
    ]);
    final support = _present(const [
      _Field(Icons.support_agent, 'Support email', CompanyInfo.supportEmail),
      _Field(Icons.phone_in_talk_outlined, 'Support phone',
          CompanyInfo.supportPhone),
      _Field(Icons.schedule, 'Support hours', CompanyInfo.supportHours),
      _Field(Icons.verified_outlined, 'Licence', CompanyInfo.licenceText),
    ]);

    var section = 0;
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          FadeSlideIn(
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.xl),
                gradient: heroGradient(),
                boxShadow: [
                  BoxShadow(
                      color: AppColors.heroStart.withValues(alpha: 0.30),
                      blurRadius: 20,
                      offset: const Offset(0, 10)),
                ],
              ),
              child: Stack(
                children: [
                  Positioned(
                    right: -50,
                    top: -60,
                    child: Container(
                      width: 200,
                      height: 200,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(colors: [
                          AppColors.accent.withValues(alpha: 0.35),
                          AppColors.accent.withValues(alpha: 0),
                        ]),
                      ),
                    ),
                  ),
                  // Full width, so the content centres inside the Stack.
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        vertical: 28, horizontal: 16),
                    child: Column(
                      children: [
                        const LogoBadge(size: 92),
                        const SizedBox(height: 14),
                        const Text(CompanyInfo.appName,
                            style: TextStyle(
                                fontSize: 24,
                                fontWeight: AppText.semibold,
                                color: Colors.white)),
                        if (CompanyInfo.appTagline.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(CompanyInfo.appTagline,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 12,
                                  letterSpacing: 1.6,
                                  color: AppColors.heroMuted)),
                        ],
                        if (CompanyInfo.productOf.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          const Text(CompanyInfo.productOf,
                              style:
                                  TextStyle(fontSize: 14, color: Colors.white)),
                        ],
                        const SizedBox(height: 12),
                        if (_version == null)
                          const SkeletonBox(width: 90, height: 12)
                        else if (_version!.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 5),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.12),
                              borderRadius:
                                  BorderRadius.circular(AppRadius.pill),
                            ),
                            child: Text('Version $_version',
                                style: TextStyle(
                                    fontSize: 12, color: AppColors.heroMuted)),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (developer.isNotEmpty) ...[
            const _SectionLabel('Developer'),
            FadeSlideIn(
                index: ++section,
                child: _FieldCard(fields: developer, onCopy: _copy)),
          ],
          if (contact.isNotEmpty) ...[
            const _SectionLabel('Contact'),
            FadeSlideIn(
                index: ++section,
                child: _FieldCard(fields: contact, onCopy: _copy)),
          ],
          if (support.isNotEmpty) ...[
            const _SectionLabel('Licence and support'),
            FadeSlideIn(
                index: ++section,
                child: _FieldCard(fields: support, onCopy: _copy)),
          ],
          const SizedBox(height: 24),
          Text(
            CompanyInfo.copyright.isNotEmpty
                ? CompanyInfo.copyright
                : 'Tap a row to copy it',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }
}

class _Field {
  const _Field(this.icon, this.label, this.value);
  final IconData icon;
  final String label;
  final String value;
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(6, 24, 4, 8),
        child: Text(text.toUpperCase(),
            style: TextStyle(
                fontSize: 12,
                letterSpacing: 0.8,
                fontWeight: AppText.semibold,
                color: AppColors.textSecondary)),
      );
}

class _FieldCard extends StatelessWidget {
  const _FieldCard({required this.fields, required this.onCopy});
  final List<_Field> fields;
  final void Function(String label, String value) onCopy;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < fields.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 60),
            ListTile(
              leading: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.brandSoft,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(fields[i].icon, size: 19, color: AppColors.brand),
              ),
              title: Text(fields[i].label,
                  style:
                      TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              subtitle: Text(fields[i].value,
                  style: TextStyle(fontSize: 15, color: AppColors.textPrimary)),
              trailing: Icon(Icons.copy_rounded,
                  size: 18, color: AppColors.textTertiary),
              onTap: () => onCopy(fields[i].label, fields[i].value),
            ),
          ],
        ],
      ),
    );
  }
}
