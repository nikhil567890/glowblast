import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/demo_ribbon.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../data/models/group.dart';
import '../../../data/repositories/app_repository.dart';
import '../../campaigns/screens/campaign_wizard_screen.dart';

class GroupsScreen extends StatefulWidget {
  final AppRepository repository;

  const GroupsScreen({super.key, required this.repository});

  @override
  State<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends State<GroupsScreen> {
  void _createNewGroupDialog() {
    final nameController = TextEditingController();
    final searchController = TextEditingController();
    final selectedIds = <String>{};
    String searchQuery = '';
    String? validationError;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? AppColors.cardDark
          : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            final allCustomers = widget.repository.eligibleCustomers;

            // Fast case-insensitive search by name and phone
            final filteredCustomers = allCustomers.where((c) {
              if (searchQuery.isEmpty) return true;
              final q = searchQuery.toLowerCase();
              final matchesName = c.name.toLowerCase().contains(q);
              final matchesPhone = c.phone.replaceAll(' ', '').contains(q);
              return matchesName || matchesPhone;
            }).toList();

            return Container(
              height: MediaQuery.of(context).size.height * 0.88,
              padding: EdgeInsets.only(
                top: 12,
                left: 20,
                right: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Drag Handle
                  Center(
                    child: Container(
                      width: 44,
                      height: 4,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white24 : Colors.black12,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),

                  const SizedBox(height: 14),

                  // Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Create Customer Group',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: isDark ? AppColors.textLight : AppColors.textCharcoal,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(context),
                        tooltip: 'Close',
                      ),
                    ],
                  ),

                  const SizedBox(height: 10),

                  // Group Name Input
                  TextField(
                    controller: nameController,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: 'Group Name',
                      hintText: 'e.g. VIP Facial Clients, Weekend regulars',
                      prefixIcon: const Icon(Icons.label_outline_rounded, size: 20),
                      filled: true,
                      fillColor: isDark ? AppColors.surfaceDark : AppColors.warmCream,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      errorText: validationError,
                    ),
                    onChanged: (_) {
                      if (validationError != null) {
                        setModalState(() => validationError = null);
                      }
                    },
                  ),

                  const SizedBox(height: 12),

                  // Customer Search Field (name, phone, email)
                  TextField(
                    controller: searchController,
                    decoration: InputDecoration(
                      hintText: 'Search customers by name or phone...',
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      suffixIcon: searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, size: 18),
                              onPressed: () {
                                searchController.clear();
                                setModalState(() => searchQuery = '');
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: isDark ? AppColors.surfaceDark : AppColors.warmCream,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onChanged: (val) {
                      setModalState(() => searchQuery = val.trim());
                    },
                  ),

                  const SizedBox(height: 12),

                  // Selection Header with Quick Actions
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Select Customers (${selectedIds.length} chosen)',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: isDark ? AppColors.textLight : AppColors.textCharcoal,
                        ),
                      ),
                      Row(
                        children: [
                          GestureDetector(
                            onTap: () {
                              setModalState(() {
                                for (final c in filteredCustomers) {
                                  selectedIds.add(c.id);
                                }
                              });
                            },
                            child: const Text(
                              'Select All',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primarySage,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          GestureDetector(
                            onTap: () {
                              setModalState(() => selectedIds.clear());
                            },
                            child: Text(
                              'Clear',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: isDark ? AppColors.textMutedDark : AppColors.textMuted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  const SizedBox(height: 8),

                  // Customer List (Designed to show at least 6 contacts comfortably)
                  Expanded(
                    child: filteredCustomers.isEmpty
                        ? Center(
                            child: Text(
                              searchQuery.isEmpty
                                  ? 'No eligible customers found.'
                                  : 'No customers match "$searchQuery"',
                              style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
                            ),
                          )
                        : ListView.builder(
                            itemCount: filteredCustomers.length,
                            itemExtent: 54, // Ensures compact comfortable height showing 6+ rows
                            itemBuilder: (context, index) {
                              final customer = filteredCustomers[index];
                              final isSelected = selectedIds.contains(customer.id);

                              return InkWell(
                                onTap: () {
                                  setModalState(() {
                                    if (isSelected) {
                                      selectedIds.remove(customer.id);
                                    } else {
                                      selectedIds.add(customer.id);
                                    }
                                  });
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                                  child: Row(
                                    children: [
                                      // Contact Avatar
                                      Container(
                                        width: 38,
                                        height: 38,
                                        decoration: BoxDecoration(
                                          color: isSelected
                                              ? AppColors.primarySage.withValues(alpha: 0.18)
                                              : (isDark ? AppColors.surfaceDark : Colors.grey.shade100),
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(
                                            color: isSelected
                                                ? AppColors.primarySage
                                                : Colors.transparent,
                                          ),
                                        ),
                                        child: Center(
                                          child: Text(
                                            customer.name.isNotEmpty
                                                ? customer.name.substring(0, 1).toUpperCase()
                                                : 'C',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 14,
                                              color: isSelected
                                                  ? AppColors.primarySage
                                                  : (isDark ? Colors.white70 : Colors.black87),
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),

                                      // Name & Phone
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Text(
                                              customer.name,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 13.5,
                                                color: isDark ? AppColors.textLight : AppColors.textCharcoal,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              customer.phone,
                                              style: TextStyle(
                                                fontSize: 11.5,
                                                color: isDark ? AppColors.textMutedDark : AppColors.textMuted,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),

                                      // Checkbox
                                      Checkbox(
                                        value: isSelected,
                                        activeColor: AppColors.primarySage,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        onChanged: (val) {
                                          setModalState(() {
                                            if (val == true) {
                                              selectedIds.add(customer.id);
                                            } else {
                                              selectedIds.remove(customer.id);
                                            }
                                          });
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),

                  const SizedBox(height: 12),

                  // Save Group Fixed Button
                  PrimaryButton(
                    text: selectedIds.isNotEmpty
                        ? 'Save Group (${selectedIds.length} Members)'
                        : 'Save Group',
                    icon: Icons.check_circle_outline_rounded,
                    onPressed: () async {
                      final name = nameController.text.trim();
                      if (name.isEmpty) {
                        setModalState(() => validationError = 'Please enter a group name');
                        return;
                      }
                      if (selectedIds.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Please select at least 1 customer for the group.'),
                            backgroundColor: AppColors.error,
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                        return;
                      }

                      final newGroup = CustomerGroup(
                        id: 'grp_${DateTime.now().millisecondsSinceEpoch}',
                        name: name,
                        description: '',
                        customerIds: selectedIds.toList(),
                      );

                      final messenger = ScaffoldMessenger.of(this.context);
                      Navigator.of(context).pop();
                      await widget.repository.addGroup(newGroup);

                      if (!mounted) return;
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text("✓ Customer group '$name' created with ${selectedIds.length} members."),
                          backgroundColor: AppColors.primarySageDark,
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                  ),
                ],
              ),
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
        final groups = widget.repository.groups;
        final isDark = Theme.of(context).brightness == Brightness.dark;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Customer Groups'),
            actions: [
              IconButton(
                icon: const Icon(Icons.group_add_rounded),
                onPressed: _createNewGroupDialog,
              ),
            ],
          ),
          body: SafeArea(
            child: Column(
              children: [
                const DemoRibbon(label: 'CUSTOMER SEGMENTS & GROUPS'),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                    itemCount: groups.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final group = groups[index];
                      return AppCard(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: AppColors.primarySageContainer,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Icon(Icons.groups_rounded, color: AppColors.primarySage, size: 20),
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      group.name,
                                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                                    ),
                                  ],
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: isDark ? const Color(0xFF26332A) : AppColors.primarySageContainer,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    '${group.customerIds.length} Clients',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.primarySage,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (group.description.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(
                                group.description,
                                style: TextStyle(fontSize: 12.5, color: isDark ? AppColors.textMutedDark : AppColors.textMuted),
                              ),
                            ],
                            const SizedBox(height: 14),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton.icon(
                                  icon: const Icon(Icons.delete_outline_rounded, size: 16, color: AppColors.error),
                                  label: const Text('Delete', style: TextStyle(color: AppColors.error)),
                                  onPressed: () async {
                                    await widget.repository.deleteGroup(group.id);
                                  },
                                ),
                                const SizedBox(width: 8),
                                ElevatedButton.icon(
                                  onPressed: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (context) => CampaignWizardScreen(
                                          repository: widget.repository,
                                          preselectedAudience: group.name,
                                        ),
                                      ),
                                    );
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.primarySage,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                    textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                                  ),
                                  icon: const Icon(Icons.send_rounded, size: 14),
                                  label: const Text('Send Offer to Group'),
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
      },
    );
  }
}
