import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/demo_ribbon.dart';
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

  void _exportExcel() async {
    try {
      final bytes = ExcelService.exportCustomersToExcelBytes(widget.repository.customers);
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/glowblast_customers_export.xlsx');
      await file.writeAsBytes(bytes);

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: 'GlowBlast Customer Directory (${widget.repository.customers.length} records)',
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export error: $e'), backgroundColor: AppColors.error),
      );
    }
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
        builder: (context) => CampaignWizardScreen(
          repository: widget.repository,
          preselectedAudience: 'Custom',
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
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: 'e.g. Customer In-Person Verbal Opt-In',
                        border: OutlineInputBorder(),
                      ),
                    ),
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
                          setDialogState(() => isSubmitting = true);
                          final messenger = ScaffoldMessenger.of(context);
                          final dialogNav = Navigator.of(dialogContext);

                          final result = await repo.bulkRecordMarketingConsent(
                            customerIds: _selectedCustomerIds.toList(),
                            source: sourceController.text.trim(),
                            evidence: evidenceController.text.trim(),
                          );

                          dialogNav.pop();
                          if (!mounted) return;

                          final succeeded = result['succeeded'] ?? 0;
                          final failed = result['failed'] ?? 0;
                          final isSuccess = result['success'] == true;

                          setState(() {
                            _selectedCustomerIds.clear();
                            _isSelectionMode = false;
                          });

                          messenger.showSnackBar(
                            SnackBar(
                              backgroundColor: isSuccess ? AppColors.whatsApp : (succeeded > 0 ? AppColors.warning : AppColors.error),
                              content: Text(
                                isSuccess
                                    ? 'Marketing consent recorded for $succeeded customers.'
                                    : 'Recorded $succeeded / ${result['totalRequested']} ($failed failed: ${result['failures']?[0]?['error'] ?? 'Unknown error'})',
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
                      tooltip: 'Select Customers for Verbal Consent',
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
                      tooltip: 'Export Excel',
                      icon: const Icon(Icons.file_upload_outlined),
                      onPressed: _exportExcel,
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
          floatingActionButton: _isSelectionMode
              ? (_selectedCustomerIds.isNotEmpty
                  ? FloatingActionButton.extended(
                      heroTag: 'fab_bulk_consent',
                      onPressed: () => _showBulkConsentDialog(repo),
                      backgroundColor: AppColors.whatsApp,
                      foregroundColor: Colors.white,
                      icon: const Icon(Icons.verified_user_rounded),
                      label: Text('Record Marketing Consent (${_selectedCustomerIds.length})',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                    )
                  : null)
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
                const DemoRibbon(label: 'CLIENT DIRECTORY • LOCAL DATABASE'),

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
