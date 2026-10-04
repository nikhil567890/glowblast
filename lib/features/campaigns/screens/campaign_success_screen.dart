import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/widgets/demo_ribbon.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../data/models/campaign.dart';
import '../../../data/repositories/app_repository.dart';

class CampaignSuccessScreen extends StatefulWidget {
  final AppRepository repository;
  final Campaign campaign;

  const CampaignSuccessScreen({
    super.key,
    required this.repository,
    required this.campaign,
  });

  @override
  State<CampaignSuccessScreen> createState() => _CampaignSuccessScreenState();
}

class _CampaignSuccessScreenState extends State<CampaignSuccessScreen> {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final totalMsgs = widget.campaign.messagesSent;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const DemoRibbon(label: 'SIMULATED BROADCAST COMPLETED • WHATSAPP ONLY'),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(height: 16),
                    // Success Badge
                    Container(
                      width: 84,
                      height: 84,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F5E9),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.success.withValues(alpha: 0.2),
                            blurRadius: 18,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.check_rounded,
                          size: 48,
                          color: AppColors.success,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    Text(
                      '🎉 Campaign Complete!',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                        color: isDark ? AppColors.textLight : AppColors.textCharcoal,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Your campaign "${widget.campaign.name}" was processed successfully.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14.5,
                        color: isDark ? AppColors.textMutedDark : AppColors.textMuted,
                        height: 1.35,
                      ),
                    ),

                    const SizedBox(height: 28),

                    // Stats Summary Card
                    AppCard(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Dispatch Summary',
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                          ),
                          const SizedBox(height: 14),
                          _buildSummaryRow(
                            Icons.chat_rounded,
                            'WhatsApp Messages Prepared',
                            '$totalMsgs',
                            AppColors.whatsApp,
                          ),
                          const Divider(height: 20),
                          _buildSummaryRow(
                            Icons.all_inbox_rounded,
                            'Total Broadcast Output',
                            '$totalMsgs messages',
                            AppColors.primarySage,
                            isBold: true,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Demo Mode Notice Banner
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF3CD),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFFEEBA)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.info_outline_rounded, color: Color(0xFF856404), size: 20),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              AppStrings.demoPostSendNotice,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF856404),
                                height: 1.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 32),

                    PrimaryButton(
                      text: 'View Performance Reports',
                      icon: Icons.bar_chart_rounded,
                      onPressed: () {
                        Navigator.of(context).popUntil((route) => route.isFirst);
                      },
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.dashboard_outlined, size: 18),
                      label: const Text('Back to Home'),
                      onPressed: () {
                        Navigator.of(context).popUntil((route) => route.isFirst);
                      },
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryRow(IconData icon, String label, String value, Color color, {bool isBold = false}) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isBold ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }
}
