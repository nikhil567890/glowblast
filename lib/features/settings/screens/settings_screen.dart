import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/demo_ribbon.dart';
import '../../../core/widgets/app_card.dart';
import '../../../data/repositories/app_repository.dart';
import '../../../services/excel_service.dart';
import '../../auth/screens/landing_screen.dart';
import 'opt_out_screen.dart';
import 'buy_credits_screen.dart';

class SettingsScreen extends StatefulWidget {
  final AppRepository repository;

  const SettingsScreen({super.key, required this.repository});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isCheckingBackend = false;
  bool? _isBackendOnline;

  @override
  void initState() {
    super.initState();
    _checkBackendStatus();
  }

  Future<void> _checkBackendStatus() async {
    setState(() => _isCheckingBackend = true);
    final status = await widget.repository.backendClient.healthCheck();
    if (mounted) {
      setState(() {
        _isCheckingBackend = false;
        _isBackendOnline = status.isOnline;
      });
    }
  }

  void _editBackendUrl() {
    final urlCtrl = TextEditingController(text: widget.repository.settings.backendUrl);
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Backend Server URL'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Specify your GlowBlast backend URL (e.g. http://10.0.2.2:3000 for emulator, or https://YOUR-DOMAIN):',
              style: TextStyle(fontSize: 12.5),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: urlCtrl,
              decoration: const InputDecoration(
                labelText: 'Backend URL',
                hintText: 'http://10.0.2.2:3000',
                prefixIcon: Icon(Icons.dns_rounded),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primarySage,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              final newUrl = urlCtrl.text.trim();
              if (newUrl.isNotEmpty) {
                Navigator.pop(dialogCtx);
                final updated = widget.repository.settings.copyWith(backendUrl: newUrl);
                await widget.repository.updateSettings(updated);
                if (mounted) {
                  _checkBackendStatus();
                }
              }
            },
            child: const Text('Save & Reconnect'),
          ),
        ],
      ),
    );
  }
  void _editBusinessProfile() {
    final settings = widget.repository.settings;
    final fullNameCtrl = TextEditingController(text: settings.fullName);
    final businessNameCtrl = TextEditingController(text: settings.businessName);
    final phoneCtrl = TextEditingController(
      text: settings.phone.startsWith('+91 ')
          ? settings.phone.substring(4)
          : settings.phone,
    );
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Business Profile'),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Your profile details are used across messages, campaign previews and reports.',
                  style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: fullNameCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Full Name',
                    prefixIcon: Icon(Icons.person_outline_rounded, size: 20),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Full Name is required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: businessNameCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Business Name',
                    prefixIcon: Icon(Icons.storefront_outlined, size: 20),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Business Name is required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Phone Number',
                    prefixText: '+91 ',
                    prefixIcon: Icon(Icons.phone_outlined, size: 20),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Phone Number is required';
                    final digits = ExcelService.extractClean10Digits(v);
                    if (digits.length != 10) return 'Must be 10 digits';
                    if (!RegExp(r'^[6-9]\d{9}$').hasMatch(digits)) {
                      return 'Must start with 6, 7, 8, or 9';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primarySage,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              final cleanPhone = ExcelService.formatIndianPhone(phoneCtrl.text.trim());
              final updated = settings.copyWith(
                fullName: fullNameCtrl.text.trim(),
                businessName: businessNameCtrl.text.trim(),
                phone: cleanPhone,
              );
              await widget.repository.updateSettings(updated);
              if (!context.mounted) return;
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('✓ Business profile updated across the app.')),
              );
            },
            child: const Text('Save Profile'),
          ),
        ],
      ),
    );
  }

  void _confirmResetDemo() {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Reset Demo Data?'),
        content: const Text(
          'This will restore demo customers, sample campaigns, and WhatsApp credits.\n\nWould you also like to clear your business profile?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel'),
          ),
          OutlinedButton(
            onPressed: () async {
              Navigator.pop(dialogCtx);
              await widget.repository.resetDemoData(clearProfile: false);
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('✓ Demo data reset (profile kept).')),
              );
            },
            child: const Text('Keep Profile'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.pop(dialogCtx);
              await widget.repository.resetDemoData(clearProfile: true);
              if (!mounted) return;
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(
                  builder: (context) => LandingScreen(repository: widget.repository),
                ),
                (route) => false,
              );
            },
            child: const Text('Clear Profile & Reset'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.repository,
      builder: (context, _) {
        final settings = widget.repository.settings;
        final isDark = Theme.of(context).brightness == Brightness.dark;

        final displayName = settings.fullName.isNotEmpty ? settings.fullName : 'Business Owner';
        final displayBusiness = settings.businessName.isNotEmpty ? settings.businessName : 'Spa & Wellness';
        final displayPhone = settings.phone.isNotEmpty ? settings.phone : '+91 Not Set';

        return Scaffold(
          appBar: AppBar(
            title: const Text('Settings'),
          ),
          body: SafeArea(
            child: Column(
              children: [
                const DemoRibbon(label: 'SETTINGS & LOCAL DEMO PREFERENCES'),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                    children: [
                      // Section 1: Business Profile Card
                      AppCard(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: AppColors.primarySageContainer,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: const Icon(Icons.storefront_rounded, color: AppColors.primarySageDark, size: 20),
                                    ),
                                    const SizedBox(width: 10),
                                    const Text('Business Profile', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                                  ],
                                ),
                                TextButton.icon(
                                  onPressed: _editBusinessProfile,
                                  icon: const Icon(Icons.edit_outlined, size: 16),
                                  label: const Text('Edit Profile'),
                                ),
                              ],
                            ),
                            const Divider(height: 20),
                            _buildInfoRow('Full Name', displayName, isDark),
                            const SizedBox(height: 10),
                            _buildInfoRow('Business Name', displayBusiness, isDark),
                            const SizedBox(height: 10),
                            _buildInfoRow('Contact Phone', displayPhone, isDark),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Section 2: Messaging Mode & WhatsApp Configuration
                      AppCard(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: AppColors.whatsAppBg,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: const Icon(Icons.chat_rounded, color: AppColors.whatsApp, size: 20),
                                    ),
                                    const SizedBox(width: 10),
                                    const Text('WhatsApp Business', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                                  ],
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: settings.isWhatsAppTestMode
                                        ? (_isBackendOnline == true ? const Color(0xFFE8F5E9) : const Color(0xFFFFEBEE))
                                        : const Color(0xFFE8F5E9),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        settings.isWhatsAppTestMode
                                            ? (_isBackendOnline == true ? Icons.cloud_done_rounded : Icons.cloud_off_rounded)
                                            : Icons.check_circle_rounded,
                                        size: 12,
                                        color: settings.isWhatsAppTestMode
                                            ? (_isBackendOnline == true ? AppColors.success : AppColors.error)
                                            : AppColors.success,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        settings.isWhatsAppTestMode
                                            ? (_isBackendOnline == true ? 'Backend Online' : 'Backend Offline')
                                            : 'Demo Mode',
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w700,
                                          color: settings.isWhatsAppTestMode
                                              ? (_isBackendOnline == true ? AppColors.success : AppColors.error)
                                              : AppColors.success,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),

                            // Messaging Mode Selector (Demo vs Real WhatsApp Test Mode)
                            const Text('Messaging Mode', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                            const SizedBox(height: 8),
                            SegmentedButton<String>(
                              segments: const [
                                ButtonSegment(
                                  value: 'demo',
                                  label: Text('Demo Mode'),
                                  icon: Icon(Icons.speed_rounded, size: 16),
                                ),
                                ButtonSegment(
                                  value: 'testMode',
                                  label: Text('WhatsApp Test Mode'),
                                  icon: Icon(Icons.verified_rounded, size: 16),
                                ),
                              ],
                              selected: {settings.messagingMode},
                              onSelectionChanged: (set) async {
                                final updated = settings.copyWith(messagingMode: set.first);
                                await widget.repository.updateSettings(updated);
                                if (set.first == 'testMode') {
                                  _checkBackendStatus();
                                }
                              },
                            ),

                            const SizedBox(height: 12),

                            if (settings.isWhatsAppTestMode) ...[
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: isDark ? AppColors.surfaceDark : const Color(0xFFE8F5E9),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: const Color(0xFFC8E6C9)),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Row(
                                      children: [
                                        Icon(Icons.shield_outlined, size: 16, color: AppColors.success),
                                        SizedBox(width: 6),
                                        Text(
                                          'Connected through GlowBlast backend',
                                          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.success),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    const Text(
                                      'Test Display Number: +1 (555) 632-5494\nRecipient Limit: Up to 5 authorized Meta test numbers\nAccess Token: Kept secret on backend server only.',
                                      style: TextStyle(fontSize: 11.5, height: 1.4, color: AppColors.textMuted),
                                    ),
                                    const Divider(height: 16),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            'Backend: ${settings.backendUrl}',
                                            style: const TextStyle(fontSize: 11.5, fontFamily: 'monospace'),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        IconButton(
                                          icon: _isCheckingBackend
                                              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                                              : const Icon(Icons.refresh_rounded, size: 18),
                                          onPressed: _checkBackendStatus,
                                          tooltip: 'Ping Backend Health',
                                        ),
                                        TextButton(
                                          onPressed: _editBackendUrl,
                                          child: const Text('Change URL', style: TextStyle(fontSize: 12)),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ] else ...[
                              Text(
                                'Simulated messaging. No real WhatsApp messages are sent.',
                                style: TextStyle(fontSize: 12, color: isDark ? AppColors.textMutedDark : AppColors.textMuted),
                              ),
                            ],

                            const Divider(height: 24),

                            // Credits balance row
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Available Broadcast Balance',
                                      style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${settings.whatsAppCredits} Credits',
                                      style: const TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.primarySage,
                                      ),
                                    ),
                                  ],
                                ),
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.primarySage,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                  ),
                                  icon: const Icon(Icons.add_rounded, size: 16),
                                  label: const Text('Top Up'),
                                  onPressed: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (context) => BuyCreditsScreen(repository: widget.repository),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Section 3: Opt-Out Management
                      AppCard(
                        padding: const EdgeInsets.all(16),
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: isDark ? AppColors.surfaceDark : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.do_not_disturb_on_outlined, color: AppColors.error, size: 22),
                          ),
                          title: const Text('Opt-Out Management', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                          subtitle: Text(
                            '${widget.repository.optedOutCustomersCount} opted-out contacts excluded from blasts',
                            style: const TextStyle(fontSize: 12),
                          ),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (context) => OptOutScreen(repository: widget.repository),
                              ),
                            );
                          },
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Section 4: App Theme
                      AppCard(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Display Appearance', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                            const SizedBox(height: 12),
                            SegmentedButton<String>(
                              segments: const [
                                ButtonSegment(value: 'system', label: Text('System'), icon: Icon(Icons.brightness_auto)),
                                ButtonSegment(value: 'light', label: Text('Light'), icon: Icon(Icons.light_mode)),
                                ButtonSegment(value: 'dark', label: Text('Dark'), icon: Icon(Icons.dark_mode)),
                              ],
                              selected: {settings.themeMode},
                              onSelectionChanged: (set) async {
                                final updated = settings.copyWith(themeMode: set.first);
                                await widget.repository.updateSettings(updated);
                              },
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Reset Demo Data Button
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.error,
                          side: const BorderSide(color: AppColors.error),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.restore_rounded),
                        label: const Text('Reset Demo Data', style: TextStyle(fontWeight: FontWeight.w700)),
                        onPressed: _confirmResetDemo,
                      ),

                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildInfoRow(String label, String value, bool isDark) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
        Text(
          value,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            color: isDark ? AppColors.textLight : AppColors.textCharcoal,
          ),
        ),
      ],
    );
  }
}
