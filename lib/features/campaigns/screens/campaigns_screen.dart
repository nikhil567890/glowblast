import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/demo_ribbon.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../data/models/campaign.dart';
import '../../../data/repositories/app_repository.dart';
import 'campaign_wizard_screen.dart';
import '../../templates/screens/templates_screen.dart';

class CampaignsScreen extends StatefulWidget {
  final AppRepository repository;

  const CampaignsScreen({super.key, required this.repository});

  @override
  State<CampaignsScreen> createState() => _CampaignsScreenState();
}

class _CampaignsScreenState extends State<CampaignsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _openComposer() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => CampaignWizardScreen(repository: widget.repository),
      ),
    );
  }

  void _openTemplates() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => TemplatesScreen(repository: widget.repository),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.repository,
      builder: (context, _) {
        final repo = widget.repository;
        final sentCampaigns = repo.sentCampaigns;
        final scheduledCampaigns = repo.scheduledCampaigns;
        final isDark = Theme.of(context).brightness == Brightness.dark;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Campaigns'),
            actions: [
              TextButton.icon(
                onPressed: _openTemplates,
                icon: const Icon(Icons.style_outlined, size: 18),
                label: const Text('Templates', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
            bottom: TabBar(
              controller: _tabController,
              indicatorColor: AppColors.primarySage,
              labelColor: isDark ? AppColors.textLight : AppColors.primarySage,
              unselectedLabelColor: isDark ? AppColors.textMutedDark : AppColors.textMuted,
              tabs: [
                Tab(text: 'Sent (${sentCampaigns.length})'),
                Tab(text: 'Scheduled (${scheduledCampaigns.length})'),
              ],
            ),
          ),
          floatingActionButton: FloatingActionButton.extended(
            heroTag: 'fab_campaigns',
            onPressed: _openComposer,
            backgroundColor: AppColors.primarySage,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.add_rounded),
            label: const Text('New Campaign', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
          body: SafeArea(
            child: Column(
              children: [
                const DemoRibbon(label: 'PROMOTIONAL CAMPAIGNS • WHATSAPP ONLY'),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildSentList(sentCampaigns, isDark),
                      _buildScheduledList(scheduledCampaigns, isDark),
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

  Widget _buildSentList(List<Campaign> list, bool isDark) {
    final dateFormat = DateFormat('dd MMM yyyy');

    if (list.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.campaign_outlined, size: 48, color: AppColors.textMuted),
            const SizedBox(height: 12),
            const Text('No sent campaigns yet', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 16),
            PrimaryButton(text: 'Launch First Campaign', isFullWidth: false, onPressed: _openComposer),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 12, bottom: 80),
      itemCount: list.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final c = list[index];

        return AppCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      c.name,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                    ),
                  ),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _buildStatusBadge(c.status),
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
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${c.status == "Failed" ? "Dispatched" : "Sent"} ${dateFormat.format(c.date)} • ${c.targetAudience} (${c.recipients} total)',
                style: TextStyle(fontSize: 11.5, color: isDark ? AppColors.textMutedDark : AppColors.textMuted),
              ),
              const SizedBox(height: 10),
              Text(
                c.messageContent,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted),
              ),
              const Divider(height: 20),

              // KPI Row: Sent, Delivered, Read, Failed
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildMetric('Sent', '${c.messagesSent}'),
                  _buildMetric('Delivered', '${c.delivered} (${c.deliveryRate.toStringAsFixed(0)}%)'),
                  _buildMetric('Read', '${c.read} (${c.readRate.toStringAsFixed(0)}%)'),
                  _buildMetric('Failed', '${c.failed}', isError: c.failed > 0),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatusBadge(String status) {
    Color bg;
    Color fg;
    String label = status;

    final lower = status.toLowerCase();
    if (lower.contains('with_errors') || lower.contains('with errors')) {
      bg = const Color(0xFFFEF3C7);
      fg = const Color(0xFFD97706);
      label = 'Partial';
    } else if (lower.contains('failed')) {
      bg = const Color(0xFFFEE2E2);
      fg = AppColors.error;
      label = 'Failed';
    } else if (lower.contains('completed') || lower.contains('sent')) {
      bg = AppColors.primarySageContainer;
      fg = AppColors.primarySageDark;
      label = 'Completed';
    } else if (lower.contains('processing') || lower.contains('accepted')) {
      bg = const Color(0xFFE0F2FE);
      fg = const Color(0xFF0284C7);
      label = 'In Progress';
    } else {
      bg = Colors.grey.shade200;
      fg = Colors.grey.shade800;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: fg),
      ),
    );
  }

  Widget _buildScheduledList(List<Campaign> list, bool isDark) {
    final dateFormat = DateFormat('dd MMM, hh:mm a');

    if (list.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.schedule_rounded, size: 48, color: AppColors.textMuted),
            const SizedBox(height: 12),
            const Text('No scheduled campaigns', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 16),
            PrimaryButton(text: 'Schedule a Campaign', isFullWidth: false, onPressed: _openComposer),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 12, bottom: 80),
      itemCount: list.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final c = list[index];

        return AppCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      c.name,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.accentGoldContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'Scheduled',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.accentGoldDark,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Will broadcast: ${c.scheduledDate != null ? dateFormat.format(c.scheduledDate!) : "Upcoming"}',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: isDark ? AppColors.accentGoldLight : AppColors.accentGoldDark),
              ),
              const SizedBox(height: 10),
              Text(
                c.messageContent,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted),
              ),
              const Divider(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${c.recipients} Recipients • WhatsApp',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.cancel_outlined, size: 16, color: AppColors.error),
                    label: const Text('Cancel', style: TextStyle(color: AppColors.error)),
                    onPressed: () async {
                      await widget.repository.cancelScheduledCampaign(c.id);
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Scheduled campaign cancelled.')),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMetric(String label, String value, {bool highlight = false, bool isError = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: isError
                ? AppColors.error
                : highlight
                    ? AppColors.primarySage
                    : null,
          ),
        ),
      ],
    );
  }
}

