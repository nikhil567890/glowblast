import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/demo_ribbon.dart';
import '../../../core/widgets/app_card.dart';
import '../../../data/models/whatsapp_template.dart';
import '../../../data/repositories/app_repository.dart';
import '../../campaigns/screens/campaign_wizard_screen.dart';
import 'create_template_screen.dart';

class TemplatesScreen extends StatefulWidget {
  final AppRepository repository;

  const TemplatesScreen({super.key, required this.repository});

  @override
  State<TemplatesScreen> createState() => _TemplatesScreenState();
}

class _TemplatesScreenState extends State<TemplatesScreen> {
  String _selectedFilter = 'All'; // 'All', 'Approved', 'Pending', 'Draft'
  bool _isSyncing = false;

  void _openCreateTemplate() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => CreateTemplateScreen(repository: widget.repository),
      ),
    );
  }

  Future<void> _syncWithMeta() async {
    setState(() => _isSyncing = true);
    final count = await widget.repository.syncTemplatesWithBackend();
    if (!mounted) return;
    setState(() => _isSyncing = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          count > 0
              ? 'Synced $count templates with Meta WhatsApp Business Platform.'
              : 'Templates are up to date with backend store.',
        ),
        backgroundColor: AppColors.primarySageDark,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ListenableBuilder(
      listenable: widget.repository,
      builder: (context, _) {
        final allTemplates = widget.repository.templates;

        final filtered = allTemplates.where((t) {
          if (_selectedFilter == 'Approved') return t.isApproved;
          if (_selectedFilter == 'Pending') return t.isPending;
          if (_selectedFilter == 'Draft') return t.isDraft;
          return true;
        }).toList();

        final sampleClientName = widget.repository.customers.isNotEmpty
            ? widget.repository.customers.first.name
            : 'Ananya Sharma';
        final biz = widget.repository.settings.businessName.isNotEmpty
            ? widget.repository.settings.businessName
            : 'Our Spa & Wellness';

        return Scaffold(
          appBar: AppBar(
            title: const Text('WhatsApp Templates'),
            actions: [
              IconButton(
                tooltip: 'Sync with Meta WhatsApp Platform',
                icon: _isSyncing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.sync_rounded),
                onPressed: _isSyncing ? null : _syncWithMeta,
              ),
              IconButton(
                tooltip: 'Create Template',
                icon: const Icon(Icons.add_rounded),
                onPressed: _openCreateTemplate,
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            heroTag: 'fab_templates',
            onPressed: _openCreateTemplate,
            backgroundColor: AppColors.primarySage,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.add_rounded),
            label: const Text('New Template', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
          body: SafeArea(
            child: Column(
              children: [
                const DemoRibbon(
                  label: 'WHATSAPP CLOUD API • APPROVED TEMPLATE MANAGEMENT SYSTEM',
                ),

                // Filter chips
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      _buildFilterChip('All (${allTemplates.length})', 'All', isDark),
                      const SizedBox(width: 8),
                      _buildFilterChip(
                        'Approved (${widget.repository.approvedTemplates.length})',
                        'Approved',
                        isDark,
                        badgeColor: AppColors.success,
                      ),
                      const SizedBox(width: 8),
                      _buildFilterChip(
                        'Pending (${widget.repository.pendingTemplates.length})',
                        'Pending',
                        isDark,
                        badgeColor: AppColors.accentGold,
                      ),
                      const SizedBox(width: 8),
                      _buildFilterChip(
                        'Draft (${widget.repository.draftTemplates.length})',
                        'Draft',
                        isDark,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 4),

                // Template List
                Expanded(
                  child: filtered.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.style_outlined, size: 48, color: AppColors.textMuted),
                              const SizedBox(height: 12),
                              Text(
                                'No ${_selectedFilter != 'All' ? _selectedFilter : ''} templates found',
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton.icon(
                                onPressed: _openCreateTemplate,
                                icon: const Icon(Icons.add_rounded),
                                label: const Text('Create First Template'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primarySage,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.only(left: 16, right: 16, top: 8, bottom: 80),
                          itemCount: filtered.length,
                          separatorBuilder: (context, index) => const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final tpl = filtered[index];
                            final previewText = tpl.resolvePreview(
                              customerName: sampleClientName,
                              businessName: biz,
                            );

                            return _buildTemplateCard(
                              tpl: tpl,
                              previewText: previewText,
                              isDark: isDark,
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFilterChip(String label, String value, bool isDark, {Color? badgeColor}) {
    final isSelected = _selectedFilter == value;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      labelStyle: TextStyle(
        fontSize: 11.5,
        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
        color: isSelected ? Colors.white : (isDark ? AppColors.textLight : AppColors.textCharcoal),
      ),
      selectedColor: AppColors.primarySage,
      backgroundColor: isDark ? AppColors.surfaceDark : Colors.white,
      onSelected: (val) => setState(() => _selectedFilter = value),
    );
  }

  Widget _buildTemplateCard({
    required WhatsAppTemplate tpl,
    required String previewText,
    required bool isDark,
  }) {
    Color statusBg;
    Color statusFg;
    String statusLabel;
    IconData statusIcon;

    if (tpl.isApproved) {
      statusBg = const Color(0xFFE8F5E9);
      statusFg = AppColors.success;
      statusLabel = 'Approved (Can Send)';
      statusIcon = Icons.check_circle_rounded;
    } else if (tpl.isPending) {
      statusBg = const Color(0xFFFFF8E1);
      statusFg = const Color(0xFFD97706);
      statusLabel = 'Pending Meta Approval';
      statusIcon = Icons.hourglass_top_rounded;
    } else if (tpl.isRejected) {
      statusBg = const Color(0xFFFFEBEE);
      statusFg = AppColors.error;
      statusLabel = 'Rejected by Meta';
      statusIcon = Icons.cancel_rounded;
    } else {
      statusBg = Colors.grey.shade200;
      statusFg = Colors.grey.shade700;
      statusLabel = 'Draft (Cannot Send)';
      statusIcon = Icons.edit_note_rounded;
    }

    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row: Display Name + Status Badge
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tpl.displayName,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          'Meta: ${tpl.name}',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            color: isDark ? AppColors.textMutedDark : AppColors.textMuted,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            tpl.language,
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey.shade800),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppColors.primarySageContainer.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            tpl.category,
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.primarySageDark),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(statusIcon, size: 13, color: statusFg),
                    const SizedBox(width: 4),
                    Text(
                      statusLabel,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: statusFg,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Message preview
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E2D24) : AppColors.whatsAppBg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              previewText,
              style: TextStyle(
                fontSize: 12.5,
                color: isDark ? AppColors.textLight : AppColors.textCharcoal,
                height: 1.35,
              ),
            ),
          ),

          // Variables & Meta Parameter Mappings
          if (tpl.variables.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: tpl.variables.asMap().entries.map((e) {
                final idx = e.key + 1;
                final varName = e.value;
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.surfaceDark : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Text(
                    '{$varName} → {{$idx}}',
                    style: const TextStyle(fontSize: 10.5, fontFamily: 'monospace', fontWeight: FontWeight.w600),
                  ),
                );
              }).toList(),
            ),
          ],

          const SizedBox(height: 14),

          // Action row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Admin manual approval button for testing / WhatsApp Manager approval sync
              if (!tpl.isApproved)
                TextButton.icon(
                  onPressed: () async {
                    await widget.repository.updateTemplateStatus(tpl.id, 'approved', metaStatus: 'APPROVED');
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          backgroundColor: AppColors.success,
                          content: Text('Template "${tpl.displayName}" marked Approved and sendable.'),
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.verified_rounded, size: 14, color: AppColors.success),
                  label: const Text('Mark Approved', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.success)),
                )
              else
                const SizedBox.shrink(),

              // Use in campaign button (STRICTLY enabled only when approved!)
              ElevatedButton.icon(
                onPressed: tpl.canSend
                    ? () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => CampaignWizardScreen(
                              repository: widget.repository,
                              preselectedTemplateId: tpl.id,
                            ),
                          ),
                        );
                      }
                    : null,
                icon: const Icon(Icons.send_rounded, size: 14),
                label: Text(
                  tpl.canSend ? 'Use in Campaign' : 'Approval Required',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primarySage,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey.shade300,
                  disabledForegroundColor: Colors.grey.shade600,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
