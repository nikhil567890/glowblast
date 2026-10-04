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
    final descController = TextEditingController();
    final selectedIds = <String>{};

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final customers = widget.repository.eligibleCustomers;

            return Padding(
              padding: EdgeInsets.only(
                top: 20,
                left: 20,
                right: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Create Custom Customer Group', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'Group Name (e.g. Regular Patrons)'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: descController,
                    decoration: const InputDecoration(labelText: 'Description'),
                  ),
                  const SizedBox(height: 16),
                  Text('Select Customers (${selectedIds.length} chosen)', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 200,
                    child: ListView.builder(
                      itemCount: customers.length,
                      itemBuilder: (context, index) {
                        final c = customers[index];
                        final isSelected = selectedIds.contains(c.id);
                        return CheckboxListTile(
                          dense: true,
                          value: isSelected,
                          title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                          subtitle: Text(c.phone, style: const TextStyle(fontSize: 11)),
                          onChanged: (val) {
                            setModalState(() {
                              if (val == true) {
                                selectedIds.add(c.id);
                              } else {
                                selectedIds.remove(c.id);
                              }
                            });
                          },
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  PrimaryButton(
                    text: 'Save Group (${selectedIds.length} Members)',
                    onPressed: () async {
                      if (nameController.text.trim().isEmpty) return;
                      final group = CustomerGroup(
                        id: 'grp_${DateTime.now().millisecondsSinceEpoch}',
                        name: nameController.text.trim(),
                        description: descController.text.trim(),
                        customerIds: selectedIds.toList(),
                      );
                      Navigator.of(context).pop();
                      await widget.repository.addGroup(group);
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
