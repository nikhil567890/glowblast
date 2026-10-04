import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/demo_ribbon.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../data/models/customer.dart';
import '../../../data/repositories/app_repository.dart';
import 'add_edit_customer_screen.dart';
import '../../campaigns/screens/campaign_wizard_screen.dart';

class CustomerDetailScreen extends StatefulWidget {
  final AppRepository repository;
  final String customerId;

  const CustomerDetailScreen({
    super.key,
    required this.repository,
    required this.customerId,
  });

  @override
  State<CustomerDetailScreen> createState() => _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends State<CustomerDetailScreen> {
  Customer? _getCustomer() {
    try {
      return widget.repository.customers.firstWhere((c) => c.id == widget.customerId);
    } catch (_) {
      return null;
    }
  }

  void _confirmDelete(Customer customer) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Customer?'),
        content: Text('Are you sure you want to remove ${customer.name} from the database? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () async {
              final nav = Navigator.of(context);
              final messenger = ScaffoldMessenger.of(context);
              nav.pop(); // dialog
              await widget.repository.deleteCustomer(customer.id);
              if (!mounted) return;
              nav.pop(); // screen
              messenger.showSnackBar(
                SnackBar(content: Text('${customer.name} was removed.')),
              );
            },
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _toggleOptOut(Customer customer) async {
    await widget.repository.toggleOptOut(customer.id, !customer.isOptedOut);
    setState(() {});
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          !customer.isOptedOut
              ? '${customer.name} has been opted-out from promotional messaging.'
              : '${customer.name} is now re-subscribed to promotional messaging.',
        ),
      ),
    );
  }

  void _openComposerForCustomer(Customer customer) {
    if (customer.isOptedOut) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${customer.name} is opted out from promotional broadcasts.')),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => CampaignWizardScreen(
          repository: widget.repository,
          preselectedAudience: 'Custom',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final customer = _getCustomer();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (customer == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Customer Not Found')),
        body: const Center(child: Text('Customer was not found or was removed.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(customer.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => AddEditCustomerScreen(
                    repository: widget.repository,
                    existingCustomer: customer,
                  ),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, color: AppColors.error),
            onPressed: () => _confirmDelete(customer),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            const DemoRibbon(label: 'CUSTOMER DETAILS • NAME & PHONE ONLY'),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
                child: Column(
                  children: [
                    // Profile Header Card
                    AppCard(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          CircleAvatar(
                            radius: 36,
                            backgroundColor: customer.isOptedOut
                                ? Colors.grey.shade300
                                : AppColors.primarySageContainer,
                            child: Text(
                              customer.name.isNotEmpty
                                  ? customer.name.substring(0, 1).toUpperCase()
                                  : '?',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                                color: customer.isOptedOut
                                    ? Colors.grey.shade700
                                    : AppColors.primarySageDark,
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            customer.name,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: isDark ? AppColors.textLight : AppColors.textCharcoal,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            customer.phone,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primarySage,
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (customer.isOptedOut)
                            StatusBadge.optedOut()
                          else
                            StatusBadge.regular(),
                          const SizedBox(height: 20),

                          // WhatsApp Broadcast Action Button
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.whatsApp,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            icon: const Icon(Icons.chat_rounded, size: 18),
                            label: const Text(
                              'Send WhatsApp Message',
                              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                            ),
                            onPressed: () => _openComposerForCustomer(customer),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Compliance / Opt-out Toggle Card
                    AppCard(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Promotional Broadcasts',
                                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  customer.isOptedOut
                                      ? 'Customer is excluded from all WhatsApp campaigns.'
                                      : 'Eligible to receive promotional WhatsApp campaigns.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDark ? AppColors.textMutedDark : AppColors.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: !customer.isOptedOut,
                            activeThumbColor: AppColors.primarySage,
                            onChanged: (_) => _toggleOptOut(customer),
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
}
