import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../data/models/customer.dart';
import '../../../data/repositories/app_repository.dart';
import 'add_edit_customer_screen.dart';
import '../../campaigns/screens/direct_send_screen.dart';

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

  Future<void> _showRecordConsentDialog(
    Customer customer, {
    String initialCategory = 'marketing',
    String initialStatus = 'opted_in',
  }) async {
    String selectedStatus = initialStatus;
    final sourceController = TextEditingController(text: 'Front Desk Digital Tablet');
    final evidenceController = TextEditingController(
      text: 'Intake Form #${customer.id.split('_').last}',
    );
    final textVersionController = TextEditingController(
      text: 'v2026.1_promotional',
    );
    bool isSubmitting = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final isDark = Theme.of(context).brightness == Brightness.dark;

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                Icon(
                  selectedStatus == 'opted_in' ? Icons.verified_user_rounded : Icons.block_rounded,
                  color: selectedStatus == 'opted_in' ? AppColors.whatsApp : AppColors.error,
                  size: 22,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    selectedStatus == 'opted_in' ? 'Record Marketing Consent' : 'Record Opt-Out / Revocation',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Customer: ${customer.name} (${customer.phone})',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: isDark ? AppColors.textMutedDark : AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Status (Opt-In vs Opt-Out vs Revoked)
                    const Text('Status Action', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      initialValue: selectedStatus,
                      decoration: InputDecoration(
                        isDense: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'opted_in', child: Text('Opted-In (Active Consent)')),
                        DropdownMenuItem(value: 'opted_out', child: Text('Opted-Out (Customer Requested)')),
                        DropdownMenuItem(value: 'revoked', child: Text('Revoked (Consent Withdrawn)')),
                      ],
                      onChanged: (val) {
                        if (val != null) setDialogState(() => selectedStatus = val);
                      },
                    ),
                    const SizedBox(height: 12),

                    // Consent Source
                    const Text('Consent Source', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: sourceController,
                      style: const TextStyle(fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'e.g. Front Desk Digital Tablet, Physical Signed Waiver',
                        isDense: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Auditable Evidence Reference
                    const Text('Auditable Evidence / Document ID', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: evidenceController,
                      style: const TextStyle(fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'e.g. Signed Form Ref #1042, Online Booking #8821',
                        isDense: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Consent Text Version
                    const Text('Consent Policy / Text Version', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: textVersionController,
                      style: const TextStyle(fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'e.g. v2026.1_promotional',
                        isDense: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Compliance notice
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.amber.shade700, width: 0.5),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.shield_outlined, size: 16, color: Colors.amber.shade900),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Production broadcasts require authentic customer consent. Never fabricate evidence or timestamps. All changes are cryptographically audited on the server.',
                              style: TextStyle(fontSize: 11, color: Colors.amber.shade900, height: 1.3),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSubmitting ? null : () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: selectedStatus == 'opted_in' ? AppColors.whatsApp : AppColors.error,
                  foregroundColor: Colors.white,
                ),
                onPressed: isSubmitting
                    ? null
                    : () async {
                        final messenger = ScaffoldMessenger.of(context);
                        final dialogNav = Navigator.of(dialogContext);

                        if (sourceController.text.trim().isEmpty || evidenceController.text.trim().isEmpty) {
                          messenger.showSnackBar(
                            const SnackBar(content: Text('Source and Evidence reference are required.')),
                          );
                          return;
                        }

                        setDialogState(() => isSubmitting = true);
                        final result = await widget.repository.recordCustomerConsent(
                          customerId: customer.id,
                          category: 'marketing',
                          status: selectedStatus,
                          source: sourceController.text.trim(),
                          evidence: evidenceController.text.trim(),
                          consentTextVersion: textVersionController.text.trim(),
                          allowOptOutOverride: true,
                        );

                        if (!mounted) {
                          return;
                        }
                        dialogNav.pop();
                        setState(() {});

                        final isSuccess = result['success'] == true;
                        if (!isSuccess) {
                          // Reload authoritative state from server
                          await widget.repository.syncConsentsFromBackend();
                          if (mounted) setState(() {});
                        }
                        messenger.showSnackBar(
                          SnackBar(
                            backgroundColor: isSuccess ? AppColors.whatsApp : AppColors.error,
                            content: Text(
                              isSuccess
                                  ? 'Consent recorded: MARKETING → ${selectedStatus.toUpperCase()} for ${customer.name}'
                                  : 'Failed to record consent: ${result['error']?['message'] ?? 'Unknown error'}',
                            ),
                          ),
                        );
                      },
                child: isSubmitting
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(selectedStatus == 'opted_in' ? 'Save & Persist Opt-In' : 'Save Opt-Out'),
              ),
            ],
          );
        },
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
        builder: (context) => DirectSendScreen(
          repository: widget.repository,
          customer: customer,
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

    final dateFormat = DateFormat('dd MMM yyyy, hh:mm a');

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
                                : (customer.hasMarketingConsent
                                    ? AppColors.primarySageContainer
                                    : const Color(0xFFFFF3E0)),
                            child: Text(
                              customer.name.isNotEmpty
                                  ? customer.name.substring(0, 1).toUpperCase()
                                  : '?',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                                color: customer.isOptedOut
                                    ? Colors.grey.shade700
                                    : (customer.hasMarketingConsent
                                        ? AppColors.primarySageDark
                                        : const Color(0xFFE65100)),
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
                        Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            alignment: WrapAlignment.center,
                            children: [
                              if (customer.isOptedOut)
                                StatusBadge.optedOut()
                              else if (customer.hasMarketingConsent)
                                StatusBadge.marketingConsent()
                              else
                                StatusBadge.noConsent(),
                            ],
                          ),
                          const SizedBox(height: 18),

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

                    // WhatsApp Customer Consent Management Card
                    AppCard(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.verified_user_rounded, color: AppColors.whatsApp, size: 20),
                                  SizedBox(width: 8),
                                  Text(
                                    'WhatsApp Consent Status',
                                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                                  ),
                                ],
                              ),
                              IconButton(
                                icon: const Icon(Icons.sync_rounded, size: 18),
                                tooltip: 'Sync consents from backend',
                                onPressed: () async {
                                  await widget.repository.syncConsentsFromBackend();
                                  if (mounted) setState(() {});
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Authoritative WhatsApp opt-in records required for live Meta broadcasts. Client-only flags are rejected by the backend.',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: isDark ? AppColors.textMutedDark : AppColors.textMuted,
                            ),
                          ),
                          const Divider(height: 24),

                          // 1. Marketing Consent Section
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        const Text(
                                          'Marketing Broadcasts',
                                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                                        ),
                                        const SizedBox(width: 8),
                                        if (customer.isOptedOut)
                                          StatusBadge.optedOut()
                                        else if (customer.hasMarketingConsent)
                                          StatusBadge.marketingConsent()
                                        else
                                          StatusBadge.noConsent(),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      customer.hasMarketingConsent && !customer.isOptedOut
                                          ? 'Eligible for festive promotions, discounts, and marketing campaigns.'
                                          : (customer.isOptedOut
                                              ? 'Customer opted out from all marketing communications.'
                                              : 'Unconsented: Cannot be included in production marketing broadcasts.'),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: isDark ? AppColors.textMutedDark : AppColors.textMuted,
                                      ),
                                    ),
                                    if (customer.hasMarketingConsent && customer.marketingConsentRecordedAt != null) ...[
                                      const SizedBox(height: 6),
                                      Text(
                                        'Recorded: ${dateFormat.format(customer.marketingConsentRecordedAt!)}',
                                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                                      ),
                                      if (customer.marketingConsentSource != null)
                                        Text(
                                          'Source: ${customer.marketingConsentSource}',
                                          style: TextStyle(fontSize: 11, color: isDark ? AppColors.textMutedDark : AppColors.textMuted),
                                        ),
                                      if (customer.marketingConsentEvidence != null)
                                        Text(
                                          'Evidence: ${customer.marketingConsentEvidence}',
                                          style: TextStyle(fontSize: 11, color: isDark ? AppColors.textMutedDark : AppColors.textMuted),
                                        ),
                                      if (customer.marketingConsentTextVersion != null)
                                        Text(
                                          'Policy: ${customer.marketingConsentTextVersion}',
                                          style: TextStyle(fontSize: 11, color: isDark ? AppColors.textMutedDark : AppColors.textMuted),
                                        ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            children: [
                              OutlinedButton.icon(
                                icon: const Icon(Icons.check_circle_outline_rounded, size: 16),
                                label: Text(customer.hasMarketingConsent ? 'Update Marketing Opt-In' : 'Record Marketing Opt-In'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.whatsApp,
                                  side: const BorderSide(color: AppColors.whatsApp),
                                  visualDensity: VisualDensity.compact,
                                ),
                                onPressed: () => _showRecordConsentDialog(
                                  customer,
                                  initialCategory: 'marketing',
                                  initialStatus: 'opted_in',
                                ),
                              ),
                              if (customer.hasMarketingConsent || !customer.isOptedOut)
                                OutlinedButton.icon(
                                  icon: const Icon(Icons.block_rounded, size: 16),
                                  label: const Text('Record Opt-Out'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.error,
                                    side: const BorderSide(color: AppColors.error),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  onPressed: () => _showRecordConsentDialog(
                                    customer,
                                    initialCategory: 'marketing',
                                    initialStatus: 'opted_out',
                                  ),
                                ),
                            ],
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
