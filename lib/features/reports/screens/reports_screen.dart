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

                              // Grid of 4 key stats (EXACTLY equal width & height via IntrinsicHeight and unified layout)
                              IntrinsicHeight(
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    Expanded(
                                      child: _buildMetricTile(
                                        'Total Sent',
                                        '${repository.totalMessagesSent}',
                                        Icons.outgoing_mail,
                                        AppColors.primarySage,
                                        isDark,
                                        sub: 'All-time broadcasts',
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
                                        sub: '${repository.overallDeliveryRate.toStringAsFixed(1)}% delivery',
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 10),
                              IntrinsicHeight(
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    Expanded(
                                      child: _buildMetricTile(
                                        'Read',
                                        '${repository.totalRead}',
                                        Icons.mark_chat_read_rounded,
                                        AppColors.info,
                                        isDark,
                                        sub: '${repository.overallReadRate.toStringAsFixed(1)}% read rate',
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
                                        sub: 'Client replies',
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              if (campaigns.isNotEmpty) ...[
                                const SizedBox(height: 22),
                                _buildRolling6MonthsBarChart(campaigns, isDark),
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

  Widget _buildMetricTile(
    String label,
    String value,
    IconData icon,
    Color color,
    bool isDark, {
    required String sub,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isDark ? AppColors.borderDark : AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 16, color: color),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              color: isDark ? AppColors.textLight : AppColors.textCharcoal,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            sub,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRolling6MonthsBarChart(List<Campaign> campaigns, bool isDark) {
    // Dynamic rolling 6-month calculation: Current month + previous 5 months
    final now = DateTime.now();
    const monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

    final monthlyData = <Map<String, dynamic>>[];
    for (int i = 5; i >= 0; i--) {
      int targetMonth = now.month - i;
      int targetYear = now.year;
      while (targetMonth <= 0) {
        targetMonth += 12;
        targetYear -= 1;
      }

      final monthStr = monthNames[targetMonth - 1];

      // Aggregate matching real/stored campaigns for this month
      final matches = campaigns.where((c) {
        return c.date.month == targetMonth && c.date.year == targetYear;
      }).toList();

      int sent = matches.fold(0, (sum, c) => sum + c.messagesSent);
      int delivered = matches.fold(0, (sum, c) => sum + c.delivered);
      bool isDemo = false;

      if (matches.isEmpty) {
        // Fallback to demo profile dataset for months before active installation
        final demoCamp = campaigns.firstWhere(
          (c) => c.month.toLowerCase().startsWith(monthStr.toLowerCase()),
          orElse: () => Campaign(
            id: '',
            name: '',
            month: monthStr,
            date: DateTime(targetYear, targetMonth, 1),
            targetAudience: 'All Clients',
            messageContent: '',
            recipients: 0,
            messagesSent: 0,
            delivered: 0,
            read: 0,
            replied: 0,
            failed: 0,
          ),
        );
        if (demoCamp.messagesSent > 0) {
          sent = demoCamp.messagesSent;
          delivered = demoCamp.delivered;
          isDemo = !demoCamp.isRealTest;
        } else {
          const sampleSent = [110, 135, 125, 150, 180, 205];
          const sampleDel = [102, 128, 118, 142, 172, 196];
          final sIdx = (5 - i).clamp(0, 5);
          sent = sampleSent[sIdx];
          delivered = sampleDel[sIdx];
          isDemo = true;
        }
      }

      monthlyData.add({
        'month': monthStr,
        'year': targetYear,
        'sent': sent,
        'delivered': delivered,
        'isDemo': isDemo,
      });
    }

    final maxVal = monthlyData
        .map((m) => (m['sent'] as int))
        .fold(100, (a, b) => a > b ? a : b);
    final chartMaxY = (maxVal * 1.25).toDouble().clamp(120.0, 500.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Title & Legend
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Campaign Dispatch Comparison',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
                ),
                const SizedBox(height: 2),
                Text(
                  'Rolling 6 Months (${monthlyData.first['month']} – ${monthlyData.last['month']} ${monthlyData.last['year']})',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: isDark ? AppColors.textMutedDark : AppColors.textMuted,
                  ),
                ),
              ],
            ),
            // Legend
            Row(
              children: [
                _buildLegendItem('Sent', AppColors.primarySageLight),
                const SizedBox(width: 8),
                _buildLegendItem('Delivered', AppColors.whatsApp),
              ],
            ),
          ],
        ),

        const SizedBox(height: 14),

        SizedBox(
          height: 150,
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: chartMaxY,
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (_) => AppColors.primarySageDark,
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    final item = monthlyData[group.x.toInt()];
                    return BarTooltipItem(
                      '${item['month']} ${item['year']}\nSent: ${item['sent']}\nDelivered: ${item['delivered']}',
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
                      if (idx >= 0 && idx < monthlyData.length) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            monthlyData[idx]['month'] as String,
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
              barGroups: List.generate(monthlyData.length, (index) {
                final item = monthlyData[index];
                return BarChartGroupData(
                  x: index,
                  barsSpace: 4,
                  barRods: [
                    BarChartRodData(
                      toY: (item['sent'] as int).toDouble(),
                      color: AppColors.primarySageLight,
                      width: 9,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                    ),
                    BarChartRodData(
                      toY: (item['delivered'] as int).toDouble(),
                      color: AppColors.whatsApp,
                      width: 9,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                    ),
                  ],
                );
              }),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: AppColors.textMuted),
        ),
      ],
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
