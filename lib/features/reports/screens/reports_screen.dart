import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/widgets/demo_ribbon.dart';
import '../../../core/widgets/app_card.dart';
import '../../../data/models/campaign.dart';
import '../../../data/repositories/app_repository.dart';

class ReportsScreen extends StatelessWidget {
  final AppRepository repository;

  const ReportsScreen({super.key, required this.repository});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: repository,
      builder: (context, _) {
        final campaigns = repository.sentCampaigns;
        final bestCampaign = repository.bestPerformingCampaign;
        final settings = repository.settings;
        final isDark = Theme.of(context).brightness == Brightness.dark;

        final senderBusiness = settings.businessName.isNotEmpty ? settings.businessName : 'Spa & Wellness';
        final senderName = settings.fullName.isNotEmpty ? settings.fullName : 'Owner';

        return Scaffold(
          appBar: AppBar(
            title: const Text('Performance & Reports'),
          ),
          body: SafeArea(
            child: Column(
              children: [
                const DemoRibbon(label: AppStrings.demoAnalyticsLabel),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Sender Profile Notice
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: isDark ? AppColors.surfaceDark : AppColors.warmCream,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.borderLight),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.verified_user_outlined, size: 16, color: AppColors.primarySage),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Sender: $senderBusiness ($senderName) • ${settings.phone.isNotEmpty ? settings.phone : "+91 Verified"}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: isDark ? AppColors.textLight : AppColors.textCharcoal,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 16),

                        // Campaign Highlight Card (🏆 Top Performing Campaign)
                        if (bestCampaign != null) ...[
                          Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF2E4034), Color(0xFF1D2821)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: AppColors.accentGoldLight.withValues(alpha: 0.4)),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.15),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: AppColors.accentGold.withValues(alpha: 0.25),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: const Row(
                                        children: [
                                          Icon(Icons.emoji_events_rounded, size: 14, color: AppColors.accentGoldLight),
                                          SizedBox(width: 4),
                                          Text(
                                            '🏆 Top Performing Campaign',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              color: AppColors.accentGoldLight,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  bestCampaign.name,
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Delivered to ${bestCampaign.recipients} recipients with ${bestCampaign.readRate.toStringAsFixed(0)}% read rate.',
                                  style: const TextStyle(fontSize: 12.5, color: Colors.white70),
                                ),
                                const SizedBox(height: 16),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    _buildHighlightStat('Sent', '${bestCampaign.messagesSent}'),
                                    _buildHighlightStat('Delivered', '${bestCampaign.delivered}'),
                                    _buildHighlightStat('Read Rate', '${bestCampaign.readRate.toStringAsFixed(0)}%'),
                                    _buildHighlightStat('Replied', '${bestCampaign.replied}'),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                        ],

                        // WhatsApp Broadcast Aggregate Metrics
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
                                      const Icon(Icons.chat_rounded, color: AppColors.whatsApp, size: 20),
                                      const SizedBox(width: 8),
                                      const Text(
                                        'WhatsApp Broadcast Totals',
                                        style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
                                      ),
                                    ],
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppColors.demoRibbonBg,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Text(
                                      'WhatsApp Only',
                                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.demoRibbonText),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),

                              // Grid of 4 key stats
                              Row(
                                children: [
                                  Expanded(
                                    child: _buildMetricTile(
                                      'Total Sent',
                                      '${repository.totalMessagesSent}',
                                      Icons.outgoing_mail,
                                      AppColors.primarySage,
                                      isDark,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: _buildMetricTile(
                                      'Delivered',
                                      '${repository.totalDelivered}',
                                      Icons.done_all_rounded,
                                      AppColors.whatsApp,
                                      isDark,
                                      sub: '${repository.overallDeliveryRate.toStringAsFixed(1)}% rate',
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: _buildMetricTile(
                                      'Read',
                                      '${repository.totalRead}',
                                      Icons.mark_chat_read_rounded,
                                      AppColors.info,
                                      isDark,
                                      sub: '${repository.overallReadRate.toStringAsFixed(1)}% rate',
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: _buildMetricTile(
                                      'Replied',
                                      '${repository.totalReplied}',
                                      Icons.reply_rounded,
                                      AppColors.accentGold,
                                      isDark,
                                    ),
                                  ),
                                ],
                              ),

                              if (campaigns.isNotEmpty) ...[
                                const SizedBox(height: 20),
                                const Text(
                                  'Campaign Dispatch Comparison',
                                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                                ),
                                const SizedBox(height: 12),
                                _buildCampaignsBarChart(campaigns, isDark),
                              ],
                            ],
                          ),
                        ),

                        const SizedBox(height: 24),

                        // All Past Campaigns Breakdown
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Campaign History (${campaigns.length})',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: isDark ? AppColors.textLight : AppColors.textCharcoal,
                              ),
                            ),
                            const Text(
                              AppStrings.demoAnalyticsLabel,
                              style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                            ),
                          ],
                        ),

                        const SizedBox(height: 12),

                        ...campaigns.map((camp) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: AppCard(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          camp.name,
                                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5),
                                        ),
                                      ),
                                      if (camp.isRealTest) ...[
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFE8F5E9),
                                            borderRadius: BorderRadius.circular(10),
                                            border: Border.all(color: const Color(0xFFC8E6C9)),
                                          ),
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.verified_rounded, size: 12, color: AppColors.success),
                                              SizedBox(width: 4),
                                              Text(
                                                'REAL TEST',
                                                style: TextStyle(
                                                  fontSize: 10.5,
                                                  fontWeight: FontWeight.w800,
                                                  color: AppColors.success,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                      ],
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: AppColors.whatsAppBg,
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.chat_rounded, size: 12, color: AppColors.whatsApp),
                                            SizedBox(width: 4),
                                            Text(
                                              'WhatsApp',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                                color: AppColors.whatsApp,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    camp.isRealTest
                                        ? 'Audience: ${camp.targetAudience} • Live Meta Cloud API Dispatch'
                                        : 'Audience: ${camp.targetAudience} • Month: ${camp.month}',
                                    style: TextStyle(fontSize: 12, color: isDark ? AppColors.textMutedDark : AppColors.textMuted),
                                  ),
                                  const Divider(height: 20),

                                  // Grid metrics: Sent, Delivered, Read, Replied, Failed
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      _buildReportItem('Sent', '${camp.messagesSent}'),
                                      _buildReportItem('Delivered', '${camp.delivered} (${camp.deliveryRate.toStringAsFixed(0)}%)'),
                                      _buildReportItem('Read', '${camp.read} (${camp.readRate.toStringAsFixed(0)}%)'),
                                      _buildReportItem('Replied', camp.isRealTest ? 'N/A*' : '${camp.replied}'),
                                      _buildReportItem('Failed', '${camp.failed}', isFailed: camp.failed > 0),
                                    ],
                                  ),
                                  if (camp.isRealTest) ...[
                                    const SizedBox(height: 6),
                                    const Text(
                                      '* Inbound customer replies are not available in current test integration.',
                                      style: TextStyle(fontSize: 10.5, fontStyle: FontStyle.italic, color: AppColors.textMuted),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        }),

                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMetricTile(String label, String value, IconData icon, Color color, bool isDark, {String? sub}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: isDark ? AppColors.textLight : AppColors.textCharcoal),
          ),
          if (sub != null) ...[
            const SizedBox(height: 2),
            Text(sub, style: TextStyle(fontSize: 10.5, color: color, fontWeight: FontWeight.w600)),
          ],
        ],
      ),
    );
  }

  Widget _buildCampaignsBarChart(List<Campaign> campaigns, bool isDark) {
    final list = campaigns.take(4).toList();

    return SizedBox(
      height: 140,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: (campaigns.map((c) => c.messagesSent).fold(0, (a, b) => a > b ? a : b) * 1.15).toDouble().clamp(100, 300),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => AppColors.primarySageDark,
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final c = list[group.x.toInt()];
                return BarTooltipItem(
                  '${c.name}\nDelivered: ${c.delivered}\nRead: ${c.read}',
                  const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                );
              },
            ),
          ),
          titlesData: FlTitlesData(
            show: true,
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  final idx = value.toInt();
                  if (idx >= 0 && idx < list.length) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        list[idx].month,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isDark ? AppColors.textMutedDark : AppColors.textMuted,
                        ),
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
            ),
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          barGroups: List.generate(list.length, (index) {
            final c = list[index];
            return BarChartGroupData(
              x: index,
              barRods: [
                BarChartRodData(
                  toY: c.delivered.toDouble(),
                  color: AppColors.whatsApp,
                  width: 14,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                ),
                BarChartRodData(
                  toY: c.read.toDouble(),
                  color: AppColors.primarySageLight,
                  width: 14,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }

  Widget _buildHighlightStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Colors.white60, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _buildReportItem(String label, String value, {bool isFailed = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: isFailed ? AppColors.error : null,
          ),
        ),
      ],
    );
  }
}
