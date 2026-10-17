import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../data/repositories/app_repository.dart';

class RechargeMetaBalanceScreen extends StatefulWidget {
  final AppRepository repository;
  static const String metaBusinessManagerUrl = 'https://business.facebook.com/';

  const RechargeMetaBalanceScreen({super.key, required this.repository});

  @override
  State<RechargeMetaBalanceScreen> createState() => _RechargeMetaBalanceScreenState();
}

class _RechargeMetaBalanceScreenState extends State<RechargeMetaBalanceScreen> {
  static const String metaBusinessManagerUrl = RechargeMetaBalanceScreen.metaBusinessManagerUrl;
  bool _isOpeningBrowser = false;

  Future<void> _openMetaBusinessManager() async {
    setState(() => _isOpeningBrowser = true);
    final Uri uri = Uri.parse(metaBusinessManagerUrl);

    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      if (!launched && mounted) {
        _showCopyUrlDialog();
      }
    } catch (e) {
      if (mounted) {
        _showCopyUrlDialog();
      }
    } finally {
      if (mounted) {
        setState(() => _isOpeningBrowser = false);
      }
    }
  }

  void _showCopyUrlDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Open in Browser'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Could not open external browser automatically. You can copy the verified Meta Business Manager link below and open it in your browser:',
              style: TextStyle(fontSize: 13),
            ),
            SizedBox(height: 12),
            SelectableText(
              metaBusinessManagerUrl,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: AppColors.primarySage,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primarySage,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.copy_rounded, size: 16),
            label: const Text('Copy URL'),
            onPressed: () {
              Clipboard.setData(const ClipboardData(text: metaBusinessManagerUrl));
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Meta URL copied to clipboard'),
                  backgroundColor: AppColors.success,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Recharge Meta Balance'),
        actions: [
          IconButton(
            tooltip: 'Return to GlowBlast',
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header title
              Text(
                'Recharge Meta Messaging Balance',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: isDark ? AppColors.textLight : AppColors.textCharcoal,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Official WhatsApp Cloud API conversation charges are billed directly by Meta (Facebook). Payments and funds are managed through Meta Business Manager.',
                style: TextStyle(
                  fontSize: 13.5,
                  color: isDark ? AppColors.textMutedDark : AppColors.textMuted,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),

              // Account Context Card
              AppCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE8F5E9),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.verified_rounded, color: Color(0xFF2E7D32), size: 20),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Connected WhatsApp Account',
                                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                              ),
                              SizedBox(height: 2),
                              Text(
                                '+91 95022 59203 • Coexistence Active',
                                style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('WhatsApp Business Account (WABA):', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                        Text('3226959717495309', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Instructions Card
              AppCard(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.payment_rounded, color: AppColors.primarySage, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'How to Add Funds or Update Billing',
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _buildStepRow(
                      number: '1',
                      title: 'Sign In to Meta',
                      description:
                          'Open Meta Business Manager and log in with the Facebook/Meta account that has billing or admin permissions for your business.',
                      isDark: isDark,
                    ),
                    const SizedBox(height: 12),
                    _buildStepRow(
                      number: '2',
                      title: 'Select Business & WhatsApp Account',
                      description:
                          'Ensure your spa business portfolio and WABA ID 3226959717495309 are selected.',
                      isDark: isDark,
                    ),
                    const SizedBox(height: 12),
                    _buildStepRow(
                      number: '3',
                      title: 'Navigate to Billing & Payment',
                      description:
                          'Go to Business Settings > Billing & Payments. Select Payment Methods or Account Funds.',
                      isDark: isDark,
                    ),
                    const SizedBox(height: 12),
                    _buildStepRow(
                      number: '4',
                      title: 'Complete Payment with Meta',
                      description:
                          'Add funds or update payment methods using the payment options available for your Meta business account (e.g., Credit/Debit card or available banking options).',
                      isDark: isDark,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              // Important Disclaimer Card
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF2C2416) : const Color(0xFFFFF9E6),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark ? const Color(0xFF5A4418) : const Color(0xFFFFE082),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline_rounded, color: Color(0xFFB78103), size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Important: Meta handles all actual payments. Tapping "Open Meta Business Manager" opens Meta\'s verified portal in your browser and does not itself recharge the balance or charge any payment method. GlowBlast does not store or process card or payment credentials.',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? const Color(0xFFFFD54F) : const Color(0xFF7A5700),
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Launch Meta Button
              PrimaryButton(
                text: _isOpeningBrowser ? 'Opening Meta...' : 'Open Meta Business Manager',
                icon: Icons.open_in_browser_rounded,
                isLoading: _isOpeningBrowser,
                onPressed: _openMetaBusinessManager,
              ),

              const SizedBox(height: 12),

              // Return to GlowBlast button
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.arrow_back_rounded, size: 18),
                  label: const Text('Return to GlowBlast', style: TextStyle(fontWeight: FontWeight.w700)),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),

              const SizedBox(height: 24),

              // Troubleshooting & Guidance
              AppCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Troubleshooting & Notes', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                    const SizedBox(height: 10),
                    _buildFaqItem(
                      'Payment methods not appearing?',
                      'Ensure you are logged in as an Admin or Finance Editor on your Meta Business account.',
                      isDark,
                    ),
                    const SizedBox(height: 8),
                    _buildFaqItem(
                      'Available payment methods',
                      'Meta determines the payment methods (Credit Card, Net Banking, or Prepaid) available based on your country and business verification status.',
                      isDark,
                    ),
                    const SizedBox(height: 8),
                    _buildFaqItem(
                      'How long until balance reflects?',
                      'Recharges processed directly on Meta typically reflect on Meta Cloud API within a few minutes.',
                      isDark,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepRow({
    required String number,
    required String title,
    required String description,
    required bool isDark,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 12,
          backgroundColor: AppColors.primarySageContainer,
          child: Text(
            number,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: AppColors.primarySageDark,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? AppColors.textMutedDark : AppColors.textMuted,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFaqItem(String question, String answer, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('• $question', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Padding(
          padding: const EdgeInsets.only(left: 10),
          child: Text(
            answer,
            style: TextStyle(fontSize: 11.5, color: isDark ? AppColors.textMutedDark : AppColors.textMuted),
          ),
        ),
      ],
    );
  }
}

/// Backwards compatibility alias
typedef BuyCreditsScreen = RechargeMetaBalanceScreen;
