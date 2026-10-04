import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/demo_ribbon.dart';
import '../../../core/widgets/app_card.dart';
import '../../../data/demo_data/initial_data.dart';
import '../../../data/repositories/app_repository.dart';
import '../../campaigns/screens/campaign_wizard_screen.dart';

class TemplatesScreen extends StatefulWidget {
  final AppRepository repository;

  const TemplatesScreen({super.key, required this.repository});

  @override
  State<TemplatesScreen> createState() => _TemplatesScreenState();
}

class _TemplatesScreenState extends State<TemplatesScreen> {
  String _selectedCategory = 'All';

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final allTemplates = InitialData.templates;

    final categories = ['All', 'Festival', 'Occasion', 'Weekend', 'Win-Back', 'Service', 'Loyalty', 'Membership'];

    final filtered = _selectedCategory == 'All'
        ? allTemplates
        : allTemplates.where((t) => t['category'] == _selectedCategory).toList();

    final biz = widget.repository.settings.businessName.isNotEmpty
        ? widget.repository.settings.businessName
        : 'Our Spa & Wellness';
    final sampleClientName = widget.repository.customers.isNotEmpty
        ? widget.repository.customers.first.name
        : 'Ananya Sharma';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Promotional Templates'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            const DemoRibbon(label: '12 PRE-WRITTEN PROMOTIONAL TEMPLATES • WHATSAPP ONLY'),

            // Category filter chips
            SizedBox(
              height: 48,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                itemCount: categories.length,
                separatorBuilder: (context, index) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final cat = categories[index];
                  final isSelected = _selectedCategory == cat;
                  return ChoiceChip(
                    label: Text(cat),
                    selected: isSelected,
                    labelStyle: TextStyle(
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: isSelected ? Colors.white : (isDark ? AppColors.textLight : AppColors.textCharcoal),
                    ),
                    selectedColor: AppColors.primarySage,
                    backgroundColor: isDark ? AppColors.surfaceDark : Colors.white,
                    onSelected: (val) => setState(() => _selectedCategory = cat),
                  );
                },
              ),
            ),

            const SizedBox(height: 6),

            // Templates List
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                itemCount: filtered.length,
                separatorBuilder: (context, index) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final tpl = filtered[index];
                  final previewText = tpl['body']!
                      .replaceAll('{name}', sampleClientName)
                      .replaceAll('{customer_name}', sampleClientName)
                      .replaceAll('{spa_name}', biz)
                      .replaceAll('{business_name}', biz);

                  return AppCard(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              tpl['title']!,
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppColors.primarySageContainer,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                tpl['offer'] ?? tpl['category']!,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primarySageDark,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          previewText,
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark ? AppColors.textMutedDark : AppColors.textMuted,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            ElevatedButton.icon(
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (context) => CampaignWizardScreen(
                                      repository: widget.repository,
                                      preselectedTemplateId: tpl['id'],
                                    ),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.send_rounded, size: 14),
                              label: const Text('Use in Campaign', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primarySage,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
