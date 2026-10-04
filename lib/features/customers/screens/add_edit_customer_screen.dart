import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../data/models/customer.dart';
import '../../../data/repositories/app_repository.dart';
import '../../../services/excel_service.dart';

class AddEditCustomerScreen extends StatefulWidget {
  final AppRepository repository;
  final Customer? existingCustomer;

  const AddEditCustomerScreen({
    super.key,
    required this.repository,
    this.existingCustomer,
  });

  @override
  State<AddEditCustomerScreen> createState() => _AddEditCustomerScreenState();
}

class _AddEditCustomerScreenState extends State<AddEditCustomerScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final c = widget.existingCustomer;
    _nameController = TextEditingController(text: c?.name ?? '');

    String phoneText = '';
    if (c != null && c.phone.isNotEmpty) {
      final digits = ExcelService.extractClean10Digits(c.phone);
      phoneText = digits;
    }
    _phoneController = TextEditingController(text: phoneText);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _saveCustomer() async {
    if (!_formKey.currentState!.validate()) return;

    final name = _nameController.text.trim();
    final rawPhone = _phoneController.text.trim();
    final inputDigits = ExcelService.extractClean10Digits(rawPhone);

    // Duplicate phone check
    final isNew = widget.existingCustomer == null;
    final exists = widget.repository.customers.any((c) {
      if (!isNew && c.id == widget.existingCustomer!.id) return false;
      return ExcelService.extractClean10Digits(c.phone) == inputDigits;
    });

    if (exists) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('A customer with this mobile number already exists in your directory.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    final formattedPhone = ExcelService.formatIndianPhone(inputDigits);

    if (isNew) {
      final newCustomer = Customer(
        id: 'cust_${DateTime.now().millisecondsSinceEpoch}',
        name: name,
        phone: formattedPhone,
        isOptedOut: false,
      );
      await widget.repository.addCustomer(newCustomer);
    } else {
      final updated = widget.existingCustomer!.copyWith(
        name: name,
        phone: formattedPhone,
      );
      await widget.repository.updateCustomer(updated);
    }

    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(isNew ? '✓ Customer added successfully.' : '✓ Customer updated.'),
        backgroundColor: AppColors.success,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.existingCustomer == null;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(isNew ? 'Add Customer' : 'Edit Customer'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isNew ? 'Create New Client' : 'Update Client Contact',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: isDark ? AppColors.textLight : AppColors.textCharcoal,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Only full name and 10-digit mobile number are required for WhatsApp campaigns.',
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? AppColors.textMutedDark : AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 24),

                // Form Card
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.cardDark : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: isDark ? AppColors.borderDark : AppColors.borderLight),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Full Name
                      const Text('Full Name', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _nameController,
                        textCapitalization: TextCapitalization.words,
                        decoration: InputDecoration(
                          hintText: 'e.g. Aarav Sharma',
                          prefixIcon: const Icon(Icons.person_outline_rounded, size: 20),
                          filled: true,
                          fillColor: isDark ? AppColors.surfaceDark : AppColors.warmCream,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter the customer\'s full name';
                          }
                          return null;
                        },
                      ),

                      const SizedBox(height: 20),

                      // Phone Number
                      const Text('Phone Number', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        decoration: InputDecoration(
                          hintText: '98765 43210',
                          prefixText: '+91 ',
                          prefixIcon: const Icon(Icons.phone_outlined, size: 20),
                          prefixStyle: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: isDark ? AppColors.textLight : AppColors.textCharcoal,
                          ),
                          filled: true,
                          fillColor: isDark ? AppColors.surfaceDark : AppColors.warmCream,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter a 10-digit mobile number';
                          }
                          final digits = ExcelService.extractClean10Digits(value);
                          if (digits.length != 10) {
                            return 'Mobile number must be exactly 10 digits';
                          }
                          if (!RegExp(r'^[6-9]\d{9}$').hasMatch(digits)) {
                            return 'Must start with 6, 7, 8, or 9';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 28),

                PrimaryButton(
                  text: isNew ? 'Save Customer' : 'Update Customer',
                  icon: isNew ? Icons.check_circle_outline_rounded : Icons.save_rounded,
                  isLoading: _isLoading,
                  onPressed: _saveCustomer,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
