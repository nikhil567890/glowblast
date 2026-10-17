import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../data/models/customer.dart';
import '../../../data/repositories/app_repository.dart';
import '../../../services/excel_service.dart';
import 'customer_detail_screen.dart';
import 'add_edit_customer_screen.dart';
import 'excel_import_screen.dart';
import 'groups_screen.dart';
import '../../campaigns/screens/campaign_wizard_screen.dart';
import '../../campaigns/screens/direct_send_screen.dart';

class CustomersScreen extends StatefulWidget {
  final AppRepository repository;

  const CustomersScreen({super.key, required this.repository});

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _selectedFilter = 'All'; // 'All', 'Recently Added', 'Opted-Out'
  String _searchQuery = '';
  bool _isSelectionMode = false;
  final Set<String> _selectedCustomerIds = {};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }


  List<Customer> _filterCustomers(List<Customer> customers) {
    var list = customers;

    switch (_selectedFilter) {
      case 'Marketing Opt-In':
        list = customers.where((c) => !c.isOptedOut && c.hasMarketingConsent).toList();
        break;
      case 'Unconsented':
        list = customers.where((c) => !c.isOptedOut && !c.hasMarketingConsent).toList();
        break;
      case 'Recently Added':
        list = widget.repository.recentlyAddedCustomers;
        break;
      case 'Opted-Out':
        list = widget.repository.optedOutCustomers;
        break;
      case 'All':
      default:
        break;
    }

    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      final qDigits = ExcelService.extractClean10Digits(_searchQuery);

      list = list.where((c) {
        final nameMatch = c.name.toLowerCase().contains(q);
        final phoneClean = ExcelService.extractClean10Digits(c.phone);
        final phoneMatch = phoneClean.contains(qDigits.isNotEmpty ? qDigits : q);
        return nameMatch || phoneMatch;
      }).toList();
    }

    return list;
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

  void _showBulkConsentDialog(AppRepository repo) async {
    if (_selectedCustomerIds.isEmpty) return;

    if (!repo.isAuthenticated) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You must be logged in to record consent. Please sign in and try again.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final sourceController = TextEditingController(text: 'Front Desk Verbal Agreement');
    final evidenceController = TextEditingController(text: 'Customer In-Person Verbal Opt-In');
    bool isSubmitting = false;
    int progressProcessed = 0;
    int progressTotal = _selectedCustomerIds.length;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.verified_user_rounded, color: AppColors.whatsApp),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text('Record Verbal Marketing Consent', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F5E9),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.whatsApp.withValues(alpha: 0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Selected Customers: ${_selectedCustomerIds.length}',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.whatsApp),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Only record consent for customers who have explicitly and verbally agreed to receive WhatsApp promotional broadcasts.',
                            style: TextStyle(fontSize: 11.5, color: Colors.black87),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Recorded by: ${repo.currentUser?.email ?? repo.currentUser?.name ?? "Authenticated Admin"}\nDate: ${DateTime.now().toLocal().toString().split(".")[0]}',
                            style: const TextStyle(fontSize: 11, color: Colors.black54),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text('Consent Source', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    TextField(
                      controller: sourceController,
                      enabled: !isSubmitting,
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: 'e.g. Verbal in-person agreement',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text('Evidence Reference', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    TextField(
                      controller: evidenceController,
                      enabled: !isSubmitting,
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: 'e.g. Customer In-Person Verbal Opt-In',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    if (isSubmitting) ...[
                      const SizedBox(height: 16),
                      LinearProgressIndicator(
                        value: progressTotal > 0 ? (progressProcessed / progressTotal) : null,
                        backgroundColor: Colors.grey.shade200,
                        valueColor: const AlwaysStoppedAnimation<Color>(AppColors.whatsApp),
                      ),
                      const SizedBox(height: 8),
                      Center(
                        child: Text(
                          'Recording consent: $progressProcessed / $progressTotal',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppColors.whatsApp,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting ? null : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.whatsApp,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          setDialogState(() {
                            isSubmitting = true;
                            progressProcessed = 0;
                            progressTotal = _selectedCustomerIds.length;
                          });
                          final messenger = ScaffoldMessenger.of(context);
                          final dialogNav = Navigator.of(dialogContext);

                          final result = await repo.bulkRecordMarketingConsent(
                            customerIds: _selectedCustomerIds.toList(),
                            source: sourceController.text.trim(),
                            evidence: evidenceController.text.trim(),
                            onProgress: (processed, total) {
                              if (dialogContext.mounted) {
                                setDialogState(() {
                                  progressProcessed = processed;
                                  progressTotal = total;
                                });
                              }
                            },
                          );

                          dialogNav.pop();
                          if (!mounted) return;

                          final succeeded = result['succeeded'] ?? 0;
                          final failed = result['failed'] ?? 0;
                          final isSuccess = result['success'] == true;
                          final failedIds = (result['failedCustomerIds'] as List?)?.cast<String>() ?? [];

                          setState(() {
                            if (isSuccess || failedIds.isEmpty) {
                              _selectedCustomerIds.clear();
                              _isSelectionMode = false;
                            } else {
                              // Retain only remaining failures for retry
                              _selectedCustomerIds.clear();
                              _selectedCustomerIds.addAll(failedIds);
                              _isSelectionMode = true;
                            }
                          });

                          messenger.showSnackBar(
                            SnackBar(
                              backgroundColor: isSuccess ? AppColors.whatsApp : (succeeded > 0 ? AppColors.warning : AppColors.error),
                              duration: const Duration(seconds: 5),
                              content: Text(
                                isSuccess
                                    ? 'Marketing consent recorded for $succeeded customers.'
                                    : 'Recorded $succeeded / ${result['totalRequested']} ($failed failed). Remaining $failed failed customers are kept selected for retry.',
                              ),
                            ),
                          );
                        },
                  child: isSubmitting
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text('Record Consent (${_selectedCustomerIds.length})'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showBulkEditDialog(AppRepository repo) async {
    if (_selectedCustomerIds.isEmpty) return;

    final groups = repo.groups;
    if (groups.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No customer groups available to assign.')),
      );
      return;
    }

    String selectedGroupId = groups.first.id;
    bool isAssigning = true; // true = add to group, false = remove from group

    await showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.edit_note_rounded, color: AppColors.primarySage),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Edit ${_selectedCustomerIds.length} Customers',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primarySageContainer.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'Shared attributes (Group / Tag) will be updated across all selected customers. Individual customer names and phone numbers remain strictly preserved.',
                    style: TextStyle(fontSize: 12, height: 1.35),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Action', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 6),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: true, label: Text('Add to Group'), icon: Icon(Icons.group_add_rounded, size: 16)),
                    ButtonSegment(value: false, label: Text('Remove'), icon: Icon(Icons.group_remove_rounded, size: 16)),
                  ],
                  selected: {isAssigning},
                  onSelectionChanged: (set) => setDialogState(() => isAssigning = set.first),
                ),
                const SizedBox(height: 16),
                const Text('Select Target Group', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  initialValue: selectedGroupId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: groups.map((g) {
                    return DropdownMenuItem(
                      value: g.id,
                      child: Text('${g.name} (${g.customerIds.length} members)'),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) setDialogState(() => selectedGroupId = val);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primarySage,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                Navigator.pop(dialogCtx);
                int count;
                if (isAssigning) {
                  count = await repo.bulkAssignGroup(
                    customerIds: _selectedCustomerIds.toList(),
                    groupId: selectedGroupId,
                  );
                } else {
                  count = await repo.bulkRemoveFromGroup(
                    customerIds: _selectedCustomerIds.toList(),
                    groupId: selectedGroupId,
                  );
                }
                if (!mounted) return;
                setState(() {
                  _selectedCustomerIds.clear();
                  _isSelectionMode = false;
                });
                final grpName = groups.firstWhere((g) => g.id == selectedGroupId).name;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(isAssigning
                        ? '✓ Added $count customers to group "$grpName".'
                        : '✓ Removed $count customers from group "$grpName".'),
                    backgroundColor: AppColors.primarySage,
                  ),
                );
              },
              child: const Text('Apply Changes'),
            ),
          ],
        ),
      ),
    );
  }

  void _showBulkDeleteDialog(AppRepository repo) async {
    if (_selectedCustomerIds.isEmpty) return;

    bool isDeleting = false;
    final count = _selectedCustomerIds.length;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.delete_forever_rounded, color: AppColors.error),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Delete $count Customers?',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Are you sure you want to delete $count selected customer record${count == 1 ? "" : "s"}?',
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFCA5A5)),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '🛡️ Relational Database Safeguards:',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.error),
                    ),
                    SizedBox(height: 4),
                    Text(
                      '• Consent history and audit trails are securely preserved for compliance.\n'
                      '• Past campaign delivery and read reports remain intact.\n'
                      '• Opt-out registries remain protected.\n'
                      '• Customer profile entries will be unlinked safely.',
                      style: TextStyle(fontSize: 11.5, color: Colors.black87, height: 1.4),
                    ),
                  ],
                ),
              ),
              if (isDeleting) ...[
                const SizedBox(height: 16),
                const Row(
                  children: [
                    SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                    SizedBox(width: 12),
                    Text('Deleting customers safely...', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ],
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: isDeleting ? null : () => Navigator.pop(dialogCtx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white,
              ),
              onPressed: isDeleting
                  ? null
                  : () async {
                      setDialogState(() => isDeleting = true);
                      final idsToDelete = _selectedCustomerIds.toList();

                      final result = await repo.bulkDeleteCustomers(idsToDelete);

                      if (dialogCtx.mounted) {
                        Navigator.pop(dialogCtx);
                      }
                      if (!mounted) return;

                      if (result['success'] == true) {
                        setState(() {
                          _selectedCustomerIds.clear();
                          _isSelectionMode = false;
                        });
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('✓ Successfully deleted ${result["deletedCount"]} customer records.'),
                            backgroundColor: AppColors.success,
                          ),
                        );
                      } else {
                        // Keep selected customers for retry on error
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Deletion failed: ${result["error"]?["message"] ?? "Server error"}'),
                            backgroundColor: AppColors.error,
                          ),
                        );
                      }
                    },
              child: isDeleting
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text('Delete ($count)'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.repository,
      builder: (context, _) {
        final repo = widget.repository;
        final allCustomers = repo.customers;
        final filteredList = _filterCustomers(allCustomers);
        final isDark = Theme.of(context).brightness == Brightness.dark;

        return Scaffold(
          appBar: AppBar(
            leading: _isSelectionMode
                ? IconButton(
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'Cancel Selection',
                    onPressed: () {
                      setState(() {
                        _isSelectionMode = false;
                        _selectedCustomerIds.clear();
                      });
                    },
                  )
                : null,
            title: Text(_isSelectionMode
                ? '${_selectedCustomerIds.length} Selected'
                : 'Customers (${allCustomers.length})'),
            actions: _isSelectionMode
                ? [
                    TextButton(
                      onPressed: () {
                        setState(() {
                          if (_selectedCustomerIds.length == filteredList.length) {
                            _selectedCustomerIds.clear();
                          } else {
                            _selectedCustomerIds.addAll(filteredList.map((c) => c.id));
                          }
                        });
                      },
                      child: Text(
                        _selectedCustomerIds.length == filteredList.length ? 'Deselect All' : 'Select All',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ]
                : [
                    IconButton(
                      tooltip: 'Select Customers',
                      icon: const Icon(Icons.playlist_add_check_rounded),
                      onPressed: () {
                        setState(() {
                          _isSelectionMode = true;
                          _selectedCustomerIds.clear();
                        });
                      },
                    ),
                    IconButton(
                      tooltip: 'Customer Groups',
                      icon: const Icon(Icons.folder_shared_outlined),
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => GroupsScreen(repository: widget.repository),
                          ),
                        );
                      },
                    ),
                    IconButton(
                      tooltip: 'Import Excel',
                      icon: const Icon(Icons.file_download_outlined),
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => ExcelImportScreen(repository: widget.repository),
                          ),
                        );
                      },
                    ),
                  ],
          ),
          bottomNavigationBar: _isSelectionMode && _selectedCustomerIds.isNotEmpty
              ? Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.surfaceDark : Colors.white,
                    border: Border(top: BorderSide(color: isDark ? AppColors.borderDark : AppColors.borderLight)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 8,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: SafeArea(
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.primarySage,
                              padding: const EdgeInsets.symmetric(vertical: 10),
                            ),
                            child: const Text('Edit', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                            onPressed: () => _showBulkEditDialog(repo),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.error,
                              side: const BorderSide(color: AppColors.error),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                            ),
                            child: const Text('Delete', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                            onPressed: () => _showBulkDeleteDialog(repo),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.whatsApp,
                              side: const BorderSide(color: AppColors.whatsApp),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                            ),
                            child: const Text('Consent', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                            onPressed: () => _showBulkConsentDialog(repo),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.whatsApp,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 10),
                            ),
                            icon: const Icon(Icons.send_rounded, size: 14),
                            label: const Text('Send', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                            onPressed: () {
                              if (_selectedCustomerIds.isEmpty) return;
                              if (_selectedCustomerIds.length == 1) {
                                final singleCustomer = repo.customers.firstWhere(
                                  (c) => c.id == _selectedCustomerIds.first,
                                  orElse: () => Customer(
                                    id: _selectedCustomerIds.first,
                                    name: 'Customer',
                                    phone: '',
                                    createdAt: DateTime.now(),
                                  ),
                                );
                                _openComposerForCustomer(singleCustomer);
                              } else {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (context) => CampaignWizardScreen(
                                      repository: widget.repository,
                                      preselectedAudience: 'Custom',
                                      preselectedCustomerIds: _selectedCustomerIds,
                                    ),
                                  ),
                                );
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : null,
          floatingActionButton: _isSelectionMode
              ? null
              : FloatingActionButton.extended(
                  heroTag: 'fab_customers',
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => AddEditCustomerScreen(repository: widget.repository),
                      ),
                    );
                  },
                  backgroundColor: AppColors.primarySage,
                  foregroundColor: Colors.white,
                  icon: const Icon(Icons.person_add_rounded),
                  label: const Text('Add Customer', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
          body: SafeArea(
            child: Column(
              children: [

                // Search Bar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (val) => setState(() => _searchQuery = val.trim()),
                    decoration: InputDecoration(
                      hintText: 'Search by full name or 10-digit phone...',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: isDark ? AppColors.surfaceDark : Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: isDark ? AppColors.borderDark : AppColors.borderLight),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: isDark ? AppColors.borderDark : AppColors.borderLight),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                ),

                // Meaningful Filter Pills
                SizedBox(
                  height: 40,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      _buildFilterChip('All', 'All (${allCustomers.length})', isDark),
                      const SizedBox(width: 8),
                      _buildFilterChip('Marketing Opt-In', 'Marketing Opt-In (${repo.marketingConsentedCustomers.length})', isDark),
                      const SizedBox(width: 8),
                      _buildFilterChip('Unconsented', 'Unconsented (${allCustomers.where((c) => !c.isOptedOut && !c.hasMarketingConsent).length})', isDark),
                      const SizedBox(width: 8),
                      _buildFilterChip('Opted-Out', 'Opted-Out (${repo.optedOutCustomersCount})', isDark),
                    ],
                  ),
                ),

                const SizedBox(height: 8),

                // Customer List View
                Expanded(
                  child: filteredList.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.search_off_rounded, size: 48, color: AppColors.textMuted),
                              const SizedBox(height: 12),
                              Text(
                                _searchQuery.isNotEmpty
                                    ? 'No customers matching "$_searchQuery"'
                                    : 'No customers found in this filter',
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.only(left: 16, right: 16, top: 8, bottom: 84),
                          itemCount: filteredList.length,
                          separatorBuilder: (context, index) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final customer = filteredList[index];

                            return AppCard(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              child: InkWell(
                                onLongPress: () {
                                  setState(() {
                                    _isSelectionMode = true;
                                    _selectedCustomerIds.add(customer.id);
                                  });
                                },
                                onTap: () {
                                  if (_isSelectionMode) {
                                    setState(() {
                                      if (_selectedCustomerIds.contains(customer.id)) {
                                        _selectedCustomerIds.remove(customer.id);
                                        if (_selectedCustomerIds.isEmpty) {
                                          _isSelectionMode = false;
                                        }
                                      } else {
                                        _selectedCustomerIds.add(customer.id);
                                      }
                                    });
                                    return;
                                  }
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (context) => CustomerDetailScreen(
                                        repository: widget.repository,
                                        customerId: customer.id,
                                      ),
                                    ),
                                  );
                                },
                                child: Row(
                                  children: [
                                    if (_isSelectionMode) ...[
                                      Checkbox(
                                        value: _selectedCustomerIds.contains(customer.id),
                                        activeColor: AppColors.primarySage,
                                        onChanged: (val) {
                                          setState(() {
                                            if (val == true) {
                                              _selectedCustomerIds.add(customer.id);
                                            } else {
                                              _selectedCustomerIds.remove(customer.id);
                                              if (_selectedCustomerIds.isEmpty) {
                                                _isSelectionMode = false;
                                              }
                                            }
                                          });
                                        },
                                      ),
                                      const SizedBox(width: 4),
                                    ],
                                    // Initials Avatar
                                    CircleAvatar(
                                      radius: 20,
                                      backgroundColor: customer.isOptedOut
                                          ? Colors.grey.shade300
                                          : AppColors.primarySageContainer,
                                      child: Text(
                                        customer.name.isNotEmpty
                                            ? customer.name.substring(0, 1).toUpperCase()
                                            : '?',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14,
                                          color: customer.isOptedOut
                                              ? Colors.grey.shade700
                                              : AppColors.primarySageDark,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),

                                    // Name and Phone
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Flexible(
                                                child: Text(
                                                  customer.name,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w700,
                                                    fontSize: 14.5,
                                                  ),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                              if (customer.isOptedOut) ...[
                                                const SizedBox(width: 6),
                                                StatusBadge.optedOut(),
                                              ] else if (customer.hasMarketingConsent) ...[
                                                const SizedBox(width: 6),
                                                StatusBadge.marketingConsent(),
                                              ] else ...[
                                                const SizedBox(width: 6),
                                                StatusBadge.noConsent(),
                                              ],
                                            ],
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            customer.phone,
                                            style: TextStyle(
                                              fontSize: 12.5,
                                              color: isDark ? AppColors.textMutedDark : AppColors.textMuted,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),

                                    // WhatsApp Action Icon
                                    if (!_isSelectionMode)
                                      IconButton(
                                        tooltip: 'WhatsApp Message',
                                        icon: Icon(
                                          Icons.chat_rounded,
                                          color: customer.isOptedOut ? Colors.grey : AppColors.whatsApp,
                                          size: 22,
                                        ),
                                        onPressed: () => _openComposerForCustomer(customer),
                                      ),
                                  ],
                                ),
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

  Widget _buildFilterChip(String key, String label, bool isDark) {
    final isSelected = _selectedFilter == key;

    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
        color: isSelected ? Colors.white : (isDark ? AppColors.textLight : AppColors.textCharcoal),
      ),
      selectedColor: AppColors.primarySage,
      backgroundColor: isDark ? AppColors.surfaceDark : Colors.white,
      onSelected: (val) => setState(() => _selectedFilter = key),
    );
  }
}
