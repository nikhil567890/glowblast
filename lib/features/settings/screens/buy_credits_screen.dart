import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/widgets/demo_ribbon.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../data/repositories/app_repository.dart';

class BuyCreditsScreen extends StatefulWidget {
  final AppRepository repository;

  const BuyCreditsScreen({super.key, required this.repository});

  @override
  State<BuyCreditsScreen> createState() => _BuyCreditsScreenState();
}

class _BuyCreditsScreenState extends State<BuyCreditsScreen> {
  int _selectedPack = 1; // 0: Starter (1k), 1: Growth (5k), 2: Scale (10k)

  void _simulatePurchase(int credits, String packTitle) async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Top Up Demo Credits?'),
        content: Text(
          'Add $credits WhatsApp broadcast credits ($packTitle) to your demo wallet?\n\nNote: ${AppStrings.demoPricingDisclaimer}.',
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
              await widget.repository.addCredits(credits);
              if (!context.mounted) return;
              Navigator.pop(context); // dialog
              Navigator.pop(context); // screen
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('✓ Added $credits WhatsApp credits to your demo wallet!'),
                  backgroundColor: AppColors.success,
                ),
              );
            },
            child: const Text('Confirm Top-Up'),
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
        title: const Text('Recharge WhatsApp Credits'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            const DemoRibbon(label: AppStrings.demoPricingDisclaimer),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'WhatsApp Credit Packs',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: isDark ? AppColors.textLight : AppColors.textCharcoal,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '1 credit = 1 WhatsApp broadcast message. Select a demo pack to top up your available balance.',
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? AppColors.textMutedDark : AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Starter Pack
                    _buildPackCard(
                      index: 0,
                      title: 'Starter Pack',
                      credits: 1000,
                      description: 'Ideal for weekly wellness announcements',
                      badge: 'BASIC',
                      isPopular: false,
                      isDark: isDark,
                    ),
                    const SizedBox(height: 14),

                    // Growth Pack
                    _buildPackCard(
                      index: 1,
                      title: 'Growth Pack',
                      credits: 5000,
                      description: 'Great for festive promotions & monthly blasts',
                      badge: 'MOST POPULAR',
                      isPopular: true,
                      isDark: isDark,
                    ),
                    const SizedBox(height: 14),

                    // Scale Pack
                    _buildPackCard(
                      index: 2,
                      title: 'Scale Pack',
                      credits: 10000,
                      description: 'Maximum capacity for peak festival broadcasts',
                      badge: 'ENTERPRISE',
                      isPopular: false,
                      isDark: isDark,
                    ),

                    const SizedBox(height: 28),

                    PrimaryButton(
                      text: 'Simulate Top-Up',
                      icon: Icons.add_circle_outline_rounded,
                      onPressed: () {
                        if (_selectedPack == 0) _simulatePurchase(1000, 'Starter Pack');
                        if (_selectedPack == 1) _simulatePurchase(5000, 'Growth Pack');
                        if (_selectedPack == 2) _simulatePurchase(10000, 'Scale Pack');
                      },
                    ),

                    const SizedBox(height: 20),

                    // Demo notice
                    AppCard(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline_rounded, color: AppColors.accentGold, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'In this simulation, credit top-ups are instant and do not require payment gateways.',
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark ? AppColors.textMutedDark : AppColors.textMuted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPackCard({
    required int index,
    required String title,
    required int credits,
    required String description,
    required String badge,
    required bool isPopular,
    required bool isDark,
  }) {
    final isSelected = _selectedPack == index;

    return InkWell(
      onTap: () => setState(() => _selectedPack = index),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? AppColors.primarySageDark.withValues(alpha: 0.35) : AppColors.primarySageContainer.withValues(alpha: 0.7))
              : (isDark ? AppColors.cardDark : Colors.white),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppColors.primarySage : (isDark ? AppColors.borderDark : AppColors.borderLight),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: isDark ? AppColors.textLight : AppColors.textCharcoal,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: isPopular ? AppColors.accentGoldContainer : (isDark ? AppColors.borderDark : Colors.grey.shade100),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isPopular ? AppColors.accentGoldLight : Colors.transparent,
                          ),
                        ),
                        child: Text(
                          badge,
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            color: isPopular ? AppColors.accentGoldDark : AppColors.textMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? AppColors.textMutedDark : AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '$credits WhatsApp Credits',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primarySage,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              isSelected ? Icons.check_circle_rounded : Icons.radio_button_off_rounded,
              color: isSelected ? AppColors.primarySage : Colors.grey,
              size: 26,
            ),
          ],
        ),
      ),
    );
  }
}
