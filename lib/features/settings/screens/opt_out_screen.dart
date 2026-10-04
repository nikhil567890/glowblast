import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/demo_ribbon.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../data/repositories/app_repository.dart';

class OptOutScreen extends StatefulWidget {
  final AppRepository repository;

  const OptOutScreen({super.key, required this.repository});

  @override
  State<OptOutScreen> createState() => _OptOutScreenState();
}

class _OptOutScreenState extends State<OptOutScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showAddOptOutDialog() {
    final eligible = widget.repository.eligibleCustomers;
    String? selectedCustId;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Add Client to Opt-Out List'),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Select a customer who requested to be excluded from promotional messages:'),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: selectedCustId,
                      hint: const Text('Select customer'),
                      items: eligible.take(50).map((c) {
                        return DropdownMenuItem(value: c.id, child: Text('${c.name} (${c.phone})', overflow: TextOverflow.ellipsis));
                      }).toList(),
                      onChanged: (val) => setDialogState(() => selectedCustId = val),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
                  onPressed: selectedCustId == null
                      ? null
                      : () async {
                          await widget.repository.toggleOptOut(selectedCustId!, true);
                          if (!context.mounted) return;
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Customer added to Opt-Out list.')),
                          );
                        },
                  child: const Text('Confirm Opt-Out', style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.repository,
      builder: (context, _) {
        final optedOutList = widget.repository.optedOutCustomers;
        final isDark = Theme.of(context).brightness == Brightness.dark;

        final filtered = _searchQuery.isEmpty
            ? optedOutList
            : optedOutList.where((c) {
                final q = _searchQuery.toLowerCase();
                return c.name.toLowerCase().contains(q) || c.phone.contains(q);
              }).toList();

        return Scaffold(
          appBar: AppBar(
            title: Text('Opt-Out Management (${optedOutList.length})'),
            actions: [
              IconButton(
                icon: const Icon(Icons.person_add_disabled_rounded),
                tooltip: 'Add Customer to Opt-Out',
                onPressed: _showAddOptOutDialog,
              ),
            ],
          ),
          body: SafeArea(
            child: Column(
              children: [
                const DemoRibbon(label: 'COMPLIANCE & CONSENT • 12 EXCLUDED CLIENTS'),

                // Search field
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (val) => setState(() => _searchQuery = val.trim()),
                    decoration: InputDecoration(
                      hintText: 'Search opted-out customers...',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                    ),
                  ),
                ),

                // Compliance Note Box
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.surfaceDark : const Color(0xFFE8F4FD),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFBEE3F8)),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.privacy_tip_outlined, color: Color(0xFF2B6CB0), size: 20),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Compliance Guarantee: Customers on this list are automatically and permanently excluded from all promotional WhatsApp blasts.',
                            style: TextStyle(fontSize: 12, color: Color(0xFF2B6CB0), height: 1.35),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 8),

                Expanded(
                  child: filtered.isEmpty
                      ? const Center(
                          child: Text('No customers found in opt-out list.', style: TextStyle(color: AppColors.textMuted)),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: filtered.length,
                          separatorBuilder: (context, index) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final c = filtered[index];
                            return AppCard(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 20,
                                    backgroundColor: Colors.grey.shade200,
                                    child: const Icon(Icons.block_rounded, size: 18, color: Colors.grey),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          c.name,
                                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                                        ),
                                        Text(
                                          c.phone,
                                          style: TextStyle(fontSize: 12, color: isDark ? AppColors.textMutedDark : AppColors.textMuted),
                                        ),
                                      ],
                                    ),
                                  ),
                                  StatusBadge.optedOut(),
                                  const SizedBox(width: 8),
                                  TextButton(
                                    style: TextButton.styleFrom(
                                      foregroundColor: AppColors.primarySage,
                                      padding: const EdgeInsets.symmetric(horizontal: 8),
                                    ),
                                    onPressed: () async {
                                      await widget.repository.toggleOptOut(c.id, false);
                                      if (!context.mounted) return;
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Re-subscribed ${c.name} to promotions.')),
                                      );
                                    },
                                    child: const Text('Re-subscribe', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
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
      },
    );
  }
}
