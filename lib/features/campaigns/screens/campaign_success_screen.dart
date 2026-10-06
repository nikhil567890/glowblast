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

    final isReal = widget.campaign.isRealTest;
    final isPartial = widget.campaign.status == 'Completed with Errors';
    final isFailed = widget.campaign.status == 'Failed';

    final badgeColor = isFailed
        ? AppColors.error
        : (isPartial ? AppColors.accentGold : AppColors.success);
    final badgeBg = isFailed
        ? const Color(0xFFFFEBEE)
        : (isPartial ? const Color(0xFFFFF8E1) : const Color(0xFFE8F5E9));
    final badgeIcon = isFailed
        ? Icons.error_outline_rounded
        : (isPartial ? Icons.warning_amber_rounded : Icons.check_rounded);

    final titleText = isReal
        ? (isFailed
            ? 'Broadcast Failed'
            : (isPartial ? 'Broadcast Completed with Errors' : '🎉 Broadcast Completed'))
        : '🎉 Campaign Complete!';

    final subtitleText = isReal
        ? (isFailed
            ? 'Campaign "${widget.campaign.name}" could not be delivered to recipients.'
            : (isPartial
                ? 'Campaign "${widget.campaign.name}" finished with partial delivery.'
                : 'Your campaign "${widget.campaign.name}" was processed by Meta Cloud API.'))
        : 'Your campaign "${widget.campaign.name}" was processed successfully.';

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            DemoRibbon(
              label: isReal
                  ? 'META CLOUD API • LIVE BROADCAST REPORT'
                  : 'SIMULATED BROADCAST COMPLETED • WHATSAPP ONLY',
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(height: 16),
                    // Status Badge
                    Container(
                      width: 84,
                      height: 84,
                      decoration: BoxDecoration(
                        color: badgeBg,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: badgeColor.withValues(alpha: 0.2),
                            blurRadius: 18,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Icon(
                          badgeIcon,
                          size: 48,
                          color: badgeColor,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    Text(
                      titleText,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                        color: isDark ? AppColors.textLight : AppColors.textCharcoal,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      subtitleText,
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
                          Text(
                            isReal ? 'Meta Dispatch Results' : 'Dispatch Summary',
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                          ),
                          const SizedBox(height: 14),
                          if (isReal) ...[
                            if (widget.campaign.templateName != null) ...[
                              _buildSummaryRow(
                                Icons.verified_user_rounded,
                                'Meta Template',
                                widget.campaign.templateName!,
                                AppColors.whatsApp,
                              ),
                              const Divider(height: 18),
                            ],
                            _buildSummaryRow(
                              Icons.people_alt_rounded,
                              'Total Recipients',
                              '${widget.campaign.recipients}',
                              AppColors.primarySage,
                            ),
                            const Divider(height: 18),
                            _buildSummaryRow(
                              Icons.cloud_done_rounded,
                              'Meta Accepted',
                              '${widget.campaign.accepted}',
                              AppColors.primarySage,
                            ),
                            const Divider(height: 18),
                            _buildSummaryRow(
                              Icons.done_all_rounded,
                              'Sent (Confirmed)',
                              '${widget.campaign.messagesSent}',
                              AppColors.whatsApp,
                            ),
                            const Divider(height: 18),
                            _buildSummaryRow(
                              Icons.mark_chat_read_rounded,
                              'Delivered (Webhook)',
                              '${widget.campaign.delivered}',
                              AppColors.whatsApp,
                            ),
                            if (widget.campaign.read > 0) ...[
                              const Divider(height: 18),
                              _buildSummaryRow(
                                Icons.remove_red_eye_rounded,
                                'Read by Customer',
                                '${widget.campaign.read}',
                                const Color(0xFF34B7F1),
                              ),
                            ],
                            if (widget.campaign.failed > 0) ...[
                              const Divider(height: 18),
                              _buildSummaryRow(
                                Icons.error_outline_rounded,
                                'Failed / Rejected',
                                '${widget.campaign.failed}',
                                AppColors.error,
                                isBold: true,
                              ),
                            ],
                          ] else ...[
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
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    if (!isReal) ...[
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
                    ] else if (widget.campaign.failed > 0) ...[
                      // Real mode error notice
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF3CD),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFFFEEBA)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.info_outline_rounded, color: Color(0xFF856404), size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                '${widget.campaign.failed} message(s) could not be delivered. In Meta Developer Test Mode, recipient numbers must be added to authorized test numbers in Meta App Dashboard.',
                                style: const TextStyle(
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
                    ],

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
